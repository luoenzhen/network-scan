//
//  PortScannerView.swift
//  NetScan
//
//  Port scanner screen for scanning common or custom TCP ports on a specified network host,
//  with service banners, admin-page links and TLS certificate checks.
//

import SwiftUI

@MainActor
public struct PortScannerView: View {
    @ObservedObject var viewModel: NetworkToolsViewModel

    public init(viewModel: NetworkToolsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 12) {
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

            VStack(alignment: .leading, spacing: 6) {
                Picker("Ports", selection: $viewModel.useCustomPorts) {
                    Text("Common ports").tag(false)
                    Text("Custom").tag(true)
                }
                .pickerStyle(SegmentedPickerStyle())
                .disabled(viewModel.isScanningPorts)
                if viewModel.useCustomPorts {
                    TextField("Ports, e.g. 22, 80, 8000-8100", text: $viewModel.customPorts)
                        .keyboardType(.numbersAndPunctuation)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .padding(8)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(8)
                        .disabled(viewModel.isScanningPorts)
                        .accessibilityIdentifier("custom-ports")
                }
                if let error = viewModel.portScanError {
                    Text(error).font(.caption).foregroundColor(.red)
                }
            }
            .padding(.horizontal)

            if viewModel.isScanningPorts {
                ProgressView(value: viewModel.portProgress, total: 1.0)
                    .tint(.blue)
                    .padding(.horizontal)
            }

            // Open Ports Result List
            List {
                Section(header: Text("Open Ports Discovered (\(viewModel.portResults.count))"),
                        footer: Text(viewModel.scannedPortCount > 0 ? "\(viewModel.scannedPortCount) TCP ports checked on \(viewModel.scannedTarget). Banners are what each service reports about itself." : "")) {
                    if viewModel.portResults.isEmpty && !viewModel.isScanningPorts {
                        Text(viewModel.scannedPortCount > 0 ? "No open ports found." : "Tap Scan to audit standard ports, or choose Custom to enter your own.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(viewModel.portResults) { res in
                            portRow(res)
                        }
                    }
                }

                let tlsPorts = viewModel.portResults.map(\.port).filter { KnownPorts.tlsPorts.contains($0) }
                if !tlsPorts.isEmpty {
                    Section(header: Text("TLS certificates"), footer: Text("Read from the TLS handshake; the connection is closed before any request is sent.")) {
                        ForEach(tlsPorts, id: \.self) { port in
                            certificateRow(port: port)
                        }
                    }
                }
            }
            .listStyle(InsetGroupedListStyle())
        }
    }

    private func portRow(_ res: PortScanResult) -> some View {
        HStack {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: 58, height: 28)
                Text(String(res.port))
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.blue)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(res.serviceName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                if let banner = res.banner {
                    Text(verbatim: banner)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                } else {
                    Text("TCP / State: Open")
                        .font(.caption2)
                        .foregroundColor(.green)
                }
            }
            Spacer()
            if let url = viewModel.adminURL(for: res.port) {
                Link(destination: url) {
                    Label("Open", systemImage: "safari")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Open admin page on port \(res.port)")
            } else {
                Image(systemName: "lock.open.fill")
                    .font(.caption)
                    .foregroundColor(.green)
            }
        }
    }

    @ViewBuilder
    private func certificateRow(port: Int) -> some View {
        if let report = viewModel.tlsReports[port] {
            VStack(alignment: .leading, spacing: 4) {
                Text("Port \(String(port)): \(report.subject)").font(.subheadline.weight(.medium))
                if let notAfter = report.notAfter {
                    (Text("Expires ") + Text(notAfter, style: .date)).font(.caption)
                }
                ForEach(report.findings(), id: \.self) { finding in
                    Text(verbatim: finding).font(.caption)
                        .foregroundColor(report.trusted && !finding.hasPrefix("Certificate expire") ? .secondary : .orange)
                }
            }
        } else if viewModel.tlsChecking.contains(port) {
            HStack { ProgressView(); Text("Checking certificate on port \(String(port))…").font(.caption) }
        } else {
            Text("Port \(String(port)): no TLS certificate was received.").font(.caption).foregroundColor(.secondary)
        }
    }
}
