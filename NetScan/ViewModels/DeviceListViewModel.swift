//
//  DeviceListViewModel.swift
//  NetScan
//
//  Manages the scanned devices list, sorting, filtering, and real-time traffic updates.
//

import Foundation
import Combine

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
    
    private var trafficTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    public init() {
        OUIVendorDatabase.loadDatabaseIfNeeded()
        startTrafficPolling()
        loadDefaultSampleData()
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
        isScanning = true
        scanProgress = 0.0
        
        let interface = NetworkInterfaceService.shared.getCurrentInterface()
        
        SubnetScannerService.shared.scanSubnet(
            interface: interface,
            onProgress: { [weak self] progress in
                DispatchQueue.main.async {
                    self?.scanProgress = progress
                }
            },
            onDeviceFound: { [weak self] newDevice in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    if let index = self.devices.firstIndex(where: { $0.ipAddress == newDevice.ipAddress }) {
                        var updated = newDevice
                        updated.id = self.devices[index].id
                        self.devices[index] = updated
                    } else {
                        self.devices.append(newDevice)
                    }
                }
            },
            onCompletion: { [weak self] allDevices in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    self.isScanning = false
                    self.scanProgress = 1.0
                    self.lastScanTimestamp = Date()
                    if !allDevices.isEmpty {
                        var updatedList = self.devices
                        for dev in allDevices {
                            if let idx = updatedList.firstIndex(where: { $0.ipAddress == dev.ipAddress }) {
                                var u = dev
                                u.id = updatedList[idx].id
                                updatedList[idx] = u
                            } else {
                                updatedList.append(dev)
                            }
                        }
                        self.devices = updatedList
                    }
                    self.enrichVendorsOnline()
                }
            }
        )
    }
    
    /// Queries the online Internet vendor database for any devices not recognized locally
    public func enrichVendorsOnline() {
        for (index, device) in devices.enumerated() {
            if device.vendor == "Network Device" || device.vendor == "Unknown" || device.vendor.isEmpty {
                Task {
                    let (vendor, type) = await OUIVendorDatabase.identifyDeviceAsync(
                        macAddress: device.macAddress,
                        hostname: device.hostname
                    )
                    if vendor != "Network Device" && vendor != "Unknown" {
                        await MainActor.run {
                            if index < self.devices.count && self.devices[index].id == device.id {
                                self.devices[index].vendor = vendor
                                if self.devices[index].deviceType == .unknown {
                                    self.devices[index].deviceType = type
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    public func stopScan() {
        SubnetScannerService.shared.cancelScan()
        isScanning = false
    }
    
    private func startTrafficPolling() {
        trafficTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            TrafficMonitorService.shared.updateDeviceTraffic(devices: &self.devices)
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
    
    private func loadDefaultSampleData() {
        devices = [
            NetworkDevice(
                ipAddress: "192.168.1.1",
                macAddress: "00:14:D1:4A:2B:10",
                hostname: "Gateway.router",
                vendor: "TP-Link Technologies",
                deviceType: .router,
                isOnline: true,
                uploadSpeedKbps: 84.2,
                downloadSpeedKbps: 340.5,
                totalBytesSent: 25_400_000,
                totalBytesReceived: 89_200_000,
                latencyMs: 1.8,
                openPorts: [53, 80, 443],
                services: ["DNS", "HTTP Admin", "HTTPS"],
                isLocalDevice: false,
                isGateway: true
            ),
            NetworkDevice(
                ipAddress: "192.168.1.105",
                macAddress: "F0:18:98:3C:A1:7E",
                hostname: "iPhone-16-Pro",
                vendor: "Apple Inc.",
                deviceType: .phone,
                isOnline: true,
                uploadSpeedKbps: 18.4,
                downloadSpeedKbps: 76.2,
                totalBytesSent: 4_300_000,
                totalBytesReceived: 14_900_000,
                latencyMs: 0.9,
                openPorts: [5353],
                services: ["mDNS Bonjour"],
                isLocalDevice: true,
                isGateway: false
            ),
            NetworkDevice(
                ipAddress: "192.168.1.112",
                macAddress: "AC:BC:32:8E:44:91",
                hostname: "MacBook-Pro.local",
                vendor: "Apple Inc.",
                deviceType: .computer,
                isOnline: true,
                uploadSpeedKbps: 42.1,
                downloadSpeedKbps: 184.6,
                totalBytesSent: 18_900_000,
                totalBytesReceived: 62_400_000,
                latencyMs: 3.4,
                openPorts: [22, 445, 5000],
                services: ["SSH", "SMB File Sharing", "AirPlay"]
            ),
            NetworkDevice(
                ipAddress: "192.168.1.140",
                macAddress: "3C:E1:A1:2F:89:01",
                hostname: "Living-Room-Chromecast",
                vendor: "Google LLC",
                deviceType: .tv,
                isOnline: true,
                uploadSpeedKbps: 4.8,
                downloadSpeedKbps: 512.0,
                totalBytesSent: 1_200_000,
                totalBytesReceived: 145_000_000,
                latencyMs: 7.2,
                openPorts: [8008, 8009],
                services: ["Google Cast HTTP", "Google Cast Protobuf"]
            ),
            NetworkDevice(
                ipAddress: "192.168.1.185",
                macAddress: "24:0A:C4:11:92:4B",
                hostname: "ESP32-Smart-Plug",
                vendor: "Espressif Inc.",
                deviceType: .smartHome,
                isOnline: true,
                uploadSpeedKbps: 0.6,
                downloadSpeedKbps: 1.2,
                totalBytesSent: 340_000,
                totalBytesReceived: 510_000,
                latencyMs: 14.1,
                openPorts: [80],
                services: ["HTTP Dashboard"]
            ),
            NetworkDevice(
                ipAddress: "192.168.1.200",
                macAddress: "70:5A:0F:D4:21:66",
                hostname: "HP-ColorLaserJet-M254",
                vendor: "HP (Hewlett-Packard)",
                deviceType: .printer,
                isOnline: true,
                uploadSpeedKbps: 0.0,
                downloadSpeedKbps: 0.0,
                totalBytesSent: 120_000,
                totalBytesReceived: 2_400_000,
                latencyMs: 12.0,
                openPorts: [80, 443, 631, 9100],
                services: ["HTTP Web Admin", "HTTPS", "IPP Printing", "RAW JetDirect"]
            ),
            NetworkDevice(
                ipAddress: "192.168.1.220",
                macAddress: "FC:0F:4B:99:38:12",
                hostname: "PlayStation-5",
                vendor: "Sony Interactive Entertainment",
                deviceType: .gaming,
                isOnline: true,
                uploadSpeedKbps: 12.3,
                downloadSpeedKbps: 280.4,
                totalBytesSent: 8_700_000,
                totalBytesReceived: 98_000_000,
                latencyMs: 5.6,
                openPorts: [9295, 9304],
                services: ["Remote Play", "PSN Discovery"]
            ),
            NetworkDevice(
                ipAddress: "192.168.1.135",
                macAddress: "DC:A6:32:8B:22:E1",
                hostname: "Raspberry-Pi-4B",
                vendor: "Raspberry Pi Foundation",
                deviceType: .computer,
                isOnline: true,
                uploadSpeedKbps: 8.4,
                downloadSpeedKbps: 34.2,
                totalBytesSent: 5_400_000,
                totalBytesReceived: 18_200_000,
                latencyMs: 3.1,
                openPorts: [22, 80],
                services: ["SSH Remote", "HTTP Web Server"]
            )
        ]
    }
}
