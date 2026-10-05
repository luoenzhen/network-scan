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
    
    private var trafficTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var lastNetworkId: String = ""
    
    public init() {
        OUIVendorDatabase.loadDatabaseIfNeeded()
        
        let initialInterface = NetworkInterfaceService.shared.getCurrentInterface()
        self.isLANConnected = initialInterface.isLAN
        self.currentSSID = initialInterface.ssid
        self.lastNetworkId = initialInterface.networkIdentifier
        
        if initialInterface.isLAN {
            startTrafficPolling()
        }
        
        // Listen to live network changes from NetworkInterfaceService
        NetworkInterfaceService.shared.$currentInterface
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newInterface in
                self?.handleInterfaceChange(newInterface)
            }
            .store(in: &cancellables)
    }
    
    private func handleInterfaceChange(_ newInterface: NetworkInterfaceInfo) {
        let currentNetId = newInterface.networkIdentifier
        self.isLANConnected = newInterface.isLAN
        self.currentSSID = newInterface.ssid
        
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
        
        // Clear previous scan results before starting fresh scan
        devices.removeAll()
        
        // Pause traffic timer during scan to prevent simultaneous data access
        trafficTimer?.invalidate()
        trafficTimer = nil
        
        SubnetScannerService.shared.scanSubnet(
            interface: interface,
            onProgress: { [weak self] progress in
                self?.scanProgress = progress
            },
            onDeviceFound: { [weak self] newDevice in
                guard let self = self else { return }
                if let index = self.devices.firstIndex(where: { $0.ipAddress == newDevice.ipAddress }) {
                    var updated = newDevice
                    updated.id = self.devices[index].id
                    self.devices[index] = updated
                } else {
                    self.devices.append(newDevice)
                }
            },
            onCompletion: { [weak self] _ in
                guard let self = self else { return }
                self.isScanning = false
                self.scanProgress = 1.0
                self.lastScanTimestamp = Date()
                self.startTrafficPolling()
            }
        )
    }
    
    public func updateDevice(_ updatedDevice: NetworkDevice) {
        if let index = devices.firstIndex(where: { $0.id == updatedDevice.id || $0.ipAddress == updatedDevice.ipAddress }) {
            devices[index] = updatedDevice
        }
    }
    
    /// Queries the online Internet vendor database and LAN heuristics for any devices not recognized locally
    public func enrichVendorsOnline() {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            var updatedDevices = self.devices
            var hasChanges = false
            
            for i in 0..<updatedDevices.count {
                let dev = updatedDevices[i]
                if dev.vendor == "Network Device" || dev.vendor == "Unknown" || dev.vendor.isEmpty {
                    let (vendor, type, resolvedHost) = await OUIVendorDatabase.identifyDeviceAsync(
                        ipAddress: dev.ipAddress,
                        macAddress: dev.macAddress,
                        hostname: dev.hostname
                    )
                    if let host = resolvedHost, !host.isEmpty, host != updatedDevices[i].hostname {
                        updatedDevices[i].hostname = host
                        hasChanges = true
                    }
                    if vendor != "Network Device" && vendor != "Unknown" && !vendor.isEmpty {
                        updatedDevices[i].vendor = vendor
                        if updatedDevices[i].deviceType == .unknown || updatedDevices[i].deviceType != type {
                            updatedDevices[i].deviceType = type
                        }
                        hasChanges = true
                    }
                }
            }
            
            if hasChanges {
                self.devices = updatedDevices
            }
        }
    }
    
    public func stopScan() {
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
