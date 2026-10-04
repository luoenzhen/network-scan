//
//  PacketRowView.swift
//  NetScan
//
//  Renders a single captured packet with protocol badge, direction, endpoints, and summary.
//

import SwiftUI

public struct PacketRowView: View {
    public let packet: NetworkPacket
    
    public init(packet: NetworkPacket) {
        self.packet = packet
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                // Direction indicator
                Image(systemName: packet.direction.symbol)
                    .font(.caption)
                    .foregroundColor(packet.direction == .inbound ? .green : .blue)
                
                // Protocol Badge
                Text(packet.protocolType.rawValue)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(protocolColor.opacity(0.18))
                    .foregroundColor(protocolColor)
                    .cornerRadius(4)
                
                // Endpoints
                Text(packet.formattedEndpoints)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Spacer()
                
                // Length and Time
                Text(packet.formattedLength)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Text(packet.summary)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                Spacer()
                
                Text(packet.formattedTime)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
    
    private var protocolColor: Color {
        switch packet.protocolType {
        case .tcp: return .blue
        case .udp: return .green
        case .icmp: return .orange
        case .dns: return .purple
        case .http: return .cyan
        case .https: return .indigo
        case .mdns: return .pink
        case .arp: return .yellow
        case .other: return .gray
        }
    }
}
