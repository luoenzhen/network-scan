//
//  NetworkToolsView.swift
//  NetScan
//
//  Diagnostic network toolbox: troubleshooter, TCP probe, port scanner, DNS lookup and Wake-on-LAN.
//

import SwiftUI

@MainActor
public struct NetworkToolsView: View {
    @StateObject private var viewModel = NetworkToolsViewModel()
    @StateObject private var troubleshooter = TroubleshooterViewModel()
    @State private var selectedTab = 0
    @Environment(\.scenePhase) private var scenePhase

    public init() {}

    public var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Segmented Control
                Picker("Tool", selection: $selectedTab) {
                    Text("Diagnose").tag(0)
                    Text("Probe").tag(1)
                    Text("Ports").tag(2)
                    Text("DNS").tag(3)
                    Text("WoL").tag(4)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()

                // Active Tool Screen
                switch selectedTab {
                case 0: TroubleshooterView(viewModel: troubleshooter)
                case 1: PingToolView(viewModel: viewModel)
                case 2: PortScannerView(viewModel: viewModel)
                case 3: DNSLookupView(viewModel: viewModel)
                default: WakeOnLANView(viewModel: viewModel)
                }
            }
            .navigationTitle("Network Tools")
        }
        .onDisappear { stopAll() }
        .onChange(of: scenePhase) { phase in
            if phase == .background { stopAll() }
        }
    }

    private func stopAll() {
        viewModel.stopDiagnostics()
        troubleshooter.cancel()
    }
}
