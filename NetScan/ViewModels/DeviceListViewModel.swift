//
//  DeviceListViewModel.swift
//  NetScan
//
//  Manages the scanned devices list, sorting, filtering, and real-time traffic updates.
//

import Foundation
import Combine
import SwiftUI

public enum DeviceSortOption: String, CaseIterable, Identifiable {
    case ipAddress = "IP Address"
    case bandwidth = "Bandwidth (KB/s)"
    case latency = "Latency (ms)"
    case name = "Device Name"
    
    public var id: String { rawValue }
}

public class DeviceListViewModel: ObservableObject {
    @Published public var devices: [NetworkDevice] = []
    @Published public var isScanning: Bool = false
    @Published public var scanProgress: Double = 0.0
    @Published public var searchText: String = ""
    @Published public var selectedFilterType: DeviceType? = nil
    @Published public var sortOption: DeviceSortOption = .ipAddress
    @Published public var lastScanTimestamp: Date? = nil
    @Published public var isLANConnected: Bool = false
    @Published public var currentSSID: String = ""
    @Published public private(set) var isUpdatingIdentities = false
    
    private var trafficTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var lastNetworkId: String = ""
    private var scanID = UUID()
    private var enrichmentID = UUID()
    private(set) var didAutoScan = false
    private var identityTask: Task<Void, Never>?
    var identityRetryDelay: UInt64 = 15_000_000_000
    var identityLookup: (NetworkDevice) async -> (vendor: String, deviceType: DeviceType, resolvedHostname: String?) = { device in
        await OUIVendorDatabase.identifyDeviceAsync(ipAddress: device.ipAddress, macAddress: device.macAddress, hostname: device.hostname)
    }
    static let securityPorts = [21, 23, 139, 445, 3389]
    private var serviceCheckID = UUID()
    private var serviceScanners: [UUID: PortScannerService] = [:]
    private var pendingServiceChecks: [UUID] = []
    var activeServiceCheckCount: Int { serviceScanners.count }

    deinit {
        trafficTimer?.invalidate()
        identityTask?.cancel()
        serviceScanners.values.forEach { $0.cancel() }
    }
    
    public convenience init() {
        self.init(observeNetwork: true)
    }

    init(observeNetwork: Bool) {
        OUIVendorDatabase.loadDatabaseIfNeeded()
        #if DEBUG
        if ProcessInfo.processInfo.environment["NETSCAN_UI_TESTING"] == "1" {
            isLANConnected = true
            currentSSID = "UI Test Network"
            devices = [NetworkDevice(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                                     ipAddress: "127.0.0.1", macAddress: "B8:27:EB:00:00:01",
                                     hostname: "Test Network Device", vendor: "Network Device")]
            didAutoScan = true
            return
        }
        #endif
        guard observeNetwork else { return }
        
        let initialInterface = NetworkInterfaceService.shared.getCurrentInterface()
        self.isLANConnected = initialInterface.isLAN
        self.currentSSID = initialInterface.ssid
        self.lastNetworkId = initialInterface.networkIdentifier
        
        if initialInterface.isLAN {
            startTrafficPolling()
        }
        
        // Listen to live network changes from NetworkInterfaceService
        Publishers.CombineLatest(NetworkInterfaceService.shared.$currentInterface,
                                 NetworkInterfaceService.shared.$hasResolvedPath)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newInterface, pathResolved in
                self?.handleInterfaceChange(newInterface, pathResolved: pathResolved)
            }
            .store(in: &cancellables)
    }
    
    func handleInterfaceChange(_ newInterface: NetworkInterfaceInfo, pathResolved: Bool) {
        let currentNetId = newInterface.networkIdentifier
        self.isLANConnected = newInterface.isLAN
        self.currentSSID = newInterface.ssid
        if lastNetworkId != currentNetId {
            stopDeviceUpdates()
            selectedFilterType = nil
        }
        
        if !newInterface.isLAN {
            // Switched to Cellular (4G/5G) or Disconnected
            if isScanning {
                stopScan()
            }
            trafficTimer?.invalidate()
            trafficTimer = nil
            
            // Clear old scan results from previous LAN network!
            if !devices.isEmpty {
                devices.removeAll()
                lastScanTimestamp = nil
            }
        } else {
            // Connected to Wi-Fi / LAN
            if !lastNetworkId.isEmpty && lastNetworkId != currentNetId {
                // Switched to a different Wi-Fi / LAN network
                if isScanning {
                    stopScan()
                }
                devices.removeAll()
                lastScanTimestamp = nil
            }
            
            if trafficTimer == nil && !isScanning && !devices.isEmpty {
                startTrafficPolling()
            }
        }
        
        lastNetworkId = currentNetId
        if pathResolved && newInterface.isLAN && !didAutoScan {
            didAutoScan = true
            if UserDefaults.standard.object(forKey: "autoRefreshOnLaunch") as? Bool ?? true {
                startScan()
            }
        }
    }
    
    public var filteredAndSortedDevices: [NetworkDevice] {
        var list = devices
        
        // Search filter
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            list = list.filter {
                $0.displayName.lowercased().contains(q) ||
                $0.ipAddress.contains(q) ||
                $0.macAddress.lowercased().contains(q) ||
                $0.vendor.lowercased().contains(q)
            }
        }
        
        // Category filter
        if let type = selectedFilterType {
            list = list.filter { $0.deviceType == type }
        }
        
        // Sorting
        switch sortOption {
        case .ipAddress:
            list.sort { compareIPs($0.ipAddress, $1.ipAddress) }
        case .bandwidth:
            list.sort { ($0.uploadSpeedKbps + $0.downloadSpeedKbps) > ($1.uploadSpeedKbps + $1.downloadSpeedKbps) }
        case .latency:
            list.sort { $0.latencyMs < $1.latencyMs }
        case .name:
            list.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        }
        
        return list
    }
    
    public func startScan() {
        guard !isScanning else { return }
        
        let interface = NetworkInterfaceService.shared.getCurrentInterface()
        guard interface.isLAN else {
            // Subnet scanning is only available on a Wi-Fi or Ethernet LAN
            return
        }
        
        isScanning = true
        scanProgress = 0.0
        scanID = UUID()
        stopDeviceUpdates()
        let run = scanID
        selectedFilterType = nil
        
        // Clear previous scan results before starting fresh scan
        devices.removeAll()
        
        // Pause traffic timer during scan to prevent simultaneous data access
        trafficTimer?.invalidate()
        trafficTimer = nil
        
        SubnetScannerService.shared.scanSubnet(
            interface: interface,
            onProgress: { [weak self] progress in
                guard self?.scanID == run else { return }
                self?.scanProgress = progress
            },
            onDeviceFound: { [weak self] newDevice in
                guard let self = self, self.scanID == run else { return }
                if let index = self.devices.firstIndex(where: { $0.ipAddress == newDevice.ipAddress }) {
                    var updated = newDevice
                    updated.id = self.devices[index].id
                    self.devices[index] = updated
                } else {
                    self.devices.append(newDevice)
                }
            },
            onCompletion: { [weak self] _ in
                guard let self = self, self.scanID == run else { return }
                self.isScanning = false
                self.scanProgress = 1.0
                self.lastScanTimestamp = Date()
                self.startTrafficPolling()
                self.enrichVendorsOnline()
                self.checkDeviceServices()
            }
        )
    }
    
    public func updateDevice(_ updatedDevice: NetworkDevice, kind: DeviceUpdateKind = .identity) {
        if let index = devices.firstIndex(where: { $0.id == updatedDevice.id }) {
            // Merge identity/diagnostics without overwriting newer traffic samples.
            switch kind {
            case .identity:
                devices[index].hostname = updatedDevice.hostname
                devices[index].vendor = updatedDevice.vendor
                devices[index].deviceType = updatedDevice.deviceType
            case .ports:
                serviceScanners.removeValue(forKey: updatedDevice.id)?.cancel()
                devices[index].openPorts = updatedDevice.openPorts
                devices[index].services = updatedDevice.services
                devices[index].serviceCheckState = .checked
                pendingServiceChecks.removeAll { $0 == updatedDevice.id }
                startNextServiceChecks()
            }
        }
    }
    
    /// Queries the online Internet vendor database and LAN heuristics for any devices not recognized locally
    public func enrichVendorsOnline() {
        identityTask?.cancel()
        enrichmentID = UUID()
        let run = enrichmentID
        isUpdatingIdentities = true
        let lookup = identityLookup
        let retryDelay = identityRetryDelay
        identityTask = Task { @MainActor [weak self] in
            for attempt in 0..<2 {
                guard !Task.isCancelled, self?.enrichmentID == run else { return }
                let candidates = self?.devices.filter { $0.needsIdentityUpdate } ?? []
                if candidates.isEmpty { break }
                if attempt > 0 {
                    do { try await Task.sleep(nanoseconds: retryDelay) } catch { return }
                }
                guard !Task.isCancelled, self?.enrichmentID == run else { return }
                for device in candidates {
                    guard !Task.isCancelled, self?.enrichmentID == run else { return }
                    guard self?.devices.first(where: { $0.id == device.id })?.needsIdentityUpdate == true else { continue }
                    let result = await lookup(device)
                    guard !Task.isCancelled, self?.enrichmentID == run else { return }
                    self?.applyIdentity(result, to: device.id)
                }
            }
            guard self?.enrichmentID == run else { return }
            self?.isUpdatingIdentities = false
            self?.identityTask = nil
        }
    }

    private func applyIdentity(_ result: (vendor: String, deviceType: DeviceType, resolvedHostname: String?), to id: UUID) {
        guard let index = devices.firstIndex(where: { $0.id == id }) else { return }
        if let host = result.resolvedHostname, !host.isEmpty, host != devices[index].ipAddress {
            devices[index].hostname = host
        }
        if !["", "Unknown", "Network Device", "Generic Device"].contains(result.vendor) {
            devices[index].vendor = result.vendor
        }
        if result.deviceType != .unknown { devices[index].deviceType = result.deviceType }
    }

    func checkDeviceServices() {
        serviceCheckID = UUID()
        serviceScanners.values.forEach { $0.cancel() }
        serviceScanners.removeAll()
        pendingServiceChecks = devices.filter { !$0.isLocalDevice && $0.isOnline }.map(\.id)
        startNextServiceChecks()
    }

    private func startNextServiceChecks() {
        let run = serviceCheckID
        while serviceScanners.count < 2 && !pendingServiceChecks.isEmpty {
            let id = pendingServiceChecks.removeFirst()
            guard let index = devices.firstIndex(where: { $0.id == id }) else { continue }
            let scanner = PortScannerService()
            serviceScanners[id] = scanner
            devices[index].serviceCheckState = .checking
            scanner.scanPorts(targetIP: devices[index].ipAddress, ports: Self.securityPorts,
                              onPortFound: { _ in }, onProgress: { _ in }, onCompletion: { [weak self] results in
                guard let self = self, self.serviceCheckID == run, self.serviceScanners[id] != nil else { return }
                self.serviceScanners.removeValue(forKey: id)
                self.mergeServiceCheck(results, into: id)
                self.startNextServiceChecks()
            })
        }
    }

    func mergeServiceCheck(_ results: [PortScanResult], into id: UUID) {
        guard let index = devices.firstIndex(where: { $0.id == id }) else { return }
        let unaffected = devices[index].openPorts.filter { !Self.securityPorts.contains($0) }
        devices[index].openPorts = Array(Set(unaffected + results.filter(\.isOpen).map(\.port))).sorted()
        devices[index].services = devices[index].openPorts.map { KnownPorts.service(for: $0) }
        devices[index].serviceCheckState = .checked
    }

    public func stopDeviceUpdates() {
        enrichmentID = UUID()
        identityTask?.cancel()
        identityTask = nil
        isUpdatingIdentities = false
        serviceCheckID = UUID()
        serviceScanners.values.forEach { $0.cancel() }
        serviceScanners.removeAll()
        pendingServiceChecks.removeAll()
        for index in devices.indices where devices[index].serviceCheckState == .checking {
            devices[index].serviceCheckState = .notChecked
        }
    }
    
    public func stopScan() {
        stopDeviceUpdates()
        scanID = UUID()
        SubnetScannerService.shared.cancelScan()
        isScanning = false
        if isLANConnected && !devices.isEmpty {
            startTrafficPolling()
        }
    }
    
    private func startTrafficPolling() {
        trafficTimer?.invalidate()
        trafficTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, !self.isScanning, self.isLANConnected else { return }
            var currentDevices = self.devices
            TrafficMonitorService.shared.updateDeviceTraffic(devices: &currentDevices)
            self.devices = currentDevices
        }
    }
    
    private func compareIPs(_ ip1: String, _ ip2: String) -> Bool {
        let p1 = ip1.split(separator: ".").compactMap { Int($0) }
        let p2 = ip2.split(separator: ".").compactMap { Int($0) }
        guard p1.count == 4 && p2.count == 4 else { return ip1 < ip2 }
        
        for i in 0..<4 {
            if p1[i] != p2[i] {
                return p1[i] < p2[i]
            }
        }
        return false
    }
}
