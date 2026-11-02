//
//  NetworkToolsViewModel.swift
//  NetScan
//
//  ViewModel for standalone diagnostic tools: Ping, Port Scan, Wake-on-LAN, Subnet Calc.
//

import Foundation
import Combine

@MainActor
public class NetworkToolsViewModel: ObservableObject {
    // Ping Tool
    @Published public var pingTarget: String = "192.168.1.1"
    @Published public var pingResults: [PingResult] = []
    @Published public var isPinging: Bool = false
    @Published public var minRtt: Double = 0.0
    @Published public var avgRtt: Double = 0.0
    @Published public var maxRtt: Double = 0.0
    @Published public var packetLoss: Double = 0.0
    @Published public var pingPort: String = "80"
    @Published public private(set) var pingError: String?
    @Published public private(set) var probedPort: UInt16 = 80

    // Port Scanner Tool
    @Published public var portScanTarget: String = "192.168.1.1"
    @Published public var portResults: [PortScanResult] = []
    @Published public var isScanningPorts: Bool = false
    @Published public var portProgress: Double = 0.0
    @Published public var useCustomPorts: Bool = false
    @Published public var customPorts: String = "1-1024"
    @Published public private(set) var portScanError: String?
    @Published public private(set) var scannedTarget: String = ""
    @Published public private(set) var scannedPortCount = 0
    @Published public private(set) var tlsReports: [Int: TLSCertificateReport] = [:]
    @Published public private(set) var tlsChecking: Set<Int> = []
    @Published public private(set) var tlsUnavailable: Set<Int> = []

    // DNS Lookup
    @Published public var dnsQuery: String = "www.apple.com"
    @Published public private(set) var dnsResult: DNSLookupResult?
    @Published public private(set) var dnsError: String?
    @Published public private(set) var isLookingUp = false
    
    // Wake on LAN
    @Published public var wolMacAddress: String = "00:11:22:33:44:55"
    @Published public var wolStatusMessage: String = ""
    @Published public var wolSuccess: Bool? = nil
    
    // Subnet Calculator
    @Published public var calcIP: String = "192.168.1.100"
    @Published public var calcMask: String = "255.255.255.0"
    

    private let pingService = PingDiagnosticService()
    private let portScanner = PortScannerService()
    private var interfaceCancellable: AnyCancellable?
    private var lastNetworkID: String
    private var portRunID = UUID()
    private var tlsTasks: [Task<Void, Never>] = []
    private var dnsRunID = UUID()
    private var dnsTask: Task<Void, Never>?
    
    public init() {
        let iface = NetworkInterfaceService.shared.getCurrentInterface()
        lastNetworkID = iface.networkIdentifier
        if iface.isLAN && !iface.gatewayIP.isEmpty {
            self.pingTarget = iface.gatewayIP
            self.portScanTarget = iface.gatewayIP
            self.calcIP = iface.ipAddress.isEmpty ? "192.168.1.100" : iface.ipAddress
            self.calcMask = iface.subnetMask.isEmpty ? "255.255.255.0" : iface.subnetMask
        } else {
            self.pingTarget = "1.1.1.1"
            self.portScanTarget = "1.1.1.1"
        }
        
        pingService.$history
            .receive(on: DispatchQueue.main)
            .assign(to: &$pingResults)
            
        pingService.$avgRtt
            .receive(on: DispatchQueue.main)
            .assign(to: &$avgRtt)
            
        pingService.$minRtt
            .receive(on: DispatchQueue.main)
            .assign(to: &$minRtt)
            
        pingService.$maxRtt
            .receive(on: DispatchQueue.main)
            .assign(to: &$maxRtt)
            
        pingService.$packetLossPercent
            .receive(on: DispatchQueue.main)
            .assign(to: &$packetLoss)
            
        pingService.$isRunning
            .receive(on: DispatchQueue.main)
            .assign(to: &$isPinging)
        interfaceCancellable = NetworkInterfaceService.shared.$currentInterface
            .receive(on: DispatchQueue.main)
            .sink { [weak self] interface in
                guard let self = self, self.lastNetworkID != interface.networkIdentifier else { return }
                self.lastNetworkID = interface.networkIdentifier
                self.stopDiagnostics()
            }
    }
    
    public func togglePing() {
        if pingService.isRunning {
            pingService.stop()
        } else {
            guard let port = UInt16(pingPort.trimmingCharacters(in: .whitespaces)), port > 0 else {
                pingError = "Enter a TCP port between 1 and 65535."
                return
            }
            pingError = nil
            probedPort = port
            pingService.startPinging(host: pingTarget, port: port)
        }
        isPinging = pingService.isRunning
    }

    public func stopDiagnostics() {
        pingService.stop()
        portScanner.cancel()
        portRunID = UUID()
        tlsTasks.forEach { $0.cancel() }
        tlsTasks.removeAll()
        tlsChecking.removeAll()
        dnsRunID = UUID()
        dnsTask?.cancel()
        dnsTask = nil
        isLookingUp = false
        isPinging = false
        isScanningPorts = false
    }

    public func runPortScan() {
        guard !isScanningPorts else { return }
        let ports: [Int]
        if useCustomPorts {
            let parsed = KnownPorts.parsePortList(customPorts)
            if let error = parsed.error {
                portScanError = error
                return
            }
            ports = parsed.ports
        } else {
            ports = KnownPorts.defaultScanPorts
        }
        portScanError = nil
        let target = portScanTarget.trimmingCharacters(in: .whitespacesAndNewlines)
        let run = UUID()
        portRunID = run
        scannedTarget = target
        scannedPortCount = ports.count
        isScanningPorts = true
        portProgress = 0.0
        portResults.removeAll()
        tlsTasks.forEach { $0.cancel() }
        tlsTasks.removeAll()
        tlsReports = [:]
        tlsChecking = []
        tlsUnavailable = []

        portScanner.scanPorts(
            targetIP: target,
            ports: ports,
            grabBanners: true,
            onPortFound: { [weak self] res in
                guard self?.portRunID == run else { return }
                self?.portResults.append(res)
            },
            onProgress: { [weak self] p in
                guard self?.portRunID == run else { return }
                self?.portProgress = p
            },
            onCompletion: { [weak self] list in
                guard let self = self, self.portRunID == run else { return }
                self.isScanningPorts = false
                self.portProgress = 1.0
                self.portResults = list
                self.checkCertificates(on: list.filter { KnownPorts.tlsPorts.contains($0.port) }.map(\.port), target: target, run: run)
            }
        )
    }

    private func checkCertificates(on ports: [Int], target: String, run: UUID) {
        tlsChecking = Set(ports)
        for port in ports {
            tlsTasks.append(Task { [weak self] in
                let report = await TLSInspector.inspect(host: target, port: port)
                guard let self = self, self.portRunID == run else { return }
                self.tlsChecking.remove(port)
                if let report = report { self.tlsReports[port] = report } else { self.tlsUnavailable.insert(port) }
            })
        }
    }

    public func adminURL(for port: Int) -> URL? {
        KnownPorts.adminURL(host: scannedTarget, port: port)
    }

    public func runDNSLookup() {
        let query = dnsQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        dnsTask?.cancel()
        let run = UUID()
        dnsRunID = run
        isLookingUp = true
        dnsResult = nil
        dnsError = nil
        dnsTask = Task { [weak self] in
            let result = await DNSLookupService.resolve(query, timeout: 5)
            guard let self = self, self.dnsRunID == run else { return }
            self.isLookingUp = false
            self.dnsTask = nil
            if let result = result {
                self.dnsResult = result
            } else {
                if query.contains(":") {
                    self.dnsError = "Reverse lookup supports IPv4 addresses only."
                } else if DNSLookupService.isIPAddress(query) {
                    self.dnsError = "\(query) has no reverse DNS (PTR) name, or the resolver did not answer within 5 seconds."
                } else {
                    self.dnsError = "\(query) could not be resolved within 5 seconds."
                }
            }
        }
    }
    
    public func sendWakeOnLAN() {
        let broadcast = NetworkInterfaceService.shared.getCurrentInterface().broadcastIP
        let interface = NetworkInterfaceService.shared.getCurrentInterface()
        guard interface.isLAN, !broadcast.isEmpty else {
            wolSuccess = false
            wolStatusMessage = "Connect to a Wi-Fi or Ethernet LAN before sending Wake-on-LAN."
            return
        }
        WakeOnLANService.shared.sendWakePacket(macAddress: wolMacAddress, broadcastIP: broadcast,
                                             interfaceName: interface.interfaceName) { [weak self] success, msg in
            DispatchQueue.main.async {
                self?.wolSuccess = success
                self?.wolStatusMessage = msg
            }
        }
    }
}
