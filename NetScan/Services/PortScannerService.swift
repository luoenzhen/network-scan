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
    private var assessedPorts: [Int] = []
    public var completedPorts: [Int] { scanLock.withLock { assessedPorts } }
    private let queue = DispatchQueue(label: "com.netscan.portscanner")
    
    public init() {}
    
    public func scanPorts(
        targetIP: String,
        ports: [Int] = KnownPorts.defaultScanPorts,
        grabBanners: Bool = false,
        onPortFound: @escaping (PortScanResult) -> Void,
        onProgress: @escaping (Double) -> Void,
        onCompletion: @escaping ([PortScanResult]) -> Void
    ) {
        let target = targetIP.trimmingCharacters(in: .whitespacesAndNewlines)
        let scan = ScanCancellation()
        scanLock.lock()
        currentScan?.cancel()
        currentScan = scan
        assessedPorts = []
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
            var assessed: [Int] = []
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
                    
                    self.checkPort(ip: target, port: port) { isOpen, determinate in
                        let record: (String?) -> Void = { banner in
                            lock.lock()
                            if determinate { assessed.append(port) }
                            scanned += 1.0
                            let progress = scanned / total
                            if isOpen {
                                let res = PortScanResult(
                                    port: port,
                                    serviceName: KnownPorts.service(for: port),
                                    isOpen: true,
                                    banner: banner
                                )
                                results.append(res)
                                DispatchQueue.main.async { if !scan.isCancelled { onPortFound(res) } }
                            }
                            lock.unlock()

                            DispatchQueue.main.async { if !scan.isCancelled { onProgress(progress) } }
                            semaphore.signal()
                            group.leave()
                        }
                        // The banner read keeps this port's slot, so at most eight sockets stay open.
                        if isOpen && grabBanners && !scan.isCancelled {
                            self.grabBanner(ip: target, port: port, completion: record)
                        } else {
                            record(nil)
                        }
                    }
                }
            }

            group.notify(queue: .main) {
                guard !scan.isCancelled else { return }
                self.scanLock.withLock { self.assessedPorts = assessed.sorted() }
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
    
    private func checkPort(ip: String, port: Int, completion: @escaping (Bool, Bool) -> Void) {
        let host = NWEndpoint.Host(ip)
        guard let value = UInt16(exactly: port), value > 0,
              let p = NWEndpoint.Port(rawValue: value) else {
            completion(false, false)
            return
        }
        
        let connection = NWConnection(host: host, port: p, using: .tcp)
        var responded = false
        
        let timeoutWork = DispatchWorkItem {
            if !responded {
                responded = true
                connection.stateUpdateHandler = nil
                connection.cancel()
                completion(false, false)
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
                    completion(true, true)
                }
            case .waiting(let error), .failed(let error):
                // Refusals usually arrive as .waiting; other waiting errors run to the timeout.
                let refused = error == .posix(.ECONNREFUSED)
                if case .waiting = state, !refused { break }
                if !responded {
                    responded = true
                    timeoutWork.cancel()
                    connection.stateUpdateHandler = nil
                    connection.cancel()
                    completion(false, refused)
                }
            default:
                break
            }
        }
        
        connection.start(queue: queue)
    }

    /// Reads what the service volunteers (SSH, FTP, SMTP…) or, for web ports, the HEAD response's Server line.
    private func grabBanner(ip: String, port: Int, timeout: TimeInterval = 1.0, completion: @escaping (String?) -> Void) {
        guard let value = UInt16(exactly: port), let endpointPort = NWEndpoint.Port(rawValue: value) else {
            completion(nil)
            return
        }
        let isHTTP = KnownPorts.httpPorts.contains(port) && !KnownPorts.tlsPorts.contains(port)
        let connection = NWConnection(host: NWEndpoint.Host(ip), port: endpointPort, using: .tcp)
        var finished = false
        let finish: (String?) -> Void = { banner in
            guard !finished else { return }
            finished = true
            connection.stateUpdateHandler = nil
            connection.cancel()
            completion(banner)
        }
        queue.asyncAfter(deadline: .now() + timeout) { finish(nil) }
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                if isHTTP {
                    let request = "HEAD / HTTP/1.0\r\nHost: \(ip)\r\nConnection: close\r\n\r\n"
                    connection.send(content: Data(request.utf8), completion: .contentProcessed { _ in })
                }
                connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { data, _, _, _ in
                    finish(data.flatMap { PortScannerService.sanitizeBanner($0, isHTTP: isHTTP) })
                }
            case .failed, .waiting:
                finish(nil)
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    /// One printable line, at most 120 characters. HTTP responses report their Server header.
    static func sanitizeBanner(_ data: Data, isHTTP: Bool) -> String? {
        let text = String(decoding: data.prefix(1024), as: UTF8.self)
        let lines = text.components(separatedBy: CharacterSet.newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        let line: String?
        if isHTTP {
            line = lines.first { $0.lowercased().hasPrefix("server:") }.map { String($0.dropFirst(7)).trimmingCharacters(in: .whitespaces) }
                ?? lines.first { $0.hasPrefix("HTTP/") }
        } else {
            line = lines.first { !$0.isEmpty }
        }
        guard let raw = line else { return nil }
        var printable = ""
        for scalar in raw.unicodeScalars where scalar.value >= 0x20 && scalar.value < 0x7F {
            printable.unicodeScalars.append(scalar)
        }
        printable = printable.trimmingCharacters(in: .whitespaces)
        return printable.isEmpty ? nil : String(printable.prefix(120))
    }
}
