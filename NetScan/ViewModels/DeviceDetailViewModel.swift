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
    }
    
    public func startPacketObserving() {
        packetCancellable?.cancel()
        packetCancellable = PacketInspectorService.shared.$capturedPackets
            .receive(on: DispatchQueue.main)
            .map { [weak self] list in
                guard let self = self else { return [] }
                return list.filter { $0.sourceIP == self.device.ipAddress || $0.destinationIP == self.device.ipAddress }
            }
            .assign(to: \.relatedPackets, on: self)
    }
    
    public func stopPacketObserving() {
        packetCancellable?.cancel()
        packetCancellable = nil
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
    
    @Published public var isSearchingOnlineVendor: Bool = false
    
    /// Queries the live Internet MAC vendor database for this device
    public func searchVendorOnline() {
        guard !isSearchingOnlineVendor else { return }
        isSearchingOnlineVendor = true
        
        Task {
            let (vendor, devType) = await OUIVendorDatabase.identifyDeviceAsync(
                macAddress: device.macAddress,
                hostname: device.hostname
            )
            await MainActor.run {
                self.isSearchingOnlineVendor = false
                if vendor != "Network Device" && vendor != "Unknown" {
                    self.device.vendor = vendor
                    if self.device.deviceType == .unknown {
                        self.device.deviceType = devType
                    }
                }
            }
        }
    }
}
