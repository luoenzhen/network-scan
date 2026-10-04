//
//  NetworkPacket.swift
//  NetScan
//
//  Represents a captured or inspected network packet with protocol decoding.
//

import Foundation

public enum PacketProtocol: String, Codable, CaseIterable {
    case tcp = "TCP"
    case udp = "UDP"
    case icmp = "ICMP"
    case dns = "DNS"
    case http = "HTTP"
    case https = "HTTPS / TLS"
    case mdns = "mDNS / Bonjour"
    case arp = "ARP"
    case other = "RAW"
    
    public var badgeColorHex: String {
        switch self {
        case .tcp: return "#0A84FF"   // Blue
        case .udp: return "#30D158"   // Green
        case .icmp: return "#FF9F0A"  // Orange
        case .dns: return "#BF5AF2"   // Purple
        case .http: return "#64D2FF"  // Light Blue
        case .https: return "#5E5CE6" // Indigo
        case .mdns: return "#FF375F"  // Pink
        case .arp: return "#FFD60A"   // Yellow
        case .other: return "#8E8E93" // Gray
        }
    }
}

public enum PacketDirection: String, Codable {
    case inbound = "Download"
    case outbound = "Upload"
    
    public var symbol: String {
        switch self {
        case .inbound: return "arrow.down.circle.fill"
        case .outbound: return "arrow.up.circle.fill"
        }
    }
}

public struct NetworkPacket: Identifiable, Codable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let protocolType: PacketProtocol
    public let direction: PacketDirection
    public let sourceIP: String
    public let sourcePort: Int
    public let destinationIP: String
    public let destinationPort: Int
    public let packetLength: Int // size in bytes
    public let summary: String
    public let payloadHex: String
    public let payloadAscii: String
    
    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        protocolType: PacketProtocol,
        direction: PacketDirection,
        sourceIP: String,
        sourcePort: Int,
        destinationIP: String,
        destinationPort: Int,
        packetLength: Int,
        summary: String,
        payloadHex: String = "",
        payloadAscii: String = ""
    ) {
        self.id = id
        self.timestamp = timestamp
        self.protocolType = protocolType
        self.direction = direction
        self.sourceIP = sourceIP
        self.sourcePort = sourcePort
        self.destinationIP = destinationIP
        self.destinationPort = destinationPort
        self.packetLength = packetLength
        self.summary = summary
        self.payloadHex = payloadHex
        self.payloadAscii = payloadAscii
    }
    
    public var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: timestamp)
    }
    
    public var formattedLength: String {
        if packetLength >= 1024 {
            return String(format: "%.1f KB", Double(packetLength) / 1024.0)
        }
        return "\(packetLength) B"
    }
    
    public var formattedEndpoints: String {
        if sourcePort > 0 && destinationPort > 0 {
            return "\(sourceIP):\(sourcePort) → \(destinationIP):\(destinationPort)"
        }
        return "\(sourceIP) → \(destinationIP)"
    }
}
