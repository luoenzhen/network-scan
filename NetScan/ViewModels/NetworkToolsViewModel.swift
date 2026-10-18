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
    

    private let pingService = PingDiagnosticService()
    private let portScanner = PortScannerService()
    private var interfaceCancellable: AnyCancellable?
    private var lastNetworkID: String
    
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
            pingService.startPinging(host: pingTarget)
        }
        isPinging = pingService.isRunning
    }

    public func stopDiagnostics() {
        pingService.stop()
        portScanner.cancel()
        isPinging = false
        isScanningPorts = false
    }
    
    public func runPortScan() {
        guard !isScanningPorts else { return }
        isScanningPorts = true
        portProgress = 0.0
        portResults.removeAll()
        
        portScanner.scanPorts(
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
