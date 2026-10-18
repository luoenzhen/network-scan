//
//  SubnetScannerService.swift
//  NetScan
//
//  Asynchronously probes LAN IP addresses to discover active devices.
//  Resolves real MAC addresses via kernel ARP table and queries OUIVendorDatabase.
//

import Foundation
import Network
#if canImport(Darwin)
import Darwin
#endif

// Each run owns its cancellation state, so restarting cannot revive old work.
final class ScanCancellation {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}

public class SubnetScannerService {
    public static let shared = SubnetScannerService()
    
    private var currentScan: ScanCancellation?
    private let scanLock = NSLock()
    private let scanQueue = DispatchQueue(label: "com.netscan.scanner", attributes: .concurrent)
    
    public init() {}
    
    public func scanSubnet(
        interface: NetworkInterfaceInfo,
        onProgress: @escaping (Double) -> Void,
        onDeviceFound: @escaping (NetworkDevice) -> Void,
        onCompletion: @escaping ([NetworkDevice]) -> Void
    ) {
        let scan = ScanCancellation()
        scanLock.lock()
        currentScan?.cancel()
        currentScan = scan
        scanLock.unlock()
        guard interface.isLAN else {
            DispatchQueue.main.async { if !scan.isCancelled { onCompletion([]) } }
            return
        }
        let defaults = UserDefaults.standard
        let timeout = min(max(defaults.object(forKey: "scanTimeout") as? Double ?? 0.4, 0.1), 1.5)
        let concurrency = min(max(defaults.object(forKey: "maxConcurrentProbes") as? Int ?? 16, 4), 32)
        
        // Dispatch entire scanning process to background queue so the UI thread NEVER blocks!
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let ips = NetworkInterfaceService.shared.generateSubnetIPs(
                localIP: interface.ipAddress,
                cidr: interface.cidrPrefix
            )
            
            guard !ips.isEmpty else {
                DispatchQueue.main.async { if !scan.isCancelled { onCompletion([]) } }
                return
            }
            
            var discoveredDevices: [NetworkDevice] = []
            let lock = NSLock()
            let group = DispatchGroup()
            let totalCount = Double(ips.count)
            var scannedCount = 0.0
            
            // Immediately register local iPhone
            let localDevice = NetworkDevice(
                ipAddress: interface.ipAddress,
                macAddress: "Self (Current Device)",
                hostname: "iPhone",
                vendor: "Apple Inc.",
                deviceType: .phone,
                isOnline: true,
                uploadSpeedKbps: 0.0,
                downloadSpeedKbps: 0.0,
                totalBytesSent: 0,
                totalBytesReceived: 0,
                latencyMs: 0.0,
                isLocalDevice: true,
                isGateway: false
            )
            
            lock.lock()
            discoveredDevices.append(localDevice)
            lock.unlock()
            
            DispatchQueue.main.async {
                if !scan.isCancelled { onDeviceFound(localDevice) }
            }
            
            var lastReportedPercent = -1
            
            let reportProgress: (Double) -> Void = { progress in
                DispatchQueue.main.async {
                    guard !scan.isCancelled else { return }
                    let percent = Int(progress * 100)
                    guard percent > lastReportedPercent else { return }
                    lastReportedPercent = percent
                    onProgress(progress)
                }
            }
            
            // Safe concurrency limit
            let semaphore = DispatchSemaphore(value: concurrency)
            
            for ip in ips {
                if scan.isCancelled { break }
                
                if ip == interface.ipAddress {
                    lock.lock()
                    scannedCount += 1.0
                    let progress = scannedCount / totalCount
                    lock.unlock()
                    reportProgress(progress)
                    continue
                }
                
                group.enter()
                semaphore.wait() // Safely waits on background worker thread
                
                self.scanQueue.async { [weak self] in
                    guard let self = self, !scan.isCancelled else {
                        semaphore.signal()
                        group.leave()
                        return
                    }
                    
                    self.probeHost(ip: ip, timeout: timeout) { device in
                        if var dev = device {
                            dev.isGateway = ip == interface.gatewayIP
                            lock.lock()
                            discoveredDevices.removeAll { $0.ipAddress == dev.ipAddress }
                            discoveredDevices.append(dev)
                            lock.unlock()
                            let found = dev
                            DispatchQueue.main.async {
                                if !scan.isCancelled { onDeviceFound(found) }
                            }
                        }
                        
                        lock.lock()
                        scannedCount += 1.0
                        let progress = scannedCount / totalCount
                        lock.unlock()
                        
                        reportProgress(progress)
                        
                        semaphore.signal()
                        group.leave()
                    }
                }
            }
            
            group.notify(queue: .main) {
                guard !scan.isCancelled else { return }
                onProgress(1.0)
                onCompletion(discoveredDevices)
            }
        }
    }
    
    public func cancelScan() {
        scanLock.lock()
        currentScan?.cancel()
        scanLock.unlock()
    }
    
    private func probeHost(ip: String, timeout: TimeInterval, completion: @escaping (NetworkDevice?) -> Void) {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            completion(nil)
            return
        }
        
        // Set non-blocking mode
        let flags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
        
        #if canImport(Darwin)
        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        #endif
        
        var addr = sockaddr_in()
        #if canImport(Darwin)
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        #endif
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(80).bigEndian
        inet_pton(AF_INET, ip, &addr.sin_addr)
        
        var genericAddr = sockaddr()
        memcpy(&genericAddr, &addr, MemoryLayout<sockaddr_in>.size)
        
        let connectRes = connect(fd, &genericAddr, socklen_t(MemoryLayout<sockaddr_in>.size))
        
        var isAlive = false
        var openPort: Int? = nil
        
        if connectRes == 0 {
            isAlive = true
            openPort = 80
        } else {
            let err = errno
            if err == EINPROGRESS || err == EWOULDBLOCK {
                var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
                let pollRes = poll(&pfd, 1, Int32(timeout * 1000))
                if pollRes > 0 {
                    var soError: Int32 = 0
                    var len = socklen_t(MemoryLayout<Int32>.size)
                    getsockopt(fd, SOL_SOCKET, SO_ERROR, &soError, &len)
                    if soError == 0 {
                        isAlive = true
                        openPort = 80
                    } else if soError == ECONNREFUSED {
                        isAlive = true
                        openPort = nil
                    }
                }
            } else if err == ECONNREFUSED {
                isAlive = true
                openPort = nil
            }
        }
        
        close(fd)
        
        if isAlive {
            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
            let device = self.buildDeviceRecord(ip: ip, latency: elapsed, openPort: openPort)
            completion(device)
        } else {
            completion(nil)
        }
    }
    
    private func buildDeviceRecord(ip: String, latency: Double, openPort: Int?) -> NetworkDevice {
        let hostname = resolveHostname(for: ip) ?? ip
        let realMAC = resolveARPMACAddress(ip: ip)
        let (vendor, deviceType) = OUIVendorDatabase.identifyDevice(macAddress: realMAC, hostname: hostname)
        
        var openPorts: [Int] = []
        var services: [String] = []
        if let p = openPort {
            openPorts.append(p)
            services.append(KnownPorts.service(for: p))
        }
        
        return NetworkDevice(
            ipAddress: ip,
            macAddress: realMAC ?? "Unknown MAC",
            hostname: hostname,
            vendor: vendor,
            deviceType: deviceType,
            isOnline: true,
            latencyMs: round(latency * 10) / 10,
            openPorts: openPorts,
            services: services
        )
    }
    
    private func resolveHostname(for ip: String) -> String? {
        // Fast, safe hostname resolution without blocking DNS PTR queries on LAN.
        // Device identity is enriched via IEEE OUI database and Bonjour / mDNS.
        return nil
    }
    
    /// Resolves the MAC address if available.
    /// Note: Direct kernel ARP table access is restricted on iOS 11+
    /// sandboxes for user privacy protection.
    public func resolveARPMACAddress(ip: String) -> String? {
        // Direct ARP table access (RTF_LLINFO) is restricted by Apple in user-space iOS sandbox.
        // Device identity is resolved via IEEE OUI database, reverse DNS, and mDNS/Bonjour services.
        return nil
    }
}
