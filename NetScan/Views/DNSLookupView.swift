//
//  DNSLookupView.swift
//  NetScan
//
//  Resolves a hostname to its addresses, or an IP address to its reverse DNS name.
//

import SwiftUI

@MainActor
public struct DNSLookupView: View {
    @ObservedObject var viewModel: NetworkToolsViewModel

    public init(viewModel: NetworkToolsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                HStack {
                    Image(systemName: "character.book.closed")
                        .foregroundColor(.secondary)
                    TextField("Hostname or IP address", text: $viewModel.dnsQuery)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .keyboardType(.URL)
                        .onSubmit { viewModel.runDNSLookup() }
                }
                .padding(10)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(10)

                Button(action: { viewModel.runDNSLookup() }) {
                    Text(viewModel.isLookingUp ? "Looking up…" : "Look Up")
                        .fontWeight(.bold)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .disabled(viewModel.isLookingUp)
            }
            .padding(.horizontal)

            List {
                Section(footer: Text("Uses this iPhone's configured DNS resolver. Times include any answer cached on this iPhone.")) {
                    if viewModel.isLookingUp {
                        HStack { ProgressView(); Text("Resolving…").foregroundColor(.secondary) }
                    } else if let error = viewModel.dnsError {
                        Text(verbatim: error).foregroundColor(.orange)
                    } else if let result = viewModel.dnsResult {
                        LabeledContent("Query") { Text(verbatim: result.query) }
                        if let name = result.reverseName {
                            LabeledContent("Reverse name") { Text(verbatim: name).textSelection(.enabled) }
                        } else {
                            ForEach(result.addresses, id: \.self) { address in
                                LabeledContent(address.contains(":") ? "IPv6" : "IPv4") {
                                    Text(verbatim: address).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                                }
                            }
                        }
                        LabeledContent("Time") { Text(String(format: "%.1f ms", result.milliseconds)) }
                    } else {
                        Text("Enter a hostname to see its addresses, or an IP address to find its name.")
                            .font(.subheadline).foregroundColor(.secondary)
                    }
                }
            }
            .listStyle(InsetGroupedListStyle())
        }
    }
}
