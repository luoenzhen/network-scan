//
//  TrafficMonitorService.swift
//  NetScan
//
//  Measures and computes live network throughput (Upload and Download in KB/second)
//  for individual devices and aggregate network interfaces.
//

import Foundation
import Combine
import Darwin

public class TrafficMonitorService: ObservableObject {
    public static let shared = TrafficMonitorService()
    
    @Published public var currentUploadKbps: Double = 0.0
    @Published public var currentDownloadKbps: Double = 0.0
    @Published public var peakUploadKbps: Double = 0.0
    @Published public var peakDownloadKbps: Double = 0.0
    @Published public var totalBytesUploaded: UInt64 = 0
    @Published public var totalBytesDownloaded: UInt64 = 0
    @Published public var recentThroughputPoints: [TrafficDataPoint] = []
    
    private var timer: Timer?
    private let maxHistoryPoints = 30
    private var previousSample: (network: String, sent: UInt64, received: UInt64, time: Date)?
    
    public init() {
        #if DEBUG
        if ProcessInfo.processInfo.environment["NETSCAN_UI_TESTING"] == "1" { return }
        #endif
        startMonitoring()
    }
    
    public func startMonitoring() {
        stopMonitoring()
        
        // Timer fires every 1.0 second to update traffic rates
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tickMetrics()
        }
    }
    
    public func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        previousSample = nil
        currentUploadKbps = 0
        currentDownloadKbps = 0
    }
    
    private func tickMetrics() {
        let currentInterface = NetworkInterfaceService.shared.getCurrentInterface()
        recordSample(interface: currentInterface, counters: Self.interfaceBytes(name: currentInterface.interfaceName), time: Date())
    }

    func recordSample(interface currentInterface: NetworkInterfaceInfo, counters: (sent: UInt64, received: UInt64)?, time now: Date) {
        guard currentInterface.isConnected else {
            currentUploadKbps = 0.0
            currentDownloadKbps = 0.0
            previousSample = nil
            return
        }
        guard let counters = counters else {
            currentUploadKbps = 0
            currentDownloadKbps = 0
            previousSample = nil
            return
        }
        let previous = previousSample
        previousSample = (currentInterface.networkIdentifier, counters.sent, counters.received, now)
        guard let previous = previous, previous.network == currentInterface.networkIdentifier,
              counters.sent >= previous.sent, counters.received >= previous.received,
              now.timeIntervalSince(previous.time) > 0 else {
            currentUploadKbps = 0
            currentDownloadKbps = 0
            return
        }
        let elapsed = now.timeIntervalSince(previous.time)
        let deltaUpBytes = counters.sent - previous.sent
        let deltaDownBytes = counters.received - previous.received
        currentUploadKbps = Double(deltaUpBytes) / elapsed / 1024
        currentDownloadKbps = Double(deltaDownBytes) / elapsed / 1024
        
        if currentUploadKbps > peakUploadKbps { peakUploadKbps = currentUploadKbps }
        if currentDownloadKbps > peakDownloadKbps { peakDownloadKbps = currentDownloadKbps }
        
        totalBytesUploaded += deltaUpBytes
        totalBytesDownloaded += deltaDownBytes
        
        let point = TrafficDataPoint(
            uploadKbps: currentUploadKbps,
            downloadKbps: currentDownloadKbps
        )
        recentThroughputPoints.append(point)
        if recentThroughputPoints.count > maxHistoryPoints {
            recentThroughputPoints.removeFirst()
        }
    }
    
    public func updateDeviceTraffic(devices: inout [NetworkDevice]) {
        let currentInterface = NetworkInterfaceService.shared.getCurrentInterface()
        guard currentInterface.isLAN else {
            for i in 0..<devices.count {
                devices[i].uploadSpeedKbps = 0.0
                devices[i].downloadSpeedKbps = 0.0
            }
            return
        }
        
        for i in 0..<devices.count {
            if !devices[i].isOnline || !devices[i].isLocalDevice {
                devices[i].uploadSpeedKbps = 0.0
                devices[i].downloadSpeedKbps = 0.0
                continue
            }
            
            devices[i].uploadSpeedKbps = currentUploadKbps
            devices[i].downloadSpeedKbps = currentDownloadKbps
            devices[i].totalBytesSent = totalBytesUploaded
            devices[i].totalBytesReceived = totalBytesDownloaded
        }
    }

    static func interfaceBytes(name: String) -> (sent: UInt64, received: UInt64)? {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0 else { return nil }
        defer { freeifaddrs(addresses) }
        var pointer = addresses
        while let current = pointer {
            let interface = current.pointee
            if String(cString: interface.ifa_name) == name,
               interface.ifa_addr?.pointee.sa_family == UInt8(AF_LINK),
               let data = interface.ifa_data {
                let counters = data.assumingMemoryBound(to: if_data.self).pointee
                return (UInt64(counters.ifi_obytes), UInt64(counters.ifi_ibytes))
            }
            pointer = interface.ifa_next
        }
        return nil
    }
}
