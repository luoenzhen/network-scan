//
//  NetworkInterfaceService.swift
//  NetScan
//
//  Detects local Wi-Fi / Cellular network interfaces, IP address, subnet mask, CIDR prefix, and gateway.
//  Monitors real-time network path transitions via NWPathMonitor.
//

import Foundation
import Network
import Combine
#if canImport(SystemConfiguration.CaptiveNetwork)
import SystemConfiguration.CaptiveNetwork
#endif
#if canImport(Darwin)
import Darwin
#endif

public extension Notification.Name {
    static let networkInterfaceDidChange = Notification.Name("com.netscan.networkInterfaceDidChange")
}

public class NetworkInterfaceService: ObservableObject {
    public static let shared = NetworkInterfaceService()
    
    @Published public private(set) var currentInterface: NetworkInterfaceInfo
    @Published public private(set) var hasResolvedPath = false
    
    private let pathMonitor: NWPathMonitor
    private let monitorQueue = DispatchQueue(label: "com.netscan.pathmonitor")
    private var lastKnownPath: NWPath?
    
    public init() {
        self.pathMonitor = NWPathMonitor()
        self.currentInterface = NetworkInterfaceService.detectCurrentInterface(path: nil)
        startMonitoring()
    }
    
    deinit {
        pathMonitor.cancel()
    }
    
    private func startMonitoring() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.lastKnownPath = path
                self.updateInterface(path: path)
                self.hasResolvedPath = true
            }
        }
        pathMonitor.start(queue: monitorQueue)
    }
    
    public func refreshInterface() {
        let updated = NetworkInterfaceService.detectCurrentInterface(path: lastKnownPath)
        DispatchQueue.main.async {
            if updated != self.currentInterface {
                self.currentInterface = updated
                NotificationCenter.default.post(name: .networkInterfaceDidChange, object: updated)
            }
        }
    }
    
    private func updateInterface(path: NWPath) {
        let updated = NetworkInterfaceService.detectCurrentInterface(path: path)
        if updated != self.currentInterface {
            self.currentInterface = updated
            NotificationCenter.default.post(name: .networkInterfaceDidChange, object: updated)
        }
    }
    
    public func getCurrentInterface() -> NetworkInterfaceInfo {
        return currentInterface
    }
    
    public static func detectCurrentInterface(path: NWPath? = nil) -> NetworkInterfaceInfo {
        let usesWiFi = path?.usesInterfaceType(.wifi) ?? false
        let usesEthernet = path?.usesInterfaceType(.wiredEthernet) ?? false
        let lanType: NWInterface.InterfaceType = usesEthernet ? .wiredEthernet : .wifi
        let lanName = path?.availableInterfaces.first(where: { $0.type == lanType })?.name
            ?? (path == nil ? "en0" : "")
        var wifiIP: String?
        var wifiNetmask: String?
        var wifiBroadcast: String?
        var wifiIfName = "en0"
        
        var cellularIP: String?
        var cellularIfName: String?
        
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&ifaddr) == 0 {
            var ptr = ifaddr
            while ptr != nil {
                guard let interface = ptr?.pointee else { break }
                guard let address = interface.ifa_addr else {
                    ptr = interface.ifa_next
                    continue
                }
                let addrFamily = address.pointee.sa_family
                let name = String(cString: interface.ifa_name)
                
                if addrFamily == UInt8(AF_INET) {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                &hostname, socklen_t(hostname.count),
                                nil, socklen_t(0), NI_NUMERICHOST)
                    let ipStr = String(cString: hostname)
                    
                    if ipStr != "127.0.0.1" && !ipStr.hasPrefix("127.") {
                        if name == lanName && wifiIP == nil {
                            wifiIP = ipStr
                            wifiIfName = name
                            
                            if let netmaskAddr = interface.ifa_netmask {
                                var netmaskName = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                                getnameinfo(netmaskAddr, socklen_t(netmaskAddr.pointee.sa_len),
                                            &netmaskName, socklen_t(netmaskName.count),
                                            nil, socklen_t(0), NI_NUMERICHOST)
                                wifiNetmask = String(cString: netmaskName)
                            }
                            
                            if let dstAddr = interface.ifa_dstaddr {
                                var broadcastName = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                                getnameinfo(dstAddr, socklen_t(dstAddr.pointee.sa_len),
                                            &broadcastName, socklen_t(broadcastName.count),
                                            nil, socklen_t(0), NI_NUMERICHOST)
                                wifiBroadcast = String(cString: broadcastName)
                            }
                        } else if name.hasPrefix("pdp_ip") {
                            if cellularIP == nil {
                                cellularIP = ipStr
                                cellularIfName = name
                            }
                        }
                    }
                }
                ptr = interface.ifa_next
            }
            freeifaddrs(ifaddr)
        }
        
        let pathStatus = path?.status
        let hasWiFi = path == nil ? wifiIP != nil : usesWiFi && !usesEthernet
        let usesCellular = path?.usesInterfaceType(.cellular) ?? (cellularIP != nil && wifiIP == nil)
        
        // 1. Wi-Fi / Local Area Network
        if hasWiFi, let ip = wifiIP {
            let mask = wifiNetmask ?? "255.255.255.0"
            let cidr = calculateCIDR(netmask: mask)
            let gateway = configuredGateway(path: path, ip: ip, mask: mask)
            let bcast = wifiBroadcast ?? inferBroadcast(ip: ip, mask: mask)
            let actualSSID = fetchSSID()
            let ssid = actualSSID ?? "Local Wi-Fi Network"
            
            return NetworkInterfaceInfo(
                interfaceName: wifiIfName,
                ipAddress: ip,
                subnetMask: mask,
                cidrPrefix: cidr,
                gatewayIP: gateway,
                broadcastIP: bcast,
                ssid: ssid,
                bssid: "02:00:00:00:00:00",
                isConnected: true,
                interfaceType: "Wi-Fi",
                isLAN: true,
                networkNameIsAvailable: actualSSID?.isEmpty == false
            )
        }
        
        // 2. Wired Ethernet (e.g. iPad USB-C adapter)
        if usesEthernet, let ip = wifiIP {
            let mask = wifiNetmask ?? "255.255.255.0"
            let cidr = calculateCIDR(netmask: mask)
            let gateway = configuredGateway(path: path, ip: ip, mask: mask)
            let bcast = wifiBroadcast ?? inferBroadcast(ip: ip, mask: mask)
            
            return NetworkInterfaceInfo(
                interfaceName: wifiIfName,
                ipAddress: ip,
                subnetMask: mask,
                cidrPrefix: cidr,
                gatewayIP: gateway,
                broadcastIP: bcast,
                ssid: "Ethernet LAN",
                bssid: "02:00:00:00:00:00",
                isConnected: true,
                interfaceType: "Ethernet (LAN)",
                isLAN: true
            )
        }
        
        // 3. Cellular (4G / 5G / LTE) - Mobile WAN connection, NOT a local subnet
        if usesCellular || (pathStatus == .satisfied && wifiIP == nil) {
            let cellIP = cellularIP ?? "Cellular WAN"
            return NetworkInterfaceInfo(
                interfaceName: cellularIfName ?? "pdp_ip0",
                ipAddress: cellIP,
                subnetMask: "",
                cidrPrefix: 0,
                gatewayIP: "",
                broadcastIP: "",
                ssid: "Cellular (4G / 5G)",
                bssid: "",
                isConnected: true,
                interfaceType: "Cellular (Mobile Data)",
                isLAN: false
            )
        }
        
        // 4. Offline / Airplane Mode / Disconnected
        return NetworkInterfaceInfo(
            interfaceName: "none",
            ipAddress: "Not Connected",
            subnetMask: "",
            cidrPrefix: 0,
            gatewayIP: "",
            broadcastIP: "",
            ssid: "No Connection",
            bssid: "",
            isConnected: false,
            interfaceType: "Disconnected",
            isLAN: false
        )
    }
    
    public func calculateCIDR(netmask: String) -> Int {
        return NetworkInterfaceService.calculateCIDR(netmask: netmask)
    }
    
    public static func calculateCIDR(netmask: String) -> Int {
        guard let mask = ipv4Value(netmask), (~mask & (~mask &+ 1)) == 0 else { return 24 }
        return mask.nonzeroBitCount
    }
    
    public func inferGateway(from ip: String) -> String {
        return NetworkInterfaceService.inferGateway(from: ip)
    }
    
    public static func inferGateway(from ip: String, mask: String = "255.255.255.0") -> String {
        guard let address = ipv4Value(ip), let netmask = ipv4Value(mask),
              (~netmask & (~netmask &+ 1)) == 0, netmask.nonzeroBitCount < 31 else { return "" }
        return ipv4String((address & netmask) + 1)
    }
    
    public func inferBroadcast(ip: String, mask: String) -> String {
        return NetworkInterfaceService.inferBroadcast(ip: ip, mask: mask)
    }
    
    public static func inferBroadcast(ip: String, mask: String) -> String {
        guard let address = ipv4Value(ip), let netmask = ipv4Value(mask),
              (~netmask & (~netmask &+ 1)) == 0 else { return "" }
        return ipv4String((address & netmask) | ~netmask)
    }
    
    public func generateSubnetIPs(localIP: String, cidr: Int) -> [String] {
        guard let address = Self.ipv4Value(localIP), (0...32).contains(cidr) else { return [] }
        let mask: UInt32 = cidr == 0 ? 0 : UInt32.max << (32 - cidr)
        let network = address & mask
        let broadcast = network | ~mask
        let first = cidr >= 31 ? network : network + 1
        let last = cidr >= 31 ? broadcast : broadcast - 1
        // Bound very large networks to a 4096-address window containing this device.
        let count = UInt64(last) - UInt64(first) + 1
        let start = count > 4096 ? max(first, min(address & 0xFFFFF000, last - 4095)) : first
        let end = UInt32(min(UInt64(last), UInt64(start) + 4095))
        return (start...end).map(Self.ipv4String)
    }

    private static func ipv4Value(_ text: String) -> UInt32? {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var value: UInt32 = 0
        for part in parts {
            guard !part.isEmpty, part.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let octet = UInt8(part) else { return nil }
            value = (value << 8) | UInt32(octet)
        }
        return value
    }

    private static func ipv4String(_ value: UInt32) -> String {
        "\((value >> 24) & 255).\((value >> 16) & 255).\((value >> 8) & 255).\(value & 255)"
    }

    private static func configuredGateway(path: NWPath?, ip: String, mask: String) -> String {
        guard let address = ipv4Value(ip), let netmask = ipv4Value(mask) else { return "" }
        for endpoint in path?.gateways ?? [] {
            if case .hostPort(let host, _) = endpoint, case .ipv4(let gateway) = host {
                let text = String(describing: gateway)
                if let value = ipv4Value(text), value & netmask == address & netmask {
                    return text
                }
            }
        }
        return ""
    }
    
    private static func fetchSSID() -> String? {
        #if os(iOS)
        if let interfaces = CNCopySupportedInterfaces() as? [String] {
            for interface in interfaces {
                if let info = CNCopyCurrentNetworkInfo(interface as CFString) as? [String: AnyObject],
                   let ssid = info[kCNNetworkInfoKeySSID as String] as? String {
                    return ssid
                }
            }
        }
        #endif
        return nil
    }
}
