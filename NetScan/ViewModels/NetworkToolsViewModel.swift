//
//  NetworkToolsViewModel.swift
//  NetScan
//
//  ViewModel for standalone diagnostic tools: Ping, Port Scan, Wake-on-LAN, Subnet Calc.
//

import Foundation
import Combine

public class NetworkToolsViewModel: ObservableObject {
    // Ping Tool
    @Published public var pingTarget: String = "192.168.1.1"
    @Published public var pingResults: [PingResult] = []
    @Published public var isPinging: Bool = false
    @Published public var minRtt: Double = 0.0
    @Published public var avgRtt: Double = 0.0
    @Published public var maxRtt: Double = 0.0
    @Published public var packetLoss: Double = 0.0
    
    // Port Scanner Tool
    @Published public var portScanTarget: String = "192.168.1.1"
    @Published public var portResults: [PortScanResult] = []
    @Published public var isScanningPorts: Bool = false
    @Published public var portProgress: Double = 0.0
    
    // Wake on LAN
    @Published public var wolMacAddress: String = "00:11:22:33:44:55"
    @Published public var wolStatusMessage: String = ""
    @Published public var wolSuccess: Bool? = nil
    
    // Subnet Calculator
    @Published public var calcIP: String = "192.168.1.100"
    @Published public var calcMask: String = "255.255.255.0"
    
    private var cancellables = Set<AnyCancellable>()
    
    public init() {
        let iface = NetworkInterfaceService.shared.getCurrentInterface()
        if iface.isLAN && !iface.gatewayIP.isEmpty {
            self.pingTarget = iface.gatewayIP
            self.portScanTarget = iface.gatewayIP
            self.calcIP = iface.ipAddress.isEmpty ? "192.168.1.100" : iface.ipAddress
            self.calcMask = iface.subnetMask.isEmpty ? "255.255.255.0" : iface.subnetMask
        } else {
            self.pingTarget = "1.1.1.1"
            self.portScanTarget = "1.1.1.1"
        }
        
        PingDiagnosticService.shared.$history
            .receive(on: DispatchQueue.main)
            .assign(to: \.pingResults, on: self)
            .store(in: &cancellables)
            
        PingDiagnosticService.shared.$avgRtt
            .receive(on: DispatchQueue.main)
            .assign(to: \.avgRtt, on: self)
            .store(in: &cancellables)
            
        PingDiagnosticService.shared.$minRtt
            .receive(on: DispatchQueue.main)
            .assign(to: \.minRtt, on: self)
            .store(in: &cancellables)
            
        PingDiagnosticService.shared.$maxRtt
            .receive(on: DispatchQueue.main)
            .assign(to: \.maxRtt, on: self)
            .store(in: &cancellables)
            
        PingDiagnosticService.shared.$packetLossPercent
            .receive(on: DispatchQueue.main)
            .assign(to: \.packetLoss, on: self)
            .store(in: &cancellables)
            
        PingDiagnosticService.shared.$isRunning
            .receive(on: DispatchQueue.main)
            .assign(to: \.isPinging, on: self)
            .store(in: &cancellables)
    }
    
    public func togglePing() {
        if isPinging {
            PingDiagnosticService.shared.stop()
        } else {
            PingDiagnosticService.shared.startPinging(host: pingTarget)
        }
    }
    
    public func runPortScan() {
        guard !isScanningPorts else { return }
        isScanningPorts = true
        portProgress = 0.0
        portResults.removeAll()
        
        PortScannerService.shared.scanPorts(
            targetIP: portScanTarget,
            onPortFound: { [weak self] res in
                self?.portResults.append(res)
            },
            onProgress: { [weak self] p in
                self?.portProgress = p
            },
            onCompletion: { [weak self] list in
                self?.isScanningPorts = false
                self?.portProgress = 1.0
                self?.portResults = list
            }
        )
    }
    
    public func sendWakeOnLAN() {
        let broadcast = NetworkInterfaceService.shared.getCurrentInterface().broadcastIP
        let targetBroadcast = broadcast.isEmpty ? "255.255.255.255" : broadcast
        WakeOnLANService.shared.sendWakePacket(macAddress: wolMacAddress, broadcastIP: targetBroadcast) { [weak self] success, msg in
            DispatchQueue.main.async {
                self?.wolSuccess = success
                self?.wolStatusMessage = msg
            }
        }
    }
}
