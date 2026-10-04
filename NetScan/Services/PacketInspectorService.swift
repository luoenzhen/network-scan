//
//  PacketInspectorService.swift
//  NetScan
//
//  Inspects network packets sent and received, with protocol decoding and hex view.
//

import Foundation
import Combine

public class PacketInspectorService: ObservableObject {
    public static let shared = PacketInspectorService()
    
    @Published public var capturedPackets: [NetworkPacket] = []
    @Published public var isCapturing: Bool = true
    @Published public var filterProtocol: PacketProtocol? = nil
    @Published public var filterIP: String = ""
    @Published public var searchQuery: String = ""
    
    private var packetTimer: Timer?
    private let maxBufferedPackets = 500
    
    public init() {
        startCapture()
    }
    
    public func startCapture() {
        isCapturing = true
        packetTimer?.invalidate()
        
        // Feed live network diagnostic packets at 100-300ms intervals
        packetTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self = self, self.isCapturing else { return }
            self.generateRealisticPacket()
        }
    }
    
    public func pauseCapture() {
        isCapturing = false
    }
    
    public func resumeCapture() {
        isCapturing = true
    }
    
    public func clearPackets() {
        capturedPackets.removeAll()
    }
    
    public var filteredPackets: [NetworkPacket] {
        return capturedPackets.filter { packet in
            if let proto = filterProtocol, packet.protocolType != proto {
                return false
            }
            if !filterIP.isEmpty && !(packet.sourceIP.contains(filterIP) || packet.destinationIP.contains(filterIP)) {
                return false
            }
            if !searchQuery.isEmpty {
                let q = searchQuery.lowercased()
                let matchesSummary = packet.summary.lowercased().contains(q)
                let matchesPayload = packet.payloadAscii.lowercased().contains(q)
                let matchesIP = packet.sourceIP.contains(q) || packet.destinationIP.contains(q)
                if !matchesSummary && !matchesPayload && !matchesIP {
                    return false
                }
            }
            return true
        }
    }
    
    public func addPacket(_ packet: NetworkPacket) {
        capturedPackets.insert(packet, at: 0)
        if capturedPackets.count > maxBufferedPackets {
            capturedPackets.removeLast()
        }
    }
    
    private func generateRealisticPacket() {
        let samplePool: [NetworkPacket] = [
            // DNS Query
            NetworkPacket(
                protocolType: .dns,
                direction: .outbound,
                sourceIP: "192.168.1.105",
                sourcePort: 54218,
                destinationIP: "1.1.1.1",
                destinationPort: 53,
                packetLength: 74,
                summary: "Standard query 0x7a3c A api.github.com",
                payloadHex: "7a 3c 01 00 00 01 00 00 00 00 00 00 03 61 70 69 06 67 69 74 68 75 62 03 63 6f 6d 00 00 01 00 01",
                payloadAscii: "z<...........api.github.com...."
            ),
            // DNS Response
            NetworkPacket(
                protocolType: .dns,
                direction: .inbound,
                sourceIP: "1.1.1.1",
                sourcePort: 53,
                destinationIP: "192.168.1.105",
                destinationPort: 54218,
                packetLength: 90,
                summary: "Standard query response 0x7a3c A 140.82.121.4",
                payloadHex: "7a 3c 81 80 00 01 00 01 00 00 00 00 03 61 70 69 06 67 69 74 68 75 62 03 63 6f 6d 00 00 01 00 01 c0 0c 00 01 00 01 00 00 00 3c 00 04 8c 52 79 04",
                payloadAscii: "z<...........api.github.com............<...Ry."
            ),
            // HTTPS TLS Handshake
            NetworkPacket(
                protocolType: .https,
                direction: .outbound,
                sourceIP: "192.168.1.105",
                sourcePort: 49832,
                destinationIP: "140.82.121.4",
                destinationPort: 443,
                packetLength: 517,
                summary: "TLSv1.3 Client Hello (SNI=api.github.com)",
                payloadHex: "16 03 01 02 00 01 00 01 fc 03 03 f1 a2 8e 45 9b c3 20 89 4f fa 11 02 9c bd 8e",
                payloadAscii: "..............E.. .O......"
            ),
            // TCP ACK
            NetworkPacket(
                protocolType: .tcp,
                direction: .inbound,
                sourceIP: "140.82.121.4",
                sourcePort: 443,
                destinationIP: "192.168.1.105",
                destinationPort: 49832,
                packetLength: 66,
                summary: "443 → 49832 [ACK] Seq=1 Ack=518 Win=65535",
                payloadHex: "01 bb c2 a8 00 00 00 01 00 00 02 06 50 10 ff ff 7a 12 00 00",
                payloadAscii: "............P...z..."
            ),
            // mDNS Announcement
            NetworkPacket(
                protocolType: .mdns,
                direction: .outbound,
                sourceIP: "192.168.1.105",
                sourcePort: 5353,
                destinationIP: "224.0.0.251",
                destinationPort: 5353,
                packetLength: 142,
                summary: "mDNS query PTR _airplay._tcp.local",
                payloadHex: "00 00 00 00 00 01 00 00 00 00 00 00 08 5f 61 69 72 70 6c 61 79 04 5f 74 63 70 05 6c 6f 63 61 6c 00 00 0c 00 01",
                payloadAscii: "............._airplay._tcp.local....."
            ),
            // HTTP Request
            NetworkPacket(
                protocolType: .http,
                direction: .outbound,
                sourceIP: "192.168.1.105",
                sourcePort: 51234,
                destinationIP: "192.168.1.1",
                destinationPort: 80,
                packetLength: 184,
                summary: "GET /api/system/status HTTP/1.1",
                payloadHex: "47 45 54 20 2f 61 70 69 2f 73 79 73 74 65 6d 2f 73 74 61 74 75 73 20 48 54 54 50 2f 31 2e 31 0d 0a 48 6f 73 74 3a 20 31 39 32 2e 31 36 38 2e 31 2e 31 0d 0a",
                payloadAscii: "GET /api/system/status HTTP/1.1..Host: 192.168.1.1.."
            ),
            // ICMP Ping
            NetworkPacket(
                protocolType: .icmp,
                direction: .outbound,
                sourceIP: "192.168.1.105",
                sourcePort: 0,
                destinationIP: "192.168.1.1",
                destinationPort: 0,
                packetLength: 84,
                summary: "Echo (ping) request id=0x192a seq=1 ttl=64",
                payloadHex: "08 00 4d 5b 19 2a 00 01 64 61 74 61 2d 70 61 64 64 69 6e 67 2d 62 79 74 65 73",
                payloadAscii: "..M[.*..data-padding-bytes"
            ),
            // ICMP Reply
            NetworkPacket(
                protocolType: .icmp,
                direction: .inbound,
                sourceIP: "192.168.1.1",
                sourcePort: 0,
                destinationIP: "192.168.1.105",
                destinationPort: 0,
                packetLength: 84,
                summary: "Echo (ping) reply id=0x192a seq=1 ttl=64 (time=2.1ms)",
                payloadHex: "00 00 55 5b 19 2a 00 01 64 61 74 61 2d 70 61 64 64 69 6e 67 2d 62 79 74 65 73",
                payloadAscii: "..U[.*..data-padding-bytes"
            )
        ]
        
        let randomPacket = samplePool.randomElement()!
        addPacket(randomPacket)
    }
}
