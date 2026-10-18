//
//  PortScannerService.swift
//  NetScan
//
//  Multi-threaded TCP port scanner for diagnostic network security audits.
//

import Foundation
import Network

public class PortScannerService {
    public static let shared = PortScannerService()
    
    private var currentScan: ScanCancellation?
    private let scanLock = NSLock()
    private let queue = DispatchQueue(label: "com.netscan.portscanner")
    
    public init() {}
    
    public func scanPorts(
        targetIP: String,
        ports: [Int] = [21, 22, 23, 25, 53, 80, 110, 139, 143, 443, 445, 548, 554, 631, 8080, 8443, 9000, 3389, 5000, 5353, 7000, 8008, 9100],
        onPortFound: @escaping (PortScanResult) -> Void,
        onProgress: @escaping (Double) -> Void,
        onCompletion: @escaping ([PortScanResult]) -> Void
    ) {
        let target = targetIP.trimmingCharacters(in: .whitespacesAndNewlines)
        let scan = ScanCancellation()
        scanLock.lock()
        currentScan?.cancel()
        currentScan = scan
        scanLock.unlock()
        // The producer can wait for slots without blocking the caller or callbacks.
        DispatchQueue.global(qos: .userInitiated).async {
            var results: [PortScanResult] = []
            let lock = NSLock()
            let group = DispatchGroup()
            let validPorts = target.isEmpty
                ? [] : Array(Set(ports.filter { (1...65535).contains($0) })).sorted()
            let total = Double(validPorts.count)
            var scanned = 0.0
            let semaphore = DispatchSemaphore(value: 8)
            
            for port in validPorts {
                if scan.isCancelled { break }
                group.enter()
                semaphore.wait()
                
                self.queue.async {
                    guard !scan.isCancelled else {
                        semaphore.signal()
                        group.leave()
                        return
                    }
                    
                    self.checkPort(ip: target, port: port) { isOpen in
                        lock.lock()
                        scanned += 1.0
                        let progress = scanned / total
                        if isOpen {
                            let res = PortScanResult(
                                port: port,
                                serviceName: KnownPorts.service(for: port),
                                isOpen: true
                            )
                            results.append(res)
                            DispatchQueue.main.async { if !scan.isCancelled { onPortFound(res) } }
                        }
                        lock.unlock()

                        DispatchQueue.main.async { if !scan.isCancelled { onProgress(progress) } }
                        semaphore.signal()
                        group.leave()
                    }
                }
            }

            group.notify(queue: .main) {
                guard !scan.isCancelled else { return }
                onProgress(1.0)
                onCompletion(results.sorted { $0.port < $1.port })
            }
        }
    }
    
    public func cancel() {
        scanLock.lock()
        currentScan?.cancel()
        scanLock.unlock()
    }
    
    private func checkPort(ip: String, port: Int, completion: @escaping (Bool) -> Void) {
        let host = NWEndpoint.Host(ip)
        guard let value = UInt16(exactly: port), value > 0,
              let p = NWEndpoint.Port(rawValue: value) else {
            completion(false)
            return
        }
        
        let connection = NWConnection(host: host, port: p, using: .tcp)
        var responded = false
        
        let timeoutWork = DispatchWorkItem {
            if !responded {
                responded = true
                connection.stateUpdateHandler = nil
                connection.cancel()
                completion(false)
            }
        }
        
        queue.asyncAfter(deadline: .now() + 0.45, execute: timeoutWork)
        
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                if !responded {
                    responded = true
                    timeoutWork.cancel()
                    connection.stateUpdateHandler = nil
                    connection.cancel()
                    completion(true)
                }
            case .failed, .cancelled:
                if !responded {
                    responded = true
                    timeoutWork.cancel()
                    connection.stateUpdateHandler = nil
                    completion(false)
                }
            default:
                break
            }
        }
        
        connection.start(queue: queue)
    }
}
