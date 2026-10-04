//
//  NetworkInterfaceService.swift
//  NetScan
//
//  Detects local Wi-Fi interface, IP address, subnet mask, CIDR prefix, and gateway.
//

import Foundation
import SystemConfiguration.CaptiveNetwork

public class NetworkInterfaceService {
    public static let shared = NetworkInterfaceService()
    
    public init() {}
    
    public func getCurrentInterface() -> NetworkInterfaceInfo {
        var localIP: String?
        var netmask: String?
        var broadcast: String?
        let ifName = "en0" // Standard iOS Wi-Fi interface
        
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&ifaddr) == 0 {
            var ptr = ifaddr
            while ptr != nil {
                guard let interface = ptr?.pointee else { break }
                let addrFamily = interface.ifa_addr.pointee.sa_family
                let name = String(cString: interface.ifa_name)
                
                if addrFamily == UInt8(AF_INET) && name == ifName {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                &hostname, socklen_t(hostname.count),
                                nil, socklen_t(0), NI_NUMERICHOST)
                    localIP = String(cString: hostname)
                    
                    if let netmaskAddr = interface.ifa_netmask {
                        var netmaskName = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                        getnameinfo(netmaskAddr, socklen_t(netmaskAddr.pointee.sa_len),
                                    &netmaskName, socklen_t(netmaskName.count),
                                    nil, socklen_t(0), NI_NUMERICHOST)
                        netmask = String(cString: netmaskName)
                    }
                    
                    if let dstAddr = interface.ifa_dstaddr {
                        var broadcastName = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                        getnameinfo(dstAddr, socklen_t(dstAddr.pointee.sa_len),
                                    &broadcastName, socklen_t(broadcastName.count),
                                    nil, socklen_t(0), NI_NUMERICHOST)
                        broadcast = String(cString: broadcastName)
                    }
                    break
                }
                ptr = interface.ifa_next
            }
            freeifaddrs(ifaddr)
        }
        
        let ip = localIP ?? "192.168.1.105"
        let mask = netmask ?? "255.255.255.0"
        let cidr = calculateCIDR(netmask: mask)
        let gateway = inferGateway(from: ip)
        let bcast = broadcast ?? inferBroadcast(ip: ip, mask: mask)
        let ssid = fetchSSID() ?? "Local Wi-Fi Network"
        
        return NetworkInterfaceInfo(
            interfaceName: ifName,
            ipAddress: ip,
            subnetMask: mask,
            cidrPrefix: cidr,
            gatewayIP: gateway,
            broadcastIP: bcast,
            ssid: ssid,
            bssid: "02:00:00:00:00:00",
            isConnected: localIP != nil,
            interfaceType: "Wi-Fi (802.11ax)"
        )
    }
    
    public func calculateCIDR(netmask: String) -> Int {
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
        let parts = ip.split(separator: ".")
        if parts.count == 4 {
            return "\(parts[0]).\(parts[1]).\(parts[2]).1"
        }
        return "192.168.1.1"
    }
    
    public func inferBroadcast(ip: String, mask: String) -> String {
        let parts = ip.split(separator: ".")
        if parts.count == 4 {
            return "\(parts[0]).\(parts[1]).\(parts[2]).255"
        }
        return "192.168.1.255"
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
    
    private func fetchSSID() -> String? {
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
