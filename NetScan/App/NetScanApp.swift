//
//  NetScanApp.swift
//  NetScan
//
//  Application entry point.
//

import SwiftUI

@main
struct NetScanApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            MainTabView()
        }
    }
}
