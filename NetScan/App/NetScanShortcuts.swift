//
//  NetScanShortcuts.swift
//  NetScan
//
//  Siri and Shortcuts actions: open NetScan to scan the network, or probe a host's TCP port.
//

import AppIntents
import Combine
import Foundation

enum ShortcutAction: Equatable {
    case scanNetwork
}

/// Hands actions from intents to the running interface. Used only on the main thread.
final class ShortcutRouter: ObservableObject {
    static let shared = ShortcutRouter()
    @Published var pendingAction: ShortcutAction?
}

struct ScanNetworkIntent: AppIntent {
    static var title: LocalizedStringResource = "Scan Network"
    static var description = IntentDescription("Opens NetScan and scans the local network for devices.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        ShortcutRouter.shared.pendingAction = .scanNetwork
        return .result()
    }
}

struct ProbeHostIntent: AppIntent {
    static var title: LocalizedStringResource = "Probe Host"
    static var description = IntentDescription("Checks whether a host answers on a TCP port and reports its response time. An explicit refusal counts as an answer.")

    @Parameter(title: "Host", description: "IP address or hostname")
    var host: String

    @Parameter(title: "Port", default: 80)
    var port: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Probe \(\.$host) on TCP port \(\.$port)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let target = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let message: String
        if let value = UInt16(exactly: port), value > 0 {
            if let ms = await TCPReachability.probe(host: target, port: value, timeout: 3) {
                message = "\(target) answered on TCP \(port) in \(String(format: "%.1f", ms)) ms."
            } else {
                message = "\(target) did not answer on TCP \(port) within 3 seconds."
            }
        } else {
            message = "Enter a TCP port between 1 and 65535."
        }
        return .result(dialog: "\(message)")
    }
}

struct NetScanShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: ScanNetworkIntent(), phrases: ["Scan my network with \(.applicationName)"])
        AppShortcut(intent: ProbeHostIntent(), phrases: ["Probe a host with \(.applicationName)"])
    }
}
