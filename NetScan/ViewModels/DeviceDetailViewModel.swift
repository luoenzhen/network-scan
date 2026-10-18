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
    
    public var onDeviceUpdated: ((NetworkDevice, DeviceUpdateKind) -> Void)?
    
    private var pingCancellable: AnyCancellable?
    private var packetCancellable: AnyCancellable?
    private let portScanner = PortScannerService()
    private let pingService = PingDiagnosticService()
    private var vendorTask: Task<Void, Never>?
    private var portScanID = UUID()
    
    public init(device: NetworkDevice, onDeviceUpdated: ((NetworkDevice, DeviceUpdateKind) -> Void)? = nil) {
        self.device = device
        self.onDeviceUpdated = onDeviceUpdated
        
        // Seed initial known open ports
        self.openPorts = Set(device.openPorts).sorted().map {
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
        pingService.stop()
        pingCancellable?.cancel()
        pingCancellable = nil
        isPinging = false
        portScanner.cancel()
        portScanID = UUID()
        isScanningPorts = false
        if device.serviceCheckState == .checking { device.serviceCheckState = .notChecked }
        vendorTask?.cancel()
        vendorTask = nil
        isSearchingOnlineVendor = false
    }

    public func updateLiveDevice(_ updated: NetworkDevice) {
        guard updated.id == device.id else { return }
        device = updated
        if !isScanningPorts {
            openPorts = Set(updated.openPorts).sorted().map {
                PortScanResult(port: $0, serviceName: KnownPorts.service(for: $0), isOpen: true)
            }
        }
    }
    
    public func runPortScan() {
        guard !isScanningPorts else { return }
        isScanningPorts = true
        device.serviceCheckState = .checking
        portScanProgress = 0.0
        openPorts.removeAll()
        portScanID = UUID()
        let run = portScanID
        
        portScanner.scanPorts(
            targetIP: device.ipAddress,
            onPortFound: { [weak self] res in
                Task { @MainActor [weak self] in
                    guard self?.portScanID == run else { return }
                    self?.openPorts.append(res)
                }
            },
            onProgress: { [weak self] p in
                Task { @MainActor [weak self] in
                    guard self?.portScanID == run else { return }
                    self?.portScanProgress = p
                }
            },
            onCompletion: { [weak self] all in
                Task { @MainActor [weak self] in
                    guard let self = self, self.portScanID == run else { return }
                    self.isScanningPorts = false
                    self.portScanProgress = 1.0
                    self.openPorts = all
                    self.device.openPorts = all.map { $0.port }
                    self.device.services = all.map { $0.serviceName }
                    self.device.serviceCheckState = .checked
                    self.device.assessedPorts = self.portScanner.completedPorts
                    self.onDeviceUpdated?(self.device, .ports)
                }
            }
        )
    }
    
    public func togglePing() {
        if isPinging {
            pingService.stop()
            isPinging = false
            pingCancellable?.cancel()
            pingCancellable = nil
        } else {
            isPinging = true
            pingService.startPinging(host: device.ipAddress)
            
            pingCancellable = pingService.$avgRtt
                .receive(on: DispatchQueue.main)
                .sink { [weak self] rtt in
                    self?.currentPingLatencyMs = rtt
                }
        }
    }
    
    public func sendWakeOnLAN(completion: @escaping (Bool, String) -> Void) {
        let interface = NetworkInterfaceService.shared.getCurrentInterface()
        guard interface.isLAN, !interface.broadcastIP.isEmpty else {
            completion(false, "Connect to a Wi-Fi or Ethernet LAN before sending Wake-on-LAN.")
            return
        }
        WakeOnLANService.shared.sendWakePacket(macAddress: device.macAddress, broadcastIP: interface.broadcastIP,
                                             interfaceName: interface.interfaceName) { success, message in
            DispatchQueue.main.async { completion(success, message) }
        }
    }
    
    /// Queries the live Internet MAC vendor database and local discovery heuristics for this device
    public func searchVendorOnline() {
        guard !isSearchingOnlineVendor else { return }
        isSearchingOnlineVendor = true
        searchStatusMessage = nil
        
        let targetIP = device.ipAddress
        let targetMAC = device.macAddress
        let targetHost = device.hostname
        
        vendorTask = Task {
            let result = await OUIVendorDatabase.identifyDeviceWithEvidence(
                ipAddress: targetIP,
                macAddress: targetMAC,
                hostname: targetHost
            )
            
            guard !Task.isCancelled else { return }
            let (vendor, devType, resolvedHost) = (result.vendor, result.deviceType, result.resolvedHostname)
            for evidence in result.evidence where !self.device.evidence.contains(where: { $0.id == evidence.id }) {
                self.device.evidence.append(evidence)
            }
            
            self.isSearchingOnlineVendor = false
            var updated = false
            
            if let host = resolvedHost, !host.isEmpty, host != self.device.hostname {
                self.device.hostname = host
                updated = true
            }
            
            if vendor != "Network Device" && vendor != "Unknown" && !vendor.isEmpty {
                self.device.vendor = vendor
                if devType != .unknown {
                    self.device.deviceType = devType
                }
                self.searchStatusMessage = "Identified as \(vendor)"
                updated = true
            } else {
                self.searchStatusMessage = "No manufacturer records found for this address."
            }
            
            if updated || !result.evidence.isEmpty {
                self.onDeviceUpdated?(self.device, .identity)
            }
        }
    }

    public func saveAnnotation(_ annotation: DeviceAnnotation) {
        device.annotation = annotation
        device.savedMatch = .current
        onDeviceUpdated?(device, .annotation)
    }
}
