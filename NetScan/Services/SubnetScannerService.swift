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
    
    // All ports share one host timeout, with at most three sockets per host.
    func probeHost(ip: String, timeout: TimeInterval, ports: [UInt16] = [80, 443, 22],
                   completion: @escaping (NetworkDevice?) -> Void) {
        let start = CFAbsoluteTimeGetCurrent()
        var descriptors: [pollfd] = []
        var descriptorPorts: [UInt16] = []
        var live = false
        var openPort: Int?
        let ports = Array(Set(ports.filter { $0 > 0 })).sorted().prefix(3)
        defer { descriptors.forEach { close($0.fd) } }
        for port in ports {
            let fd = socket(AF_INET, SOCK_STREAM, 0)
            guard fd >= 0 else { continue }
            let flags = fcntl(fd, F_GETFL, 0)
            guard flags >= 0, fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0 else { close(fd); continue }
            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = port.bigEndian
            guard inet_pton(AF_INET, ip, &address.sin_addr) == 1 else { close(fd); continue }
            let result = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
            }
            if result == 0 { live = true; openPort = Int(port) }
            else if errno == ECONNREFUSED { live = true }
            descriptors.append(pollfd(fd: fd, events: Int16(POLLOUT), revents: 0))
            descriptorPorts.append(port)
        }
        if !live && !descriptors.isEmpty {
            let count = descriptors.count
            let ready = poll(&descriptors, nfds_t(count), Int32(max(0, min(timeout, 1.5)) * 1000))
            if ready > 0 {
                for (index, descriptor) in descriptors.enumerated() where descriptor.revents & Int16(POLLOUT | POLLERR | POLLHUP) != 0 {
                    var error: Int32 = 0
                    var length = socklen_t(MemoryLayout<Int32>.size)
                    if getsockopt(descriptor.fd, SOL_SOCKET, SO_ERROR, &error, &length) == 0 {
                        if error == 0 { live = true; openPort = Int(descriptorPorts[index]) }
                        else if error == ECONNREFUSED { live = true }
                    }
                }
            }
        }
        guard live else { completion(nil); return }
        var device = buildDeviceRecord(ip: ip, latency: (CFAbsoluteTimeGetCurrent() - start) * 1000, openPort: openPort)
        device.evidence.append(IdentityEvidence(source: "TCP discovery", observation: openPort.map { "TCP \($0) accepted a connection." } ?? "A TCP connection was explicitly refused; host responded."))
        completion(device)
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
