//
//  PacketStreamViewModel.swift
//  NetScan
//
//  ViewModel powering the live packet stream, filter bars, pause/resume, and packet details.
//

import Foundation
import Combine

public class PacketStreamViewModel: ObservableObject {
    @Published public var packets: [NetworkPacket] = []
    @Published public var isCapturing: Bool = true
    @Published public var selectedProtocol: PacketProtocol? = nil
    @Published public var searchText: String = ""
    @Published public var selectedDeviceIP: String = ""
    @Published public var selectedPacket: NetworkPacket? = nil
    @Published public var packetsPerSecond: Double = 4.2
    
    private var cancellables = Set<AnyCancellable>()
    
    public init() {
        PacketInspectorService.shared.$isCapturing
            .receive(on: DispatchQueue.main)
            .assign(to: \.isCapturing, on: self)
            .store(in: &cancellables)
            
        // Combine captured packets with active filters
        Publishers.CombineLatest4(
            PacketInspectorService.shared.$capturedPackets,
            $selectedProtocol,
            $searchText,
            $selectedDeviceIP
        )
        .map { captured, proto, search, ip in
            captured.filter { packet in
                if let p = proto, packet.protocolType != p { return false }
                if !ip.isEmpty && !(packet.sourceIP.contains(ip) || packet.destinationIP.contains(ip)) { return false }
                if !search.isEmpty {
                    let q = search.lowercased()
                    let match = packet.summary.lowercased().contains(q) ||
                                packet.payloadAscii.lowercased().contains(q) ||
                                packet.sourceIP.contains(q) ||
                                packet.destinationIP.contains(q)
                    if !match { return false }
                }
                return true
            }
        }
        .receive(on: DispatchQueue.main)
        .assign(to: \.packets, on: self)
        .store(in: &cancellables)
    }
    
    public func toggleCapture() {
        if isCapturing {
            PacketInspectorService.shared.pauseCapture()
        } else {
            PacketInspectorService.shared.resumeCapture()
        }
    }
    
    public func clear() {
        PacketInspectorService.shared.clearPackets()
    }
    
    public func exportPacketsJSON() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(packets), let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "[]"
    }
}
