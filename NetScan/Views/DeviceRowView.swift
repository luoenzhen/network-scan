//
//  DeviceRowView.swift
//  NetScan
//
//  List item rendering a single LAN device with live KB/s bandwidth counters.
//

import SwiftUI

public struct DeviceRowView: View {
    public let device: NetworkDevice
    
    public init(device: NetworkDevice) {
        self.device = device
    }
    
    public var body: some View {
        HStack(spacing: 12) {
            // Device Type Icon
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(iconBackgroundColor.opacity(0.15))
                    .frame(width: 44, height: 44)
                
                Image(systemName: device.deviceType.iconName)
                    .font(.system(size: 20))
                    .foregroundColor(iconBackgroundColor)
            }
            
            // Name, IP, Vendor
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(device.displayName)
                        .font(.body)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    
                    if device.isGateway {
                        Text("GATEWAY")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.2))
                            .foregroundColor(.orange)
                            .cornerRadius(4)
                    } else if device.isLocalDevice {
                        Text("THIS IPHONE")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.2))
                            .foregroundColor(.blue)
                            .cornerRadius(4)
                    }
                }
                
                HStack(spacing: 6) {
                    Text(device.ipAddress)
                        .font(.caption)
                        .foregroundColor(.primary)
                    
                    Text("•")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Text(device.vendor)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                if device.latencyMs > 0 {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                        Text(String(format: "%.1f ms", device.latencyMs))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        
                        if !device.openPorts.isEmpty {
                            Text("• \(device.openPorts.count) open ports")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            Spacer()
            
            // Live Bandwidth Metrics in KB/s
            VStack(alignment: .trailing, spacing: 3) {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.green)
                    Text(device.formattedDownload)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(.green)
                }
                
                HStack(spacing: 3) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.blue)
                    Text(device.formattedUpload)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(.blue)
                }
                
                Text(device.formattedTotalTransfer)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
    
    private var iconBackgroundColor: Color {
        if device.isGateway { return .orange }
        if device.isLocalDevice { return .blue }
        switch device.deviceType {
        case .router: return .orange
        case .phone: return .blue
        case .tablet: return .indigo
        case .computer: return .purple
        case .smartHome: return .green
        case .printer: return .teal
        case .gaming: return .red
        case .tv: return .pink
        case .unknown: return .gray
        }
    }
}
