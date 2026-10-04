//
//  PingToolView.swift
//  NetScan
//
//  Continuous latency test tool with real-time RTT stats and history.
//

import SwiftUI

public struct PingToolView: View {
    @ObservedObject var viewModel: NetworkToolsViewModel
    
    public init(viewModel: NetworkToolsViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        VStack(spacing: 16) {
            // Target Input and Start/Stop Button
            HStack(spacing: 10) {
                HStack {
                    Image(systemName: "globe")
                        .foregroundColor(.secondary)
                    TextField("IP or Hostname (e.g. 192.168.1.1)", text: $viewModel.pingTarget)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }
                .padding(10)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(10)
                
                Button(action: {
                    viewModel.togglePing()
                }) {
                    Text(viewModel.isPinging ? "Stop" : "Ping")
                        .fontWeight(.bold)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(viewModel.isPinging ? Color.red : Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
            }
            .padding(.horizontal)
            
            // Statistics Summary Cards
            HStack(spacing: 10) {
                statCard(title: "AVG RTT", value: String(format: "%.1f ms", viewModel.avgRtt), color: .blue)
                statCard(title: "MIN RTT", value: String(format: "%.1f ms", viewModel.minRtt), color: .green)
                statCard(title: "MAX RTT", value: String(format: "%.1f ms", viewModel.maxRtt), color: .orange)
                statCard(title: "LOSS", value: String(format: "%.0f%%", viewModel.packetLoss), color: viewModel.packetLoss > 0 ? .red : .secondary)
            }
            .padding(.horizontal)
            
            // Ping Log History
            List {
                Section(header: Text("Ping Response Log (\(viewModel.pingResults.count))")) {
                    ForEach(viewModel.pingResults.reversed()) { res in
                        HStack {
                            Circle()
                                .fill(res.success ? Color.green : Color.red)
                                .frame(width: 8, height: 8)
                            Text("Seq \(res.seq)")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.secondary)
                            Spacer()
                            if res.success {
                                Text("\(String(format: "%.1f", res.rttMs)) ms")
                                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.green)
                            } else {
                                Text("Request timed out")
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(.red)
                            }
                        }
                    }
                }
            }
            .listStyle(InsetGroupedListStyle())
        }
    }
    
    private func statCard(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(10)
    }
}
