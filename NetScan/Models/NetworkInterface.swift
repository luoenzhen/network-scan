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
    
    public init(
        interfaceName: String = "en0",
        ipAddress: String = "192.168.1.105",
        subnetMask: String = "255.255.255.0",
        cidrPrefix: Int = 24,
        gatewayIP: String = "192.168.1.1",
        broadcastIP: String = "192.168.1.255",
        ssid: String = "Wi-Fi Network",
        bssid: String = "00:11:22:33:44:55",
        isConnected: Bool = true,
        interfaceType: String = "Wi-Fi (802.11ax)"
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
    }
    
    public var subnetDescription: String {
        return "\(gatewayIP)/\(cidrPrefix)"
    }
    
    public var estimatedHostCount: Int {
        if cidrPrefix >= 32 { return 1 }
        let hostBits = 32 - cidrPrefix
        let total = (1 << hostBits) - 2
        return max(total, 1)
    }
}
