//
//  AppDelegate.swift
//  NetScan
//
//  App lifecycle, background network tasks, and notification handling.
//

import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil
    ) -> Bool {
        // Prevent kernel SIGPIPE signals from terminating the app when sockets close or reset
        signal(SIGPIPE, SIG_IGN)
        
        // Initialize background network monitoring service
        TrafficMonitorService.shared.startMonitoring()
        PacketInspectorService.shared.startCapture()
        
        return true
    }
    
    func applicationDidEnterBackground(_ application: UIApplication) {
        // Gracefully pause intensive polling when entering background
        SubnetScannerService.shared.cancelScan()
    }
    
    func applicationWillEnterForeground(_ application: UIApplication) {
        // Resume network services
        TrafficMonitorService.shared.startMonitoring()
    }
}
