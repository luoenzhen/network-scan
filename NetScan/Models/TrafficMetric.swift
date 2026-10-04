//
//  TrafficMetric.swift
//  NetScan
//
//  Data structure for network bandwidth monitoring and historical throughput points.
//

import Foundation

public struct TrafficDataPoint: Identifiable, Codable {
    public let id: UUID
    public let timestamp: Date
    public let uploadKbps: Double
    public let downloadKbps: Double
    
    public init(id: UUID = UUID(), timestamp: Date = Date(), uploadKbps: Double, downloadKbps: Double) {
        self.id = id
        self.timestamp = timestamp
        self.uploadKbps = uploadKbps
        self.downloadKbps = downloadKbps
    }
}

public struct NetworkTrafficSummary {
    public var currentUploadKbps: Double
    public var currentDownloadKbps: Double
    public var peakUploadKbps: Double
    public var peakDownloadKbps: Double
    public var totalUploadedBytes: UInt64
    public var totalDownloadedBytes: UInt64
    public var packetCount: Int
    
    public init(
        currentUploadKbps: Double = 0.0,
        currentDownloadKbps: Double = 0.0,
        peakUploadKbps: Double = 0.0,
        peakDownloadKbps: Double = 0.0,
        totalUploadedBytes: UInt64 = 0,
        totalDownloadedBytes: UInt64 = 0,
        packetCount: Int = 0
    ) {
        self.currentUploadKbps = currentUploadKbps
        self.currentDownloadKbps = currentDownloadKbps
        self.peakUploadKbps = peakUploadKbps
        self.peakDownloadKbps = peakDownloadKbps
        self.totalUploadedBytes = totalUploadedBytes
        self.totalDownloadedBytes = totalDownloadedBytes
        self.packetCount = packetCount
    }
}
