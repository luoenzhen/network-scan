//
//  TroubleshooterView.swift
//  NetScan
//
//  "Is it me or the network?" checklist that names the first failing step.
//

import SwiftUI

@MainActor
public struct TroubleshooterView: View {
    @ObservedObject var viewModel: TroubleshooterViewModel

    public init(viewModel: TroubleshooterViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        List {
            Section {
                Button {
                    if viewModel.isRunning { viewModel.cancel() } else { viewModel.run() }
                } label: {
                    HStack {
                        Image(systemName: viewModel.isRunning ? "stop.fill" : "stethoscope")
                        Text(viewModel.isRunning ? "Stop" : "Run Diagnosis").fontWeight(.semibold)
                        Spacer()
                        if viewModel.isRunning { ProgressView() }
                    }
                }
                .accessibilityIdentifier("run-diagnosis")
                if !viewModel.summary.isEmpty {
                    Text(verbatim: viewModel.summary)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(viewModel.results.contains { $0.status == .failed } ? .red : .primary)
                }
            }

            Section(header: Text("Checks"), footer: Text("Contacts captive.apple.com and Cloudflare (1.1.1.1, speed.cloudflare.com) to test internet access, read your public IP and download about 5 MB. Results describe this iPhone's connection only.")) {
                ForEach(TroubleshootStep.allCases) { step in
                    row(step: step, result: viewModel.results.first { $0.step == step })
                }
            }
        }
        .listStyle(InsetGroupedListStyle())
    }

    private func row(step: TroubleshootStep, result: TroubleshootResult?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            icon(for: result)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(step.rawValue).font(.subheadline.weight(.medium))
                if let result = result {
                    Text(verbatim: result.detail).font(.caption).foregroundColor(.secondary)
                } else if viewModel.isRunning && viewModel.results.count == TroubleshootStep.allCases.firstIndex(of: step) {
                    Text("Checking…").font(.caption).foregroundColor(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func icon(for result: TroubleshootResult?) -> some View {
        switch result?.status {
        case .passed: Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
        case .warning: Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
        case .failed: Image(systemName: "xmark.octagon.fill").foregroundColor(.red)
        case .skipped: Image(systemName: "minus.circle").foregroundColor(.secondary)
        case nil: Image(systemName: "circle").foregroundColor(.secondary)
        }
    }
}
