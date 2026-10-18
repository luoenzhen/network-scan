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
    @Published public private(set) var history: [ScanSnapshot] = []
    public private(set) var networkScope = ""
    public private(set) var networkIsCertain = false
    private let inventory: DeviceInventory
    private let bonjour = BonjourDiscoveryService()
    private var discoveryFinish: DispatchWorkItem?
    private var historyRunID: UUID?
    private var identityCoverage: CheckCoverage = .pending
    private var serviceCoverage: CheckCoverage = .pending
    public var storageMessage: String? { inventory.storageMessage }
    
    private var trafficTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var lastNetworkId: String = ""
    private var scanID = UUID()
    var activeScanID: UUID { scanID }
    private var enrichmentID = UUID()
    private(set) var didAutoScan = false
    private var identityTask: Task<Void, Never>?
    var identityRetryDelay: UInt64 = 15_000_000_000
    var identityLookup: ((NetworkDevice) async -> (vendor: String, deviceType: DeviceType, resolvedHostname: String?))?
    static let securityPorts = [21, 23, 139, 445, 3389]
    private var serviceCheckID = UUID()
    private var serviceScanners: [UUID: PortScannerService] = [:]
    private var pendingServiceChecks: [UUID] = []
    var activeServiceCheckCount: Int { serviceScanners.count }

    deinit {
        discoveryFinish?.cancel()
        let browser = bonjour
        if Thread.isMainThread { browser.stopBrowsing() } else { DispatchQueue.main.async { browser.stopBrowsing() } }
        trafficTimer?.invalidate()
        identityTask?.cancel()
        serviceScanners.values.forEach { $0.cancel() }
    }
    
    public convenience init() {
        #if DEBUG
        if ProcessInfo.processInfo.environment["NETSCAN_UI_TESTING"] == "1" {
            let file = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("NetScan/ui-test-inventory.json")
            if ProcessInfo.processInfo.environment["NETSCAN_UI_RESET"] == "1" { try? FileManager.default.removeItem(at: file) }
            self.init(observeNetwork: true, inventory: DeviceInventory(file: file))
            return
        }
        #endif
        self.init(observeNetwork: true, inventory: DeviceInventory())
    }

    init(observeNetwork: Bool, inventory: DeviceInventory = DeviceInventory(file: nil)) {
        self.inventory = inventory
        inventory.didFailToSave = { [weak self] in self?.objectWillChange.send() }
        OUIVendorDatabase.loadDatabaseIfNeeded()
        #if DEBUG
        if ProcessInfo.processInfo.environment["NETSCAN_UI_TESTING"] == "1" {
            isLANConnected = true
            currentSSID = "UI Test Network"
            devices = [NetworkDevice(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                                     ipAddress: "127.0.0.1", macAddress: "B8:27:EB:00:00:01",
                                     hostname: "Test Network Device", vendor: "Network Device")]
            didAutoScan = true
            networkScope = "UI Test Network"
            networkIsCertain = true
            associateDevices()
            history = inventory.allHistory
            if history.isEmpty {
                inventory.recordScan(id: UUID(), network: networkScope, devices: devices)
                history = inventory.allHistory
            }
            return
        }
        #endif
        guard observeNetwork else { return }
        
        let initialInterface = NetworkInterfaceService.shared.getCurrentInterface()
        self.isLANConnected = initialInterface.isLAN
        self.currentSSID = initialInterface.ssid
        self.lastNetworkId = initialInterface.networkIdentifier
        configureInventory(initialInterface)
        
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
            configureInventory(newInterface)
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
        #if DEBUG
        if ProcessInfo.processInfo.environment["NETSCAN_UI_TESTING"] == "1" {
            inventory.recordScan(id: UUID(), network: networkScope, devices: devices)
            history = inventory.allHistory
            inventory.flush()
            return
        }
        #endif
        
        let interface = NetworkInterfaceService.shared.getCurrentInterface()
        guard interface.isLAN else {
            // Subnet scanning is only available on a Wi-Fi or Ethernet LAN
            return
        }
        
        isScanning = true
        scanProgress = 0.0
        scanID = UUID()
        stopDeviceUpdates()
        configureInventory(interface)
        let run = scanID
        selectedFilterType = nil
        
        // Clear previous scan results before starting fresh scan
        devices.removeAll()
        
        // Pause traffic timer during scan to prevent simultaneous data access
        trafficTimer?.invalidate()
        trafficTimer = nil
        
        bonjour.startBrowsing { [weak self] observation in
            self?.acceptBonjour(observation, interface: interface, run: run)
        }
        SubnetScannerService.shared.scanSubnet(
            interface: interface,
            onProgress: { [weak self] progress in
                guard self?.scanID == run else { return }
                self?.scanProgress = progress * 0.95
            },
            onDeviceFound: { [weak self] newDevice in
                guard let self = self, self.scanID == run else { return }
                if let index = self.devices.firstIndex(where: { $0.ipAddress == newDevice.ipAddress }) {
                    self.devices[index].latencyMs = newDevice.latencyMs
                    self.devices[index].isGateway = newDevice.isGateway
                    self.devices[index].openPorts = Array(Set(self.devices[index].openPorts + newDevice.openPorts)).sorted()
                    self.devices[index].evidence += newDevice.evidence
                } else {
                    self.devices.append(newDevice)
                }
            },
            onCompletion: { [weak self] _ in
                guard let self = self, self.scanID == run else { return }
                let finish = DispatchWorkItem { [weak self] in
                    guard let self = self, self.scanID == run else { return }
                    self.completeDiscovery(run: run)
                }
                self.discoveryFinish = finish
                DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: finish)
            }
        )
    }
    
    private func configureInventory(_ interface: NetworkInterfaceInfo) {
        networkScope = DeviceInventory.networkScope(interface)
        networkIsCertain = !["", "Wi-Fi Network", "Wi-Fi", "Ethernet"].contains(interface.ssid)
        history = inventory.allHistory
    }

    func associateDevices() {
        let hosts = devices.filter(\.hasResolvedHostname).map { $0.hostname.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ". ")) }
        let duplicates = Set(Dictionary(grouping: hosts, by: { $0 }).filter { $0.value.count > 1 }.keys)
        devices = devices.map { inventory.associate($0, network: networkScope, certainNetwork: networkIsCertain, duplicateHostnames: duplicates) }
    }

    func acceptBonjour(_ observation: BonjourObservation, interface: NetworkInterfaceInfo, run: UUID) {
        guard isScanning, scanID == run, interface.containsIPv4(observation.address) else { return }
        let index = devices.firstIndex { $0.ipAddress == observation.address }
        var device = index.map { devices[$0] } ?? NetworkDevice(ipAddress: observation.address, isGateway: observation.address == interface.gatewayIP)
        if !observation.hostname.isEmpty { device.hostname = String(observation.hostname.prefix(255)) }
        let identity = OUIVendorDatabase.identifyDevice(macAddress: nil, hostname: device.hostname)
        if identity.vendor != "Network Device" && device.vendor == "Generic Device" {
            device.vendor = identity.vendor
            device.deviceType = identity.deviceType
        }
        let evidence = IdentityEvidence(source: "Bonjour advertisement (self-reported)", observation: "\(observation.name): \(observation.type) on advertised TCP \(observation.port); hostname \(observation.hostname). This is not a port reachability check.")
        if !device.evidence.contains(where: { $0.id == evidence.id }) { device.evidence.append(evidence) }
        if let index = index { devices[index] = device } else { devices.append(device) }
    }

    func completeDiscovery(run: UUID) {
        guard scanID == run, isScanning else { return }
        bonjour.stopBrowsing()
        discoveryFinish = nil
        isScanning = false
        scanProgress = 1
        lastScanTimestamp = Date()
        associateDevices()
        historyRunID = run
        identityCoverage = .pending
        serviceCoverage = .pending
        inventory.recordScan(id: run, network: networkScope, devices: devices)
        history = inventory.allHistory
        startTrafficPolling()
        enrichVendorsOnline()
        checkDeviceServices()
    }

    private func syncHistory() {
        guard let run = historyRunID else { return }
        associateDevices()
        inventory.updateScan(id: run, devices: devices, identity: identityCoverage, services: serviceCoverage)
        history = inventory.allHistory
    }

    public func updateDevice(_ updatedDevice: NetworkDevice, kind: DeviceUpdateKind = .identity) {
        if kind == .annotation { associateDevices() }
        if let index = devices.firstIndex(where: { $0.id == updatedDevice.id }) {
            // Merge identity/diagnostics without overwriting newer traffic samples.
            switch kind {
            case .identity:
                devices[index].hostname = updatedDevice.hostname
                devices[index].vendor = updatedDevice.vendor
                devices[index].deviceType = updatedDevice.deviceType
                for evidence in updatedDevice.evidence where !devices[index].evidence.contains(where: { $0.id == evidence.id }) {
                    devices[index].evidence.append(evidence)
                }
            case .ports:
                serviceScanners.removeValue(forKey: updatedDevice.id)?.cancel()
                devices[index].openPorts = updatedDevice.openPorts
                devices[index].services = updatedDevice.services
                devices[index].serviceCheckState = .checked
                devices[index].assessedPorts = updatedDevice.assessedPorts
                pendingServiceChecks.removeAll { $0 == updatedDevice.id }
                startNextServiceChecks()
            case .annotation:
                devices[index].annotation = updatedDevice.annotation
                devices[index].savedMatch = .current
                inventory.saveAnnotation(updatedDevice.annotation, device: devices[index], network: networkScope)
                inventory.flush()
            }
            syncHistory()
        }
    }
    
    /// Queries the online Internet vendor database and LAN heuristics for any devices not recognized locally
    public func enrichVendorsOnline() {
        identityTask?.cancel()
        enrichmentID = UUID()
        let run = enrichmentID
        isUpdatingIdentities = true
        identityCoverage = .pending
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
                    let result: DeviceIdentityResult
                    if let lookup = lookup {
                        let value = await lookup(device)
                        result = DeviceIdentityResult(vendor: value.vendor, deviceType: value.deviceType, resolvedHostname: value.resolvedHostname, evidence: [])
                    } else {
                        result = await OUIVendorDatabase.identifyDeviceWithEvidence(ipAddress: device.ipAddress, macAddress: device.macAddress, hostname: device.hostname)
                    }
                    guard !Task.isCancelled, self?.enrichmentID == run else { return }
                    // A manual lookup may have supplied a newer identity while this request waited.
                    guard let current = self?.devices.first(where: { $0.id == device.id }),
                          current.hostname == device.hostname, current.vendor == device.vendor,
                          current.deviceType == device.deviceType else { continue }
                    self?.applyIdentity(result, to: device.id)
                    self?.syncHistory()
                }
            }
            guard self?.enrichmentID == run else { return }
            self?.isUpdatingIdentities = false
            self?.identityTask = nil
            self?.identityCoverage = .completed
            self?.syncHistory()
        }
    }

    private func applyIdentity(_ result: DeviceIdentityResult, to id: UUID) {
        guard let index = devices.firstIndex(where: { $0.id == id }) else { return }
        if let host = result.resolvedHostname, !host.isEmpty, host != devices[index].ipAddress {
            devices[index].hostname = host
        }
        if !["", "Unknown", "Network Device", "Generic Device"].contains(result.vendor) {
            devices[index].vendor = result.vendor
        }
        if result.deviceType != .unknown { devices[index].deviceType = result.deviceType }
        for evidence in result.evidence where !devices[index].evidence.contains(where: { $0.id == evidence.id }) {
            devices[index].evidence.append(evidence)
        }
    }

    func checkDeviceServices() {
        serviceCoverage = .pending
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
                if let index = self.devices.firstIndex(where: { $0.id == id }) {
                    self.devices[index].assessedPorts = scanner.completedPorts
                }
                self.serviceScanners.removeValue(forKey: id)
                self.mergeServiceCheck(results, into: id)
                self.startNextServiceChecks()
            })
        }
        if serviceScanners.isEmpty && pendingServiceChecks.isEmpty { serviceCoverage = .completed }
        syncHistory()
    }

    func mergeServiceCheck(_ results: [PortScanResult], into id: UUID) {
        guard let index = devices.firstIndex(where: { $0.id == id }) else { return }
        let unaffected = devices[index].openPorts.filter { !Self.securityPorts.contains($0) }
        devices[index].openPorts = Array(Set(unaffected + results.filter(\.isOpen).map(\.port))).sorted()
        devices[index].services = devices[index].openPorts.map { KnownPorts.service(for: $0) }
        devices[index].serviceCheckState = .checked
    }

    public func stopDeviceUpdates() {
        discoveryFinish?.cancel()
        discoveryFinish = nil
        bonjour.stopBrowsing()
        if identityCoverage == .pending { identityCoverage = .cancelled }
        if serviceCoverage == .pending { serviceCoverage = .cancelled }
        syncHistory()
        historyRunID = nil
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
        inventory.flush()
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
