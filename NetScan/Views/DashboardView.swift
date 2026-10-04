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
    
    public var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Wi-Fi Status Card
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            ZStack {
                                Circle()
                                    .fill(Color.blue.opacity(0.15))
                                    .frame(width: 44, height: 44)
                                Image(systemName: "wifi")
                                    .font(.title3)
                                    .foregroundColor(.blue)
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
                                    .fill(Color.green)
                                    .frame(width: 8, height: 8)
                                Text("Online")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.green)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.12))
                            .cornerRadius(12)
                        }
                        
                        Divider()
                        
                        // Interface Specs Grid
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            metricItem(label: "IP Address", value: viewModel.networkInfo.ipAddress, icon: "iphone")
                            metricItem(label: "Subnet Mask", value: viewModel.networkInfo.subnetMask, icon: "square.grid.3x3")
                            metricItem(label: "Default Gateway", value: viewModel.networkInfo.gatewayIP, icon: "wifi.router")
                            metricItem(label: "Broadcast IP", value: viewModel.networkInfo.broadcastIP, icon: "antenna.radiowaves.left.and.right")
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
                                Text("\(deviceListVM.devices.count) devices found on \(viewModel.networkInfo.subnetDescription)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            
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
                        }
                        
                        if deviceListVM.isScanning {
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
                        }
                        
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
