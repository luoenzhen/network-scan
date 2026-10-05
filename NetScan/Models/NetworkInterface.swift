//
//  NetworkInterface.swift
//  NetScan
//
//  Represents network interface details (Wi-Fi, IP, subnet, gateway).
//

import Foundation

public struct NetworkInterfaceInfo: Codable, Equatable {
    public var interfaceName: String
    public var ipAddress: String
    public var subnetMask: String
    public var cidrPrefix: Int
    public var gatewayIP: String
    public var broadcastIP: String
    public var ssid: String
    public var bssid: String
    public var isConnected: Bool
    public var interfaceType: String
    public var isLAN: Bool
    
    public init(
        interfaceName: String = "en0",
        ipAddress: String = "",
        subnetMask: String = "",
        cidrPrefix: Int = 24,
        gatewayIP: String = "",
        broadcastIP: String = "",
        ssid: String = "Wi-Fi Network",
        bssid: String = "00:11:22:33:44:55",
        isConnected: Bool = false,
        interfaceType: String = "Wi-Fi (802.11ax)",
        isLAN: Bool = false
    ) {
        self.interfaceName = interfaceName
        self.ipAddress = ipAddress
        self.subnetMask = subnetMask
        self.cidrPrefix = cidrPrefix
        self.gatewayIP = gatewayIP
        self.broadcastIP = broadcastIP
        self.ssid = ssid
        self.bssid = bssid
        self.isConnected = isConnected
        self.interfaceType = interfaceType
        self.isLAN = isLAN
    }
    
    public var subnetDescription: String {
        guard isConnected else { return "Disconnected" }
        guard isLAN else { return "Cellular (No LAN Subnet)" }
        if !gatewayIP.isEmpty {
            return "\(gatewayIP)/\(cidrPrefix)"
        } else if !ipAddress.isEmpty {
            return "\(ipAddress)/\(cidrPrefix)"
        } else {
            return "Local Network"
        }
    }
    
    public var estimatedHostCount: Int {
        guard isConnected && isLAN else { return 0 }
        if cidrPrefix >= 32 { return 1 }
        let hostBits = 32 - cidrPrefix
        let total = (1 << hostBits) - 2
        return max(total, 1)
    }
    
    public var networkIdentifier: String {
        return "\(isLAN ? "LAN" : "WAN")_\(interfaceType)_\(ssid)_\(gatewayIP)_\(subnetMask)"
    }
}
