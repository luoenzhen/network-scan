//
//  PacketDetailSheet.swift
//  NetScan
//
//  Full packet inspector breakdown: frame headers, protocol metadata,
//  hexadecimal payload dump, and ASCII payload representation.
//

import SwiftUI

public struct PacketDetailSheet: View {
    public let packet: NetworkPacket
    
    public init(packet: NetworkPacket) {
        self.packet = packet
    }
    
    public var body: some View {
        List {
            // General Information
            Section(header: Text("Packet Overview")) {
                infoRow(label: "Timestamp", value: packet.formattedTime)
                infoRow(label: "Protocol", value: packet.protocolType.rawValue)
                infoRow(label: "Direction", value: packet.direction.rawValue)
                infoRow(label: "Packet Length", value: "\(packet.packetLength) Bytes")
                infoRow(label: "Summary", value: packet.summary)
            }
            
            // Layer 3 / 4 Endpoints
            Section(header: Text("Network Endpoints")) {
                infoRow(label: "Source IP", value: packet.sourceIP)
                if packet.sourcePort > 0 {
                    infoRow(label: "Source Port", value: "\(packet.sourcePort)")
                }
                infoRow(label: "Destination IP", value: packet.destinationIP)
                if packet.destinationPort > 0 {
                    infoRow(label: "Destination Port", value: "\(packet.destinationPort)")
                }
            }
            
            // Hex Dump View
            if !packet.payloadHex.isEmpty {
                Section(header: Text("Payload Hex Dump (16-Byte Alignment)")) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(formatHexDump(packet.payloadHex))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.primary)
                            .padding(.vertical, 4)
                    }
                }
            }
            
            // ASCII String View
            if !packet.payloadAscii.isEmpty {
                Section(header: Text("Printable ASCII Representation")) {
                    Text(packet.payloadAscii)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.vertical, 4)
                }
            }
        }
        .listStyle(InsetGroupedListStyle())
        .navigationTitle("\(packet.protocolType.rawValue) Packet")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.primary)
                .multilineTextAlignment(.trailing)
        }
    }
    
    private func formatHexDump(_ rawHex: String) -> String {
        let tokens = rawHex.split(separator: " ").map { String($0) }
        guard !tokens.isEmpty else { return rawHex }
        
        var lines: [String] = []
        var offset = 0
        
        for i in stride(from: 0, to: tokens.count, by: 16) {
            let chunk = tokens[i..<min(i + 16, tokens.count)]
            let offsetStr = String(format: "%04X", offset)
            let hexStr = chunk.joined(separator: " ")
            lines.append("\(offsetStr)   \(hexStr)")
            offset += 16
        }
        
        return lines.joined(separator: "\n")
    }
}
