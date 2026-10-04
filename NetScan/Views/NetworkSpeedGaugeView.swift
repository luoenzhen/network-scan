//
//  NetworkSpeedGaugeView.swift
//  NetScan
//
//  Visual speed meter widget displaying live upload/download in KB/second.
//

import SwiftUI

public struct NetworkSpeedGaugeView: View {
    public let uploadKbps: Double
    public let downloadKbps: Double
    
    public init(uploadKbps: Double, downloadKbps: Double) {
        self.uploadKbps = uploadKbps
        self.downloadKbps = downloadKbps
    }
    
    public var body: some View {
        HStack(spacing: 16) {
            // Download Card
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundColor(.green)
                    Text("DOWNLOAD")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                }
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(String(format: "%.1f", downloadKbps))
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundColor(.primary)
                    Text("KB/s")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                }
                ProgressView(value: min(downloadKbps, 2000.0), total: 2000.0)
                    .tint(.green)
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(14)
            
            // Upload Card
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "arrow.up.circle.fill")
                        .foregroundColor(.blue)
                    Text("UPLOAD")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                }
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(String(format: "%.1f", uploadKbps))
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundColor(.primary)
                    Text("KB/s")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                }
                ProgressView(value: min(uploadKbps, 1000.0), total: 1000.0)
                    .tint(.blue)
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(14)
        }
    }
}
