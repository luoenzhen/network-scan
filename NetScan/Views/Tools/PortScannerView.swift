//
//  PortScannerView.swift
//  NetScan
//
//  Port scanner screen for scanning common TCP ports on a specified network host.
//

import SwiftUI

public struct PortScannerView: View {
    @ObservedObject var viewModel: NetworkToolsViewModel
    
    public init(viewModel: NetworkToolsViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        VStack(spacing: 16) {
            // Target IP and Scan Button
            HStack(spacing: 10) {
                HStack {
                    Image(systemName: "server.rack")
                        .foregroundColor(.secondary)
                    TextField("Target IP (e.g. 192.168.1.1)", text: $viewModel.portScanTarget)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }
                .padding(10)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(10)
                
                Button(action: {
                    viewModel.runPortScan()
                }) {
                    Text(viewModel.isScanningPorts ? "Scanning..." : "Scan")
                        .fontWeight(.bold)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .disabled(viewModel.isScanningPorts)
            }
            .padding(.horizontal)
            
            if viewModel.isScanningPorts {
                ProgressView(value: viewModel.portProgress, total: 1.0)
                    .tint(.blue)
                    .padding(.horizontal)
            }
            
            // Open Ports Result List
            List {
                Section(header: Text("Open Ports Discovered (\(viewModel.portResults.count))")) {
                    if viewModel.portResults.isEmpty && !viewModel.isScanningPorts {
                        Text("No open ports found yet. Tap Scan to audit standard ports.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(viewModel.portResults) { res in
                            HStack {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.blue.opacity(0.15))
                                        .frame(width: 50, height: 28)
                                    Text("\(res.port)")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundColor(.blue)
                                }
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(res.serviceName)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    Text("TCP / State: Open")
                                        .font(.caption2)
                                        .foregroundColor(.green)
                                }
                                Spacer()
                                Image(systemName: "lock.open.fill")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                        }
                    }
                }
            }
            .listStyle(InsetGroupedListStyle())
        }
    }
}
