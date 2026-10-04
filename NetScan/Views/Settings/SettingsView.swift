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
                        Text("NetScan is a comprehensive local network analyzer designed for iOS, featuring live subnet scanning, per-device throughput (KB/s), protocol packet decoding, port auditing, and AltStore support.")
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
