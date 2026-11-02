//
//  PingToolView.swift
//  NetScan
//
//  Continuous latency test tool with real-time RTT stats and history.
//

import SwiftUI
import Charts

@MainActor
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

                TextField("Port", text: $viewModel.pingPort)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .frame(width: 64)
                    .padding(10)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(10)
                    .disabled(viewModel.isPinging)
                    .accessibilityLabel("TCP port")

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

            if let error = viewModel.pingError {
                Text(error).font(.caption).foregroundColor(.red).padding(.horizontal)
            }

            // Statistics Summary Cards
            HStack(spacing: 10) {
                statCard(title: "AVG RTT", value: String(format: "%.1f ms", viewModel.avgRtt), color: .blue)
                statCard(title: "MIN RTT", value: String(format: "%.1f ms", viewModel.minRtt), color: .green)
                statCard(title: "MAX RTT", value: String(format: "%.1f ms", viewModel.maxRtt), color: .orange)
                statCard(title: "LOSS", value: String(format: "%.0f%%", viewModel.packetLoss), color: viewModel.packetLoss > 0 ? .red : .secondary)
            }
            .padding(.horizontal)

            latencyChart
                .frame(height: 120)
                .padding(.horizontal)

            // Ping Log History
            List {
                Section(header: Text("TCP Port \(String(viewModel.probedPort)) Probe Log (\(viewModel.pingResults.count))"), footer: Text("Measures TCP response time, including explicit connection refusals. This is not an ICMP ping test.")) {
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
                                Text("No TCP response")
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
    
    /// Response time per probe over the last 50; failed probes are marked on the baseline in red.
    private var latencyChart: some View {
        Chart {
            ForEach(viewModel.pingResults.filter(\.success)) { result in
                LineMark(x: .value("Probe", result.seq), y: .value("Response (ms)", result.rttMs))
                    .foregroundStyle(Color.blue)
                    .interpolationMethod(.monotone)
            }
            ForEach(viewModel.pingResults.filter { !$0.success }) { result in
                PointMark(x: .value("Probe", result.seq), y: .value("Response (ms)", 0.0))
                    .foregroundStyle(Color.red)
                    .symbolSize(20)
            }
        }
        .chartYAxisLabel("ms")
        .chartXAxis(.hidden)
        .overlay {
            if viewModel.pingResults.isEmpty {
                Text("Response times appear here while probing.")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
        .accessibilityLabel("Response time chart")
        .accessibilityValue(String(format: "Average %.1f milliseconds, %.0f percent failed", viewModel.avgRtt, viewModel.packetLoss))
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
