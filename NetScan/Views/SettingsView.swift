//
//  SettingsView.swift
//  NetScan
//
//  App configuration, scanner parameters, AltStore source info, and version details.
//

import SwiftUI

public struct SettingsView: View {
    @AppStorage("scanTimeout") private var scanTimeout: Double = 0.4
    @AppStorage("maxConcurrentProbes") private var maxConcurrentProbes: Int = 16
    @AppStorage("trafficUpdateInterval") private var trafficUpdateInterval: Double = 1.0
    @AppStorage("autoRefreshOnLaunch") private var autoRefreshOnLaunch: Bool = true
    @AppStorage("watchInterval") private var watchInterval: Double = 300
    
    public init() {}
    
    public var body: some View {
        NavigationView {
            List {
                Section(header: Text("Scanner Configuration")) {
                    HStack {
                        Text("Probe Timeout")
                        Spacer()
                        Text(String(format: "%.1f s", scanTimeout))
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $scanTimeout, in: 0.1...1.5, step: 0.1)
                    
                    Stepper("Concurrency: \(maxConcurrentProbes) threads", value: $maxConcurrentProbes, in: 4...32)
                    
                    Toggle("Auto-Scan on Launch", isOn: $autoRefreshOnLaunch)
                }

                Section(header: Text("Watch Mode"), footer: Text("Watch mode is turned on from Devices. It rescans only while NetScan is open; iOS does not allow local-network scans in the background.")) {
                    Picker("Rescan Every", selection: $watchInterval) {
                        Text("2 minutes").tag(120.0)
                        Text("5 minutes").tag(300.0)
                        Text("15 minutes").tag(900.0)
                        Text("30 minutes").tag(1800.0)
                    }
                }
                
                Section(header: Text("Distribution & AltStore")) {
                    NavigationLink(destination: AltStoreInfoView()) {
                        HStack {
                            Image(systemName: "arrow.down.app.fill")
                                .foregroundColor(.blue)
                            Text("AltStore Sideloading Guide")
                        }
                    }
                    
                    HStack {
                        Text("Target Architecture")
                        Spacer()
                        Text("ARM64 (iOS 16+)")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Bundle Identifier")
                        Spacer()
                        Text("com.netscan.app")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                
                Section(header: Text("About NetScan")) {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0 (Build 1)")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Architecture")
                        Spacer()
                        Text("SwiftUI • MVVM • Combine")
                            .foregroundColor(.secondary)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("NetScan provides local device discovery, this device's traffic counters, TCP latency checks, port auditing, and Wake-on-LAN. Remote device traffic is unavailable. The packet inspector displays generated examples.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .listStyle(InsetGroupedListStyle())
            .navigationTitle("Settings")
        }
    }
}
