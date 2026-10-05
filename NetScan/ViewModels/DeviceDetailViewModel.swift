//
//  DeviceDetailViewModel.swift
//  NetScan
//
//  Detailed device statistics, on-demand port scanning, ping test, and packet filtering.
//

import Foundation
import Combine

@MainActor
public class DeviceDetailViewModel: ObservableObject {
    @Published public var device: NetworkDevice
    @Published public var openPorts: [PortScanResult] = []
    @Published public var isScanningPorts: Bool = false
    @Published public var portScanProgress: Double = 0.0
    @Published public var isPinging: Bool = false
    @Published public var currentPingLatencyMs: Double = 0.0
    @Published public var relatedPackets: [NetworkPacket] = []
    @Published public var isSearchingOnlineVendor: Bool = false
    @Published public var searchStatusMessage: String? = nil
    
    public var onDeviceUpdated: ((NetworkDevice) -> Void)?
    
    private var pingCancellable: AnyCancellable?
    private var packetCancellable: AnyCancellable?
    
    public init(device: NetworkDevice, onDeviceUpdated: ((NetworkDevice) -> Void)? = nil) {
        self.device = device
        self.onDeviceUpdated = onDeviceUpdated
        
        // Seed initial known open ports
        self.openPorts = device.openPorts.map {
            PortScanResult(port: $0, serviceName: KnownPorts.service(for: $0), isOpen: true)
        }
    }
    
    public func startPacketObserving() {
        packetCancellable?.cancel()
        let ip = device.ipAddress
        packetCancellable = PacketInspectorService.shared.$capturedPackets
            .receive(on: DispatchQueue.main)
            .map { list in
                list.filter { $0.sourceIP == ip || $0.destinationIP == ip }
            }
            .sink { [weak self] filtered in
                self?.relatedPackets = filtered
            }
    }
    
    public func stopPacketObserving() {
        packetCancellable?.cancel()
        packetCancellable = nil
    }
    
    public func runPortScan() {
        guard !isScanningPorts else { return }
        isScanningPorts = true
        portScanProgress = 0.0
        openPorts.removeAll()
        
        PortScannerService.shared.scanPorts(
            targetIP: device.ipAddress,
            onPortFound: { [weak self] res in
                Task { @MainActor [weak self] in
                    self?.openPorts.append(res)
                }
            },
            onProgress: { [weak self] p in
                Task { @MainActor [weak self] in
                    self?.portScanProgress = p
                }
            },
            onCompletion: { [weak self] all in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.isScanningPorts = false
                    self.portScanProgress = 1.0
                    self.openPorts = all
                    self.device.openPorts = all.map { $0.port }
                    self.device.services = all.map { $0.serviceName }
                    self.onDeviceUpdated?(self.device)
                }
            }
        )
    }
    
    public func togglePing() {
        if isPinging {
            PingDiagnosticService.shared.stop()
            isPinging = false
            pingCancellable?.cancel()
            pingCancellable = nil
        } else {
            isPinging = true
            PingDiagnosticService.shared.startPinging(host: device.ipAddress)
            
            pingCancellable = PingDiagnosticService.shared.$avgRtt
                .receive(on: DispatchQueue.main)
                .sink { [weak self] rtt in
                    self?.currentPingLatencyMs = rtt
                }
        }
    }
    
    public func sendWakeOnLAN(completion: @escaping (Bool, String) -> Void) {
        let broadcast = NetworkInterfaceService.shared.getCurrentInterface().broadcastIP
        let targetBroadcast = broadcast.isEmpty ? "255.255.255.255" : broadcast
        WakeOnLANService.shared.sendWakePacket(macAddress: device.macAddress, broadcastIP: targetBroadcast, completion: completion)
    }
    
    /// Queries the live Internet MAC vendor database and local discovery heuristics for this device
    public func searchVendorOnline() {
        guard !isSearchingOnlineVendor else { return }
        isSearchingOnlineVendor = true
        searchStatusMessage = nil
        
        let targetIP = device.ipAddress
        let targetMAC = device.macAddress
        let targetHost = device.hostname
        
        Task {
            // Keep user feedback visible for at least 0.45s so the UI transition is fluid
            async let minDelay: Void = Task.sleep(nanoseconds: 450_000_000)
            
            let (vendor, devType, resolvedHost) = await OUIVendorDatabase.identifyDeviceAsync(
                ipAddress: targetIP,
                macAddress: targetMAC,
                hostname: targetHost
            )
            
            _ = try? await minDelay
            
            self.isSearchingOnlineVendor = false
            var updated = false
            
            if let host = resolvedHost, !host.isEmpty, host != self.device.hostname {
                self.device.hostname = host
                updated = true
            }
            
            if vendor != "Network Device" && vendor != "Unknown" && !vendor.isEmpty {
                self.device.vendor = vendor
                if self.device.deviceType == .unknown || self.device.deviceType != devType {
                    self.device.deviceType = devType
                }
                self.searchStatusMessage = "Identified as \(vendor)"
                updated = true
            } else {
                self.searchStatusMessage = "No manufacturer records found for this address."
            }
            
            if updated {
                self.onDeviceUpdated?(self.device)
            }
        }
    }
}
