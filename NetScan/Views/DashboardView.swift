//
//  DashboardView.swift
//  NetScan
//
//  Overview screen displaying Wi-Fi metrics, gateway info, throughput meters, and quick actions.
//

import SwiftUI

public struct DashboardView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @ObservedObject var deviceListVM: DeviceListViewModel
    @Binding var selectedTab: Int
    @State private var navigateToDevices = false
    @State private var navigateToPackets = false
    
    public init(viewModel: DashboardViewModel, deviceListVM: DeviceListViewModel, selectedTab: Binding<Int> = .constant(0)) {
        self.viewModel = viewModel
        self.deviceListVM = deviceListVM
        self._selectedTab = selectedTab
    }
    
    private var statusIcon: String {
        if viewModel.networkInfo.isLAN {
            return "wifi"
        } else if viewModel.networkInfo.isConnected {
            return "antenna.radiowaves.left.and.right"
        } else {
            return "wifi.slash"
        }
    }
    
    private var statusColor: Color {
        if viewModel.networkInfo.isLAN {
            return .blue
        } else if viewModel.networkInfo.isConnected {
            return .orange
        } else {
            return .secondary
        }
    }
    
    private var badgeColor: Color {
        if viewModel.networkInfo.isLAN {
            return .green
        } else if viewModel.networkInfo.isConnected {
            return .orange
        } else {
            return .red
        }
    }
    
    private var badgeTitle: String {
        if viewModel.networkInfo.isLAN {
            return "Online"
        } else if viewModel.networkInfo.isConnected {
            return "Cellular"
        } else {
            return "Offline"
        }
    }
    
    public var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Network Connection Status Card (Wi-Fi vs Cellular vs Disconnected)
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            ZStack {
                                Circle()
                                    .fill(statusColor.opacity(0.15))
                                    .frame(width: 44, height: 44)
                                Image(systemName: statusIcon)
                                    .font(.title3)
                                    .foregroundColor(statusColor)
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(viewModel.networkInfo.ssid)
                                    .font(.headline)
                                    .fontWeight(.bold)
                                Text(viewModel.networkInfo.interfaceType)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(badgeColor)
                                    .frame(width: 8, height: 8)
                                Text(badgeTitle)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(badgeColor)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(badgeColor.opacity(0.12))
                            .cornerRadius(12)
                        }
                        
                        Divider()
                        
                        // Interface Specs Grid
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            if viewModel.networkInfo.isLAN {
                                metricItem(label: "IP Address", value: viewModel.networkInfo.ipAddress, icon: "iphone")
                                metricItem(label: "Subnet Mask", value: viewModel.networkInfo.subnetMask, icon: "square.grid.3x3")
                                metricItem(label: "Default Gateway", value: viewModel.networkInfo.gatewayIP, icon: "wifi.router")
                                metricItem(label: "Broadcast IP", value: viewModel.networkInfo.broadcastIP, icon: "antenna.radiowaves.left.and.right")
                            } else if viewModel.networkInfo.isConnected {
                                metricItem(label: "Cellular IP", value: viewModel.networkInfo.ipAddress, icon: "iphone")
                                metricItem(label: "Network Mode", value: "Mobile WAN (4G/5G)", icon: "antenna.radiowaves.left.and.right")
                                metricItem(label: "Local Subnet", value: "None (Cellular)", icon: "network.slash")
                                metricItem(label: "LAN Status", value: "No Wi-Fi Connected", icon: "wifi.exclamationmark")
                            } else {
                                metricItem(label: "Status", value: "Offline", icon: "bolt.slash")
                                metricItem(label: "Network", value: "No Connection", icon: "antenna.radiowaves.left.and.right.slash")
                                metricItem(label: "Local Subnet", value: "None", icon: "network.slash")
                                metricItem(label: "LAN Status", value: "Disconnected", icon: "wifi.slash")
                            }
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(18)
                    
                    // Live Traffic Speeds (Upload / Download in KB/s)
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Real-Time Network Traffic")
                                .font(.headline)
                            Spacer()
                            Text("Updated every 1s")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        NetworkSpeedGaugeView(
                            uploadKbps: viewModel.uploadSpeedKbps,
                            downloadKbps: viewModel.downloadSpeedKbps
                        )
                    }
                    
                    // Discovered Devices Quick Summary Card
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Local Network Devices")
                                    .font(.headline)
                                if viewModel.networkInfo.isLAN {
                                    Text("\(deviceListVM.devices.count) devices found on \(viewModel.networkInfo.subnetDescription)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("No LAN active — connected to Cellular")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            
                            if viewModel.networkInfo.isLAN {
                                Button(action: {
                                    selectedTab = 1
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        deviceListVM.startScan()
                                    }
                                }) {
                                    HStack(spacing: 6) {
                                        if deviceListVM.isScanning {
                                            ProgressView()
                                                .progressViewStyle(CircularProgressViewStyle())
                                                .scaleEffect(0.8)
                                        } else {
                                            Image(systemName: "arrow.clockwise")
                                        }
                                        Text(deviceListVM.isScanning ? "Scanning..." : "Scan Now")
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(20)
                                }
                                .disabled(deviceListVM.isScanning)
                            } else {
                                HStack(spacing: 6) {
                                    Image(systemName: "wifi.slash")
                                    Text("Wi-Fi Required")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color(.tertiarySystemFill))
                                .foregroundColor(.secondary)
                                .cornerRadius(20)
                            }
                        }
                        
                        if !viewModel.networkInfo.isLAN {
                            HStack(spacing: 12) {
                                Image(systemName: "info.circle")
                                    .font(.title3)
                                    .foregroundColor(.orange)
                                Text("Local network scanning requires a Wi-Fi or Ethernet connection. Connect to Wi-Fi to discover LAN devices.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        } else if deviceListVM.isScanning {
                            VStack(spacing: 6) {
                                ProgressView(value: deviceListVM.scanProgress, total: 1.0)
                                    .tint(.blue)
                                HStack {
                                    Text("Probing subnet hosts...")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text("\(Int(deviceListVM.scanProgress * 100))%")
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                        .foregroundColor(.blue)
                                }
                            }
                            .transition(.opacity)
                        } else if deviceListVM.devices.isEmpty {
                            HStack(spacing: 10) {
                                Image(systemName: "network")
                                    .font(.title3)
                                    .foregroundColor(.blue)
                                Text("No devices discovered yet. Tap 'Scan Now' to scan the local network.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        } else {
                            // Mini preview of first 3 active devices
                            VStack(spacing: 8) {
                                ForEach(Array(deviceListVM.devices.prefix(3)), id: \.id) { dev in
                                    Button(action: {
                                        selectedTab = 1
                                    }) {
                                        HStack {
                                            Image(systemName: dev.deviceType.iconName)
                                                .foregroundColor(.blue)
                                                .frame(width: 24)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(dev.displayName)
                                                    .font(.subheadline)
                                                    .fontWeight(.semibold)
                                                    .lineLimit(1)
                                                    .foregroundColor(.primary)
                                                Text(dev.ipAddress)
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                            }
                                            Spacer()
                                            VStack(alignment: .trailing, spacing: 2) {
                                                Text("↓ \(dev.formattedDownload)")
                                                    .font(.caption)
                                                    .fontWeight(.medium)
                                                    .foregroundColor(.green)
                                                Text("↑ \(dev.formattedUpload)")
                                                    .font(.caption2)
                                                    .foregroundColor(.blue)
                                            }
                                        }
                                        .padding(.vertical, 4)
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(18)
                }
                .padding()
            }
            .navigationTitle("NetScan")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        viewModel.refreshInterface()
                    }) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                }
            }
        }
    }
    
    private func metricItem(label: String, value: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.footnote)
                .foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.caption)
                    .fontWeight(.bold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer()
        }
    }
}
