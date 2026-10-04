//
//  DashboardViewModel.swift
//  NetScan
//
//  State and data binding for the main network overview dashboard.
//

import Foundation
import Combine

public class DashboardViewModel: ObservableObject {
    @Published public var networkInfo: NetworkInterfaceInfo
    @Published public var uploadSpeedKbps: Double = 0.0
    @Published public var downloadSpeedKbps: Double = 0.0
    @Published public var totalDiscoveredCount: Int = 0
    @Published public var onlineDeviceCount: Int = 0
    @Published public var isScanning: Bool = false
    @Published public var scanProgress: Double = 0.0
    
    private var cancellables = Set<AnyCancellable>()
    
    public init() {
        self.networkInfo = NetworkInterfaceService.shared.getCurrentInterface()
        
        TrafficMonitorService.shared.$currentUploadKbps
            .receive(on: DispatchQueue.main)
            .assign(to: \.uploadSpeedKbps, on: self)
            .store(in: &cancellables)
            
        TrafficMonitorService.shared.$currentDownloadKbps
            .receive(on: DispatchQueue.main)
            .assign(to: \.downloadSpeedKbps, on: self)
            .store(in: &cancellables)
    }
    
    public func refreshInterface() {
        self.networkInfo = NetworkInterfaceService.shared.getCurrentInterface()
    }
}
