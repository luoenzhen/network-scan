//
//  NetworkToolsView.swift
//  NetScan
//
//  Diagnostic network toolbox: Ping latency tester, Port Scanner, and Wake-on-LAN.
//

import SwiftUI

public struct NetworkToolsView: View {
    @StateObject private var viewModel = NetworkToolsViewModel()
    @State private var selectedTab = 0
    
    public init() {}
    
    public var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Segmented Control
                Picker("Tool", selection: $selectedTab) {
                    Text("Ping").tag(0)
                    Text("Port Scan").tag(1)
                    Text("Wake on LAN").tag(2)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()
                
                // Active Tool Screen
                if selectedTab == 0 {
                    PingToolView(viewModel: viewModel)
                } else if selectedTab == 1 {
                    PortScannerView(viewModel: viewModel)
                } else {
                    WakeOnLANView(viewModel: viewModel)
                }
            }
            .navigationTitle("Network Tools")
        }
    }
}
