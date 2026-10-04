//
//  DeviceListView.swift
//  NetScan
//
//  Searchable, filterable list of scanned devices on the same Wi-Fi network.
//

import SwiftUI

public struct DeviceListView: View {
    @ObservedObject var viewModel: DeviceListViewModel
    
    public init(viewModel: DeviceListViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Scan Progress Banner
                if viewModel.isScanning {
                    VStack(spacing: 4) {
                        ProgressView(value: viewModel.scanProgress, total: 1.0)
                            .tint(.blue)
                        HStack {
                            Text("Scanning subnet...")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(Int(viewModel.scanProgress * 100))%")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.blue)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color(.secondarySystemBackground))
                    .transition(.opacity)
                }
                
                // Category Filter Pills
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        filterChip(title: "All (\(viewModel.devices.count))", isSelected: viewModel.selectedFilterType == nil) {
                            viewModel.selectedFilterType = nil
                        }
                        
                        ForEach(DeviceType.allCases, id: \.self) { type in
                            let count = viewModel.devices.filter { $0.deviceType == type }.count
                            if count > 0 {
                                filterChip(title: "\(type.rawValue) (\(count))", isSelected: viewModel.selectedFilterType == type) {
                                    viewModel.selectedFilterType = type
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                }
                .background(Color(.systemBackground))
                
                // Device List
                List {
                    Section(header: listHeader) {
                        ForEach(viewModel.filteredAndSortedDevices, id: \.id) { device in
                            NavigationLink(destination: DeviceDetailView(device: device)) {
                                DeviceRowView(device: device)
                            }
                        }
                    }
                }
                .listStyle(InsetGroupedListStyle())
                .searchable(text: $viewModel.searchText, prompt: "Search by IP, Name, or Vendor")
                .refreshable {
                    viewModel.startScan()
                }
            }
            .navigationTitle("Network Devices")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        Picker("Sort By", selection: $viewModel.sortOption) {
                            ForEach(DeviceSortOption.allCases) { opt in
                                Text(opt.rawValue).tag(opt)
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.arrow.down")
                            Text("Sort")
                        }
                        .font(.subheadline)
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        if viewModel.isScanning {
                            viewModel.stopScan()
                        } else {
                            viewModel.startScan()
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: viewModel.isScanning ? "stop.fill" : "play.fill")
                            Text(viewModel.isScanning ? "Stop" : "Scan")
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
        }
    }
    
    private var listHeader: some View {
        HStack {
            Text("\(viewModel.filteredAndSortedDevices.count) DEVICES FOUND")
                .font(.caption2)
                .foregroundColor(.secondary)
            Spacer()
            Text("SORT: \(viewModel.sortOption.rawValue.uppercased())")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
    
    private func filterChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .fontWeight(isSelected ? .bold : .medium)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.blue : Color(.secondarySystemBackground))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(16)
        }
    }
}
