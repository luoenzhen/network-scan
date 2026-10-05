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
            self.lastKnownPath = path
            DispatchQueue.main.async {
                self.updateInterface(path: path)
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
                let addrFamily = interface.ifa_addr.pointee.sa_family
                let name = String(cString: interface.ifa_name)
                
                if addrFamily == UInt8(AF_INET) {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                &hostname, socklen_t(hostname.count),
                                nil, socklen_t(0), NI_NUMERICHOST)
                    let ipStr = String(cString: hostname)
                    
                    if ipStr != "127.0.0.1" && !ipStr.hasPrefix("127.") {
                        if name.hasPrefix("en") {
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
        let usesWiFi = path?.usesInterfaceType(.wifi) ?? (wifiIP != nil)
        let usesCellular = path?.usesInterfaceType(.cellular) ?? (cellularIP != nil && wifiIP == nil)
        let usesEthernet = path?.usesInterfaceType(.wiredEthernet) ?? false
        
        // 1. Wi-Fi / Local Area Network
        if usesWiFi, let ip = wifiIP {
            let mask = wifiNetmask ?? "255.255.255.0"
            let cidr = calculateCIDR(netmask: mask)
            let gateway = inferGateway(from: ip)
            let bcast = wifiBroadcast ?? inferBroadcast(ip: ip, mask: mask)
            let ssid = fetchSSID() ?? "Local Wi-Fi Network"
            
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
                interfaceType: "Wi-Fi (802.11ax)",
                isLAN: true
            )
        }
        
        // 2. Wired Ethernet (e.g. iPad USB-C adapter)
        if usesEthernet, let ip = wifiIP {
            let mask = wifiNetmask ?? "255.255.255.0"
            let cidr = calculateCIDR(netmask: mask)
            let gateway = inferGateway(from: ip)
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
        let parts = netmask.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return 24 }
        var bits = 0
        for part in parts {
            var b = part
            while b > 0 {
                bits += (b & 1)
                b >>= 1
            }
        }
        return (bits <= 0 || bits > 32) ? 24 : bits
    }
    
    public func inferGateway(from ip: String) -> String {
        return NetworkInterfaceService.inferGateway(from: ip)
    }
    
    public static func inferGateway(from ip: String) -> String {
        let parts = ip.split(separator: ".")
        if parts.count == 4 {
            return "\(parts[0]).\(parts[1]).\(parts[2]).1"
        }
        return ""
    }
    
    public func inferBroadcast(ip: String, mask: String) -> String {
        return NetworkInterfaceService.inferBroadcast(ip: ip, mask: mask)
    }
    
    public static func inferBroadcast(ip: String, mask: String) -> String {
        let parts = ip.split(separator: ".")
        if parts.count == 4 {
            return "\(parts[0]).\(parts[1]).\(parts[2]).255"
        }
        return ""
    }
    
    public func generateSubnetIPs(localIP: String, cidr: Int) -> [String] {
        let parts = localIP.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return [] }
        
        let p0 = parts[0]
        let p1 = parts[1]
        let p2 = parts[2]
        
        // Always generate a safe 1...254 host range for the /24 subnet:
        var ips: [String] = []
        ips.reserveCapacity(254)
        for host in 1...254 {
            ips.append("\(p0).\(p1).\(p2).\(host)")
        }
        return ips
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
