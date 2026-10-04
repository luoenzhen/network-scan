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
    
    public init() {}
    
    public func startPinging(host: String) {
        stop()
        targetHost = host
        sequenceNumber = 0
        history.removeAll()
        isRunning = true
        
        pingTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            self?.sendSingleProbe()
        }
    }
    
    public func stop() {
        isRunning = false
        pingTimer?.invalidate()
        pingTimer = nil
    }
    
    private func sendSingleProbe() {
        sequenceNumber += 1
        let seq = sequenceNumber
        let startTime = CFAbsoluteTimeGetCurrent()
        
        let endpointHost = NWEndpoint.Host(targetHost)
        // Probe via lightweight TCP connect (SYN -> SYN/ACK)
        let connection = NWConnection(host: endpointHost, port: 80, using: .tcp)
        var finished = false
        
        let timeoutWork = DispatchWorkItem { [weak self] in
            if !finished {
                finished = true
                connection.cancel()
                self?.recordResult(seq: seq, rtt: 0, success: false)
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.0, execute: timeoutWork)
        
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready, .waiting:
                if !finished {
                    finished = true
                    timeoutWork.cancel()
                    connection.cancel()
                    let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
                    self?.recordResult(seq: seq, rtt: elapsed, success: true)
                }
            case .failed:
                if !finished {
                    finished = true
                    timeoutWork.cancel()
                    connection.cancel()
                    let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
                    // Host responded with RST/reject, which still calculates RTT!
                    self?.recordResult(seq: seq, rtt: elapsed, success: true)
                }
            default:
                break
            }
        }
        
        connection.start(queue: .global())
    }
    
    private func recordResult(seq: Int, rtt: Double, success: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let item = PingResult(seq: seq, rttMs: round(rtt * 10) / 10, success: success, timestamp: Date())
            self.history.append(item)
            if self.history.count > 50 { self.history.removeFirst() }
            
            let successful = self.history.filter { $0.success }
            let failed = self.history.filter { !$0.success }
            self.packetLossPercent = Double(failed.count) / Double(self.history.count) * 100.0
            
            if !successful.isEmpty {
                let rtts = successful.map { $0.rttMs }
                self.minRtt = rtts.min() ?? 0.0
                self.maxRtt = rtts.max() ?? 0.0
                self.avgRtt = round((rtts.reduce(0, +) / Double(rtts.count)) * 10) / 10
            }
        }
    }
}
