//
//  DeviceRowView.swift
//  NetScan
//
//  List item rendering a single LAN device with multi-row layout:
//  Row 1: Full Device Name & Badges
//  Row 2: Network Address (IP and MAC)
//  Row 3: Live Network Traffic (Upload & Download in KB/s)
//

import SwiftUI

public struct DeviceRowView: View {
    public let device: NetworkDevice
    
    public init(device: NetworkDevice) {
        self.device = device
    }
    
    public var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // Device Type Icon (aligned to top)
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(iconBackgroundColor.opacity(0.15))
                    .frame(width: 44, height: 44)
                
                Image(systemName: device.deviceType.iconName)
                    .font(.system(size: 20))
                    .foregroundColor(iconBackgroundColor)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                // ROW 1: Full Device Name (No truncation)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .center, spacing: 6) {
                        Text(device.displayName)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        if device.isGateway {
                            Text("GATEWAY")
                                .font(.system(size: 9, weight: .heavy))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.2))
                                .foregroundColor(.orange)
                                .cornerRadius(4)
                        } else if device.isLocalDevice {
                            Text("THIS IPHONE")
                                .font(.system(size: 9, weight: .heavy))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.2))
                                .foregroundColor(.blue)
                                .cornerRadius(4)
                        }
                    }
                    
                    if !device.vendor.isEmpty && !device.displayName.contains(device.vendor) {
                        Text(device.vendor)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                // ROW 2: Network Address (IP Address & MAC Address on the next row)
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Text("IP:")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.secondary)
                        Text(device.ipAddress)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(.primary)
                    }
                    
                    Text("•")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 4) {
                        Text("MAC:")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.secondary)
                        Text(device.macAddress)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                
                // ROW 3: Network Traffic on the next next row (Download & Upload in KB/s)
                HStack(spacing: 10) {
                    // Download Speed in KB/s
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundColor(.green)
                        Text(device.formattedDownload)
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(.green)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.green.opacity(0.12))
                    .cornerRadius(6)
                    
                    // Upload Speed in KB/s
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundColor(.blue)
                        Text(device.formattedUpload)
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(.blue)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.blue.opacity(0.12))
                    .cornerRadius(6)
                    
                    Spacer()
                    
                    // Response Latency / Ports
                    if device.latencyMs > 0 {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 5, height: 5)
                            Text(String(format: "%.1f ms", device.latencyMs))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                }
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
