//
//  DeviceDetailView.swift
//  NetScan
//
//  Detailed view for a selected device: network identity, live bandwidth (KB/s),
//  open ports, ping RTT diagnostics, and device packet stream.
//

import SwiftUI

@MainActor
public struct DeviceDetailView: View {
    @StateObject private var viewModel: DeviceDetailViewModel
    @State private var wolAlertMessage: String?
    @State private var showWolAlert = false
    private let sourceDevice: NetworkDevice
    @Environment(\.scenePhase) private var scenePhase
    
    public init(device: NetworkDevice, onUpdate: ((NetworkDevice, DeviceUpdateKind) -> Void)? = nil) {
        sourceDevice = device
        _viewModel = StateObject(wrappedValue: DeviceDetailViewModel(device: device, onDeviceUpdated: onUpdate))
    }
    
    public var body: some View {
        List {
            // Identity Header Section
            Section {
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.12))
                            .frame(width: 72, height: 72)
                        Image(systemName: viewModel.device.deviceType.iconName)
                            .font(.system(size: 34))
                            .foregroundColor(.blue)
                    }
                    
                    VStack(spacing: 4) {
                        Text(viewModel.device.displayName)
                            .font(.title2)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                        
                        Text(viewModel.device.vendor)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack(spacing: 6) {
                        Circle()
                            .fill(viewModel.device.isOnline ? Color.green : Color.secondary)
                            .frame(width: 8, height: 8)
                        Text(viewModel.device.isOnline ? "Online & Reachable" : "Offline")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(viewModel.device.isOnline ? .green : .secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background((viewModel.device.isOnline ? Color.green : Color.secondary).opacity(0.12))
                    .cornerRadius(12)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            
            // Live Bandwidth Traffic Section (Upload & Download in KB/s)
            Section(header: Text("Local Device Traffic"), footer: Text("iOS does not expose other devices' traffic. Remote readings are unavailable.")) {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundColor(.green)
                            Text("DOWNLOAD")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.secondary)
                        }
                        Text(viewModel.device.formattedDownload)
                            .font(.system(size: 20, weight: .bold, design: .monospaced))
                            .foregroundColor(.green)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        HStack {
                            Image(systemName: "arrow.up.circle.fill")
                                .foregroundColor(.blue)
                            Text("UPLOAD")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.secondary)
                        }
                        Text(viewModel.device.formattedUpload)
                            .font(.system(size: 20, weight: .bold, design: .monospaced))
                            .foregroundColor(.blue)
                    }
                }
                .padding(.vertical, 4)
                
                HStack {
                    Text("Total Session Traffic")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(viewModel.device.formattedTotalTransfer)
                        .fontWeight(.semibold)
                }
            }
            
            // Network Technical Specs
            Section(header: Text("Technical Details")) {
                detailRow(label: "IP Address", value: viewModel.device.ipAddress)
                detailRow(label: "MAC Address", value: viewModel.device.hasKnownMACAddress ? viewModel.device.macAddress : "Unavailable on iOS")
                detailRow(label: "Hostname", value: viewModel.device.hostname)
                HStack {
                    Text("Hardware Vendor")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(viewModel.device.vendor)
                        .fontWeight(.semibold)
                    if viewModel.device.vendor == "Network Device" || viewModel.device.vendor == "Unknown" || viewModel.device.vendor.isEmpty {
                        Button(action: {
                            viewModel.searchVendorOnline()
                        }) {
                            HStack(spacing: 4) {
                                if viewModel.isSearchingOnlineVendor {
                                    ProgressView()
                                        .scaleEffect(0.65)
                                        .frame(width: 14, height: 14)
                                } else {
                                    Image(systemName: "globe")
                                }
                                Text(viewModel.isSearchingOnlineVendor ? "Searching..." : "Find Online")
                            }
                            .font(.caption2)
                            .fontWeight(.bold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.blue.opacity(0.15))
                            .foregroundColor(.blue)
                            .cornerRadius(6)
                        }
                        .buttonStyle(BorderlessButtonStyle())
                        .disabled(viewModel.isSearchingOnlineVendor)
                        .accessibilityIdentifier("find-vendor")
                    }
                }
                detailRow(label: "Device Category", value: viewModel.device.deviceType.rawValue)
                detailRow(label: "Round-Trip Latency", value: String(format: "%.1f ms", viewModel.device.latencyMs))
            }
            Section(header: Text("Security checks"), footer: Text("These are observable risk indicators, not proof of malicious behavior. Only TCP ports 21, 23, 139, 445, and 3389 are checked automatically; packet samples are not analyzed.")) {
                Text(viewModel.device.serviceCheckState.rawValue)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                ForEach(viewModel.device.securityFindings) { finding in
                    VStack(alignment: .leading, spacing: 4) {
                        Label(finding.title, systemImage: finding.requiresReview ? "exclamationmark.shield" : "info.circle")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(finding.requiresReview ? .orange : .secondary)
                        Text(finding.detail)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                if viewModel.device.serviceCheckState == .checked && !viewModel.device.securityFindings.contains(where: \.requiresReview) {
                    Text("No flagged services detected in the checked ports.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // Open Port Discovery Section
            Section(header: HStack {
                Text("Open Ports & Services")
                Spacer()
                if viewModel.isScanningPorts {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }) {
                if viewModel.openPorts.isEmpty && !viewModel.isScanningPorts {
                    Text("No open ports scanned yet.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(viewModel.openPorts) { portRes in
                        HStack {
                            ZStack {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.blue.opacity(0.15))
                                    .frame(width: 48, height: 28)
                                Text("\(portRes.port)")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.blue)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(portRes.serviceName)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text("TCP • Open")
                                    .font(.caption2)
                                    .foregroundColor(.green)
                            }
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                        }
                    }
                }
                
                Button(action: {
                    viewModel.runPortScan()
                }) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                        Text(viewModel.isScanningPorts ? "Scanning Ports (\(Int(viewModel.portScanProgress * 100))%)..." : "Scan Common Ports")
                    }
                    .font(.subheadline)
                    .fontWeight(.semibold)
                }
                .buttonStyle(BorderlessButtonStyle())
                .disabled(viewModel.isScanningPorts)
            }
            
            // Diagnostic Actions: Ping & Wake on LAN
            Section(header: Text("Actions & Diagnostics")) {
                Button(action: {
                    viewModel.togglePing()
                }) {
                    HStack {
                        Image(systemName: viewModel.isPinging ? "stop.circle.fill" : "waveform.path")
                            .foregroundColor(viewModel.isPinging ? .red : .blue)
                        Text(viewModel.isPinging ? "Stop Continuous Ping" : "Start Live Ping Test")
                        Spacer()
                        if viewModel.isPinging {
                            Text(String(format: "%.1f ms", viewModel.currentPingLatencyMs))
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.green)
                        }
                    }
                }
                .buttonStyle(BorderlessButtonStyle())
                
                Button(action: {
                    viewModel.sendWakeOnLAN { success, msg in
                        wolAlertMessage = msg
                        showWolAlert = true
                    }
                }) {
                    HStack {
                        Image(systemName: "power")
                            .foregroundColor(.orange)
                        Text("Send Wake-on-LAN Magic Packet")
                    }
                }
                .buttonStyle(BorderlessButtonStyle())
                
                VStack(alignment: .leading, spacing: 6) {
                    Button(action: {
                        viewModel.searchVendorOnline()
                    }) {
                        HStack {
                            Image(systemName: "globe.badge.chevron.backward")
                                .foregroundColor(.indigo)
                            Text(viewModel.isSearchingOnlineVendor ? "Searching Internet & LAN Identity..." : "Search Vendor from Internet")
                                .foregroundColor(.primary)
                            Spacer()
                            if viewModel.isSearchingOnlineVendor {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                        }
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    .disabled(viewModel.isSearchingOnlineVendor)
                    
                    if let msg = viewModel.searchStatusMessage {
                        Text(msg)
                            .font(.caption2)
                            .foregroundColor(msg.contains("Identified") ? .green : .secondary)
                            .padding(.leading, 24)
                    }
                }
            }
            
            // Device Specific Packets
            Section(header: Text("Sample Packets (\(viewModel.relatedPackets.count))"), footer: Text("Demonstration data; these packets are generated samples, not captured traffic.")) {
                if viewModel.relatedPackets.isEmpty {
                    Text("No sample packets associated with this IP yet.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(viewModel.relatedPackets.prefix(10)) { packet in
                        NavigationLink(destination: PacketDetailSheet(packet: packet)) {
                            PacketRowView(packet: packet)
                        }
                    }
                }
            }
        }
        .listStyle(InsetGroupedListStyle())
        .accessibilityIdentifier("device-detail")
        .navigationTitle(viewModel.device.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .alert(isPresented: $showWolAlert) {
            Alert(
                title: Text("Wake-on-LAN"),
                message: Text(wolAlertMessage ?? ""),
                dismissButton: .default(Text("OK"))
            )
        }
        .onAppear {
            viewModel.startPacketObserving()
        }
        .onChange(of: sourceDevice) { updated in
            viewModel.updateLiveDevice(updated)
        }
        .onDisappear {
            viewModel.stopPacketObserving()
        }
        .onChange(of: scenePhase) { phase in
            if phase == .background { viewModel.stopPacketObserving() }
            if phase == .active { viewModel.startPacketObserving() }
        }
    }
    
    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.primary)
                .multilineTextAlignment(.trailing)
        }
    }
}
