//
//  MainTabView.swift
//  NetScan
//
//  Root navigation tab bar linking Dashboard, Devices, Packets, Tools, and Settings.
//

import SwiftUI

public struct MainTabView: View {
    @StateObject private var dashboardVM = DashboardViewModel()
    @StateObject private var deviceListVM = DeviceListViewModel()
    @StateObject private var packetStreamVM = PacketStreamViewModel()
    @State private var selectedTab = 0
    
    public init() {}
    
    public var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView(viewModel: dashboardVM, deviceListVM: deviceListVM, selectedTab: $selectedTab)
                .tabItem {
                    Label("Dashboard", systemImage: "speedometer")
                }
                .tag(0)
            
            DeviceListView(viewModel: deviceListVM)
                .tabItem {
                    Label("Devices", systemImage: "network")
                }
                .tag(1)
            
            PacketInspectorView(viewModel: packetStreamVM)
                .tabItem {
                    Label("Packets", systemImage: "doc.text.magnifyingglass")
                }
                .tag(2)
            
            NetworkToolsView()
                .tabItem {
                    Label("Tools", systemImage: "wrench.and.screwdriver")
                }
                .tag(3)
            
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(4)
        }
        .accentColor(.blue)
    }
}
