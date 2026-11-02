//
//  NewDeviceNotifier.swift
//  NetScan
//
//  Local notifications for watch mode when an unrecognized device joins the network.
//

import Foundation
import UserNotifications

public protocol NewDeviceNotifying: AnyObject {
    func requestAuthorization(completion: @escaping (Bool) -> Void)
    func notify(newDevices: [NetworkDevice])
}

public final class NewDeviceNotifier: NewDeviceNotifying {
    public static let shared = NewDeviceNotifier()

    public init() {}

    public func requestAuthorization(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    public func notify(newDevices: [NetworkDevice]) {
        guard let message = Self.message(for: newDevices) else { return }
        let content = UNMutableNotificationContent()
        content.title = message.title
        content.body = message.body
        content.sound = .default
        content.threadIdentifier = "new-devices"
        let request = UNNotificationRequest(identifier: "new-devices-\(UUID().uuidString)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// Lock-screen text names at most two devices by hostname or manufacturer estimate, never by address.
    public static func message(for devices: [NetworkDevice]) -> (title: String, body: String)? {
        guard !devices.isEmpty else { return nil }
        let title = devices.count == 1 ? "New device on your network" : "\(devices.count) new devices on your network"
        let names = devices.prefix(2).map { device -> String in
            device.hasResolvedHostname ? device.hostname : "\(device.deviceType.rawValue) (\(device.vendor))"
        }
        let more = devices.count > 2 ? " and \(devices.count - 2) more" : ""
        return (title, names.joined(separator: ", ") + more + ". Open NetScan to review and label it.")
    }
}
