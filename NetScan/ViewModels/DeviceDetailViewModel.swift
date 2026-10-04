//
//  DeviceDetailViewModel.swift
//  NetScan
//
//  Detailed device statistics, on-demand port scanning, ping test, and packet filtering.
//

import Foundation
import Combine

public class DeviceDetailViewModel: ObservableObject {
    @Published public var device: NetworkDevice
    @Published public var openPorts: [PortScanResult] = []
    @Published public var isScanningPorts: Bool = false
    @Published public var portScanProgress: Double = 0.0
    @Published public var isPinging: Bool = false
    @Published public var currentPingLatencyMs: Double = 0.0
    @Published public var relatedPackets: [NetworkPacket] = []
    
    private var pingCancellable: AnyCancellable?
    private var packetCancellable: AnyCancellable?
    
    public init(device: NetworkDevice) {
        self.device = device
        
        // Seed initial known open ports
        self.openPorts = device.openPorts.map {
            PortScanResult(port: $0, serviceName: KnownPorts.service(for: $0), isOpen: true)
        }
        
        // Subscribe to packet updates matching this device IP
        PacketInspectorService.shared.$capturedPackets
            .receive(on: DispatchQueue.main)
            .map { list in
                list.filter { $0.sourceIP == device.ipAddress || $0.destinationIP == device.ipAddress }
            }
            .assign(to: \.relatedPackets, on: self)
            .store(in: &cancellables)
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    public func runPortScan() {
        guard !isScanningPorts else { return }
        isScanningPorts = true
        portScanProgress = 0.0
        openPorts.removeAll()
        
        PortScannerService.shared.scanPorts(
            targetIP: device.ipAddress,
            onPortFound: { [weak self] res in
                self?.openPorts.append(res)
            },
            onProgress: { [weak self] p in
                self?.portScanProgress = p
            },
            onCompletion: { [weak self] all in
                guard let self = self else { return }
                self.isScanningPorts = false
                self.portScanProgress = 1.0
                self.openPorts = all
                self.device.openPorts = all.map { $0.port }
                self.device.services = all.map { $0.serviceName }
            }
        )
    }
    
    public func togglePing() {
        if isPinging {
            PingDiagnosticService.shared.stop()
            isPinging = false
        } else {
            isPinging = true
            PingDiagnosticService.shared.startPinging(host: device.ipAddress)
            
            pingCancellable = PingDiagnosticService.shared.$avgRtt
                .receive(on: DispatchQueue.main)
                .assign(to: \.currentPingLatencyMs, on: self)
        }
    }
    
    public func sendWakeOnLAN(completion: @escaping (Bool, String) -> Void) {
        let broadcast = NetworkInterfaceService.shared.getCurrentInterface().broadcastIP
        WakeOnLANService.shared.sendWakePacket(macAddress: device.macAddress, broadcastIP: broadcast, completion: completion)
    }
}
