//
//  PacketInspectorView.swift
//  NetScan
//
//  Live network packet stream and analyzer screen.
//

import SwiftUI

public struct PacketInspectorView: View {
    @ObservedObject var viewModel: PacketStreamViewModel
    @State private var showingExportSheet = false
    @State private var exportedJSON = ""
    
    public init(viewModel: PacketStreamViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Status & Controls Banner
                HStack {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(viewModel.isCapturing ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                        Text(viewModel.isCapturing ? "LIVE CAPTURE ACTIVE" : "CAPTURE PAUSED")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(viewModel.isCapturing ? .green : .orange)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background((viewModel.isCapturing ? Color.green : Color.orange).opacity(0.12))
                    .cornerRadius(8)
                    
                    Spacer()
                    
                    Text("\(viewModel.packets.count) packets")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Button(action: {
                        viewModel.toggleCapture()
                    }) {
                        Image(systemName: viewModel.isCapturing ? "pause.circle.fill" : "play.circle.fill")
                            .font(.title3)
                            .foregroundColor(viewModel.isCapturing ? .orange : .green)
                    }
                    
                    Button(action: {
                        viewModel.clear()
                    }) {
                        Image(systemName: "trash")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemBackground))
                
                // Protocol Filter Chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        filterPill(title: "ALL", isSelected: viewModel.selectedProtocol == nil) {
                            viewModel.selectedProtocol = nil
                        }
                        
                        ForEach(PacketProtocol.allCases, id: \.self) { proto in
                            filterPill(title: proto.rawValue, isSelected: viewModel.selectedProtocol == proto) {
                                viewModel.selectedProtocol = proto
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                .background(Color(.systemBackground))
                
                // Live Packet Stream List
                List {
                    ForEach(viewModel.packets) { packet in
                        NavigationLink(destination: PacketDetailSheet(packet: packet)) {
                            PacketRowView(packet: packet)
                        }
                    }
                }
                .listStyle(PlainListStyle())
                .searchable(text: $viewModel.searchText, prompt: "Search packets by IP, host, or payload")
            }
            .navigationTitle("Packet Inspector")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        exportedJSON = viewModel.exportPacketsJSON()
                        showingExportSheet = true
                    }) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
            .sheet(isPresented: $showingExportSheet) {
                NavigationView {
                    ScrollView {
                        Text(exportedJSON)
                            .font(.system(size: 11, design: .monospaced))
                            .padding()
                    }
                    .navigationTitle("Export Packets (JSON)")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") {
                                showingExportSheet = false
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func filterPill(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isSelected ? Color.blue : Color(.secondarySystemBackground))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(12)
        }
    }
}
