//
//  NetworkDevice.swift
//  NetScan
//
//  Represents a discovered device on the local network with live traffic stats.
//

import Foundation

public enum DeviceType: String, Codable, CaseIterable {
    case router = "Router / Gateway"
    case phone = "Smartphone"
    case tablet = "Tablet"
    case computer = "Computer"
    case smartHome = "Smart Home / IoT"
    case printer = "Printer"
    case gaming = "Gaming Console"
    case tv = "Smart TV / Streaming"
    case unknown = "Network Device"
    
    public var iconName: String {
        switch self {
        case .router: return "wifi.router"
        case .phone: return "iphone"
        case .tablet: return "ipad"
        case .computer: return "laptopcomputer"
        case .smartHome: return "homekit"
        case .printer: return "printer"
        case .gaming: return "gamecontroller"
        case .tv: return "tv"
        case .unknown: return "network"
        }
    }
}

public struct NetworkDevice: Identifiable, Codable, Equatable {
    public var id: UUID
    public var ipAddress: String
    public var macAddress: String
    public var hostname: String
    public var vendor: String
    public var deviceType: DeviceType
    public var isOnline: Bool
    
    // Live traffic metrics in Kilobytes per second
    public var uploadSpeedKbps: Double
    public var downloadSpeedKbps: Double
    
    // Cumulative metrics
    public var totalBytesSent: UInt64
    public var totalBytesReceived: UInt64
    
    // Diagnostics
    public var latencyMs: Double
    public var openPorts: [Int]
    public var services: [String]
    
    // Timestamps
    public var firstDiscovered: Date
    public var lastSeen: Date
    public var isLocalDevice: Bool
    public var isGateway: Bool
    
    public init(
        id: UUID = UUID(),
        ipAddress: String,
        macAddress: String = "Unknown",
        hostname: String = "",
        vendor: String = "Generic Device",
        deviceType: DeviceType = .unknown,
        isOnline: Bool = true,
        uploadSpeedKbps: Double = 0.0,
        downloadSpeedKbps: Double = 0.0,
        totalBytesSent: UInt64 = 0,
        totalBytesReceived: UInt64 = 0,
        latencyMs: Double = 0.0,
        openPorts: [Int] = [],
        services: [String] = [],
        firstDiscovered: Date = Date(),
        lastSeen: Date = Date(),
        isLocalDevice: Bool = false,
        isGateway: Bool = false
    ) {
        self.id = id
        self.ipAddress = ipAddress
        self.macAddress = macAddress
        self.hostname = hostname.isEmpty ? ipAddress : hostname
        self.vendor = vendor
        self.deviceType = deviceType
        self.isOnline = isOnline
        self.uploadSpeedKbps = uploadSpeedKbps
        self.downloadSpeedKbps = downloadSpeedKbps
        self.totalBytesSent = totalBytesSent
        self.totalBytesReceived = totalBytesReceived
        self.latencyMs = latencyMs
        self.openPorts = openPorts
        self.services = services
        self.firstDiscovered = firstDiscovered
        self.lastSeen = lastSeen
        self.isLocalDevice = isLocalDevice
        self.isGateway = isGateway
    }
    
    public var displayName: String {
        if !hostname.isEmpty && hostname != ipAddress {
            return hostname
        }
        if isGateway {
            return "Gateway (\(vendor))"
        }
        if isLocalDevice {
            return "This iPhone (\(vendor))"
        }
        return "\(vendor) (\(ipAddress))"
    }
    
    public var formattedUpload: String {
        return String(format: "%.1f KB/s", uploadSpeedKbps)
    }
    
    public var formattedDownload: String {
        return String(format: "%.1f KB/s", downloadSpeedKbps)
    }
    
    public var formattedTotalTransfer: String {
        let total = Double(totalBytesSent + totalBytesReceived)
        if total >= 1_000_000_000 {
            return String(format: "%.2f GB", total / 1_000_000_000)
        } else if total >= 1_000_000 {
            return String(format: "%.2f MB", total / 1_000_000)
        } else if total >= 1_000 {
            return String(format: "%.1f KB", total / 1_000)
        } else {
            return "\(Int(total)) B"
        }
    }
}
