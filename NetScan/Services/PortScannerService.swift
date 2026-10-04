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
    
    private var isCancelled = false
    private let queue = DispatchQueue(label: "com.netscan.portscanner", attributes: .concurrent)
    
    public init() {}
    
    public func scanPorts(
        targetIP: String,
        ports: [Int] = [21, 22, 23, 25, 53, 80, 110, 139, 143, 443, 445, 548, 554, 631, 8080, 8443, 9000, 3389, 5000, 5353, 7000, 8008, 9100],
        onPortFound: @escaping (PortScanResult) -> Void,
        onProgress: @escaping (Double) -> Void,
        onCompletion: @escaping ([PortScanResult]) -> Void
    ) {
        isCancelled = false
        var results: [PortScanResult] = []
        let lock = NSLock()
        let group = DispatchGroup()
        let total = Double(ports.count)
        var scanned = 0.0
        let semaphore = DispatchSemaphore(value: 8)
        
        for port in ports {
            if isCancelled { break }
            group.enter()
            semaphore.wait()
            
            queue.async { [weak self] in
                guard let self = self, !self.isCancelled else {
                    semaphore.signal()
                    group.leave()
                    return
                }
                
                self.checkPort(ip: targetIP, port: port) { isOpen in
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
                        DispatchQueue.main.async { onPortFound(res) }
                    }
                    lock.unlock()
                    
                    DispatchQueue.main.async { onProgress(progress) }
                    semaphore.signal()
                    group.leave()
                }
            }
        }
        
        group.notify(queue: .main) {
            onProgress(1.0)
            onCompletion(results.sorted { $0.port < $1.port })
        }
    }
    
    public func cancel() {
        isCancelled = true
    }
    
    private func checkPort(ip: String, port: Int, completion: @escaping (Bool) -> Void) {
        let host = NWEndpoint.Host(ip)
        guard let p = NWEndpoint.Port(rawValue: UInt16(port)) else {
            completion(false)
            return
        }
        
        let connection = NWConnection(host: host, port: p, using: .tcp)
        var responded = false
        
        let timeoutWork = DispatchWorkItem {
            if !responded {
                responded = true
                connection.cancel()
                completion(false)
            }
        }
        
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.45, execute: timeoutWork)
        
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                if !responded {
                    responded = true
                    timeoutWork.cancel()
                    connection.cancel()
                    completion(true)
                }
            case .failed, .cancelled:
                if !responded {
                    responded = true
                    timeoutWork.cancel()
                    completion(false)
                }
            default:
                break
            }
        }
        
        connection.start(queue: .global())
    }
}
