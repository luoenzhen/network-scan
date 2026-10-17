//
//  PingDiagnosticService.swift
//  NetScan
//
//  Measures latency (RTT) in milliseconds, jitter, and packet loss.
//

import Foundation
import Network

public struct PingResult: Identifiable {
    public let id = UUID()
    public let seq: Int
    public let rttMs: Double
    public let success: Bool
    public let timestamp: Date
}

public class PingDiagnosticService: ObservableObject {
    public static let shared = PingDiagnosticService()
    
    @Published public var isRunning: Bool = false
    @Published public var history: [PingResult] = []
    @Published public var minRtt: Double = 0.0
    @Published public var avgRtt: Double = 0.0
    @Published public var maxRtt: Double = 0.0
    @Published public var packetLossPercent: Double = 0.0
    
    private var pingTimer: Timer?
    private var sequenceNumber = 0
    private var targetHost: String = ""
    private var sessionID = UUID()
    private var connections: [Int: NWConnection] = [:]
    
    public init() {}

    deinit {
        pingTimer?.invalidate()
        for connection in connections.values {
            connection.stateUpdateHandler = nil
            connection.cancel()
        }
    }
    
    public func startPinging(host: String) {
        stop()
        targetHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !targetHost.isEmpty else { return }
        sequenceNumber = 0
        history.removeAll()
        minRtt = 0
        avgRtt = 0
        maxRtt = 0
        packetLossPercent = 0
        isRunning = true
        sendSingleProbe()
        
        pingTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            self?.sendSingleProbe()
        }
    }
    
    public func stop() {
        sessionID = UUID()
        isRunning = false
        pingTimer?.invalidate()
        pingTimer = nil
        for connection in connections.values {
            connection.stateUpdateHandler = nil
            connection.cancel()
        }
        connections.removeAll()
    }
    
    private func sendSingleProbe() {
        sequenceNumber += 1
        let seq = sequenceNumber
        let session = sessionID
        let startTime = CFAbsoluteTimeGetCurrent()
        
        let endpointHost = NWEndpoint.Host(targetHost)
        // Probe via lightweight TCP connect (SYN -> SYN/ACK)
        let connection = NWConnection(host: endpointHost, port: 80, using: .tcp)
        connections[seq] = connection
        var finished = false

        // Both the timeout and connection events run on main, so completion is one-shot.
        let finish: (Bool) -> Void = { [weak self] success in
            guard !finished else { return }
            finished = true
            connection.stateUpdateHandler = nil
            connection.cancel()
            guard let self = self, self.isRunning, self.sessionID == session else { return }
            self.connections.removeValue(forKey: seq)
            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
            self.recordResult(seq: seq, rtt: success ? elapsed : 0, success: success, session: session)
        }
        
        let timeoutWork = DispatchWorkItem { finish(false) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: timeoutWork)

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                timeoutWork.cancel()
                finish(true)
            case .waiting(let error), .failed(let error):
                // Only an explicit TCP refusal proves that the host responded.
                if case .posix(.ECONNREFUSED) = error {
                    timeoutWork.cancel()
                    finish(true)
                } else if case .failed = state {
                    timeoutWork.cancel()
                    finish(false)
                }
            default:
                break
            }
        }
        
        connection.start(queue: .main)
    }
    
    private func recordResult(seq: Int, rtt: Double, success: Bool, session: UUID) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.isRunning, self.sessionID == session else { return }
            let item = PingResult(seq: seq, rttMs: round(rtt * 10) / 10, success: success, timestamp: Date())
            self.history.append(item)
            if self.history.count > 50 { self.history.removeFirst() }
            
            let successful = self.history.filter { $0.success }
            let failed = self.history.filter { !$0.success }
            self.packetLossPercent = Double(failed.count) / Double(self.history.count) * 100.0
            
            if successful.isEmpty {
                self.minRtt = 0
                self.maxRtt = 0
                self.avgRtt = 0
            } else {
                let rtts = successful.map { $0.rttMs }
                self.minRtt = rtts.min() ?? 0.0
                self.maxRtt = rtts.max() ?? 0.0
                self.avgRtt = round((rtts.reduce(0, +) / Double(rtts.count)) * 10) / 10
            }
        }
    }
}
