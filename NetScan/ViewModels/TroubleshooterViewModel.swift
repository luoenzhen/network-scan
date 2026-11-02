//
//  TroubleshooterViewModel.swift
//  NetScan
//
//  Runs the ordered network checks and exposes their results to the Diagnose tool.
//

import Foundation
import Combine

@MainActor
public class TroubleshooterViewModel: ObservableObject {
    @Published public private(set) var results: [TroubleshootResult] = []
    @Published public private(set) var isRunning = false
    @Published public private(set) var summary = ""

    private var task: Task<Void, Never>?
    private var runID = UUID()
    var checks = NetworkTroubleshooter.live

    public init() {}

    public func run() {
        cancel()
        let interface = NetworkInterfaceService.shared.getCurrentInterface()
        let gateway = interface.isLAN ? interface.gatewayIP : ""
        let run = UUID()
        runID = run
        results = []
        summary = ""
        isRunning = true
        let checks = self.checks
        task = Task { [weak self] in
            let all = await NetworkTroubleshooter.run(gateway: gateway, checks: checks) { result in
                guard let self = self, self.runID == run else { return }
                self.results.append(result)
            }
            guard let self = self, self.runID == run else { return }
            self.summary = NetworkTroubleshooter.summary(all)
            self.isRunning = false
            self.task = nil
        }
    }

    public func cancel() {
        runID = UUID()
        task?.cancel()
        task = nil
        if isRunning {
            isRunning = false
            summary = results.isEmpty ? "" : "Diagnosis cancelled."
        }
    }
}
