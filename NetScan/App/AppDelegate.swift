//
//  AppDelegate.swift
//  NetScan
//
//  App lifecycle, background network tasks, and notification handling.
//

import UIKit
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil
    ) -> Bool {
        // Prevent kernel SIGPIPE signals from terminating the app when sockets close or reset
        signal(SIGPIPE, SIG_IGN)
        // Watch mode runs only in the foreground, so its alerts must show while the app is open.
        UNUserNotificationCenter.current().delegate = self
        #if DEBUG
        if ProcessInfo.processInfo.environment["NETSCAN_UI_TESTING"] == "1" { return true }
        #endif
        
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

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }
}
