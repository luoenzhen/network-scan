//
//  NetworkDevice.swift
//  NetScan
//
//  Represents a discovered device on the local network with live traffic stats.
//

import Foundation

public enum DeviceType: String, Codable, CaseIterable {
    case router = "Router / Gateway"
    case phone = "Smartphone"
    case tablet = "Tablet"
    case computer = "Computer"
    case smartHome = "Smart Home / IoT"
    case printer = "Printer"
    case gaming = "Gaming Console"
    case tv = "Smart TV / Streaming"
    case unknown = "Network Device"
    
    public var iconName: String {
        switch self {
        case .router: return "wifi.router"
        case .phone: return "iphone"
        case .tablet: return "ipad"
        case .computer: return "laptopcomputer"
        case .smartHome: return "homekit"
        case .printer: return "printer"
        case .gaming: return "gamecontroller"
        case .tv: return "tv"
        case .unknown: return "network"
        }
    }
}

public struct NetworkDevice: Identifiable, Codable, Equatable {
    public var id: UUID
    public var ipAddress: String
    public var macAddress: String
    public var hostname: String
    public var vendor: String
    public var deviceType: DeviceType
    public var isOnline: Bool
    
    // Live traffic metrics in Kilobytes per second
    public var uploadSpeedKbps: Double
    public var downloadSpeedKbps: Double
    
    // Cumulative metrics
    public var totalBytesSent: UInt64
    public var totalBytesReceived: UInt64
    
    // Diagnostics
    public var latencyMs: Double
    public var openPorts: [Int]
    public var services: [String]
    
    // Timestamps
    public var firstDiscovered: Date
    public var lastSeen: Date
    public var isLocalDevice: Bool
    public var isGateway: Bool
    public var serviceCheckState: ServiceCheckState
    public var annotation = DeviceAnnotation()
    public var inventoryID: UUID?
    public var savedMatch: SavedDeviceMatch = .none
    public var evidence: [IdentityEvidence] = []
    public var assessedPorts: [Int] = []
    
    public init(
        id: UUID = UUID(),
        ipAddress: String,
        macAddress: String = "Unknown",
        hostname: String = "",
        vendor: String = "Generic Device",
        deviceType: DeviceType = .unknown,
        isOnline: Bool = true,
        uploadSpeedKbps: Double = 0.0,
        downloadSpeedKbps: Double = 0.0,
        totalBytesSent: UInt64 = 0,
        totalBytesReceived: UInt64 = 0,
        latencyMs: Double = 0.0,
        openPorts: [Int] = [],
        services: [String] = [],
        firstDiscovered: Date = Date(),
        lastSeen: Date = Date(),
        isLocalDevice: Bool = false,
        isGateway: Bool = false,
        serviceCheckState: ServiceCheckState = .notChecked
    ) {
        self.id = id
        self.ipAddress = ipAddress
        self.macAddress = macAddress
        self.hostname = hostname.isEmpty ? ipAddress : hostname
        self.vendor = vendor
        self.deviceType = deviceType
        self.isOnline = isOnline
        self.uploadSpeedKbps = uploadSpeedKbps
        self.downloadSpeedKbps = downloadSpeedKbps
        self.totalBytesSent = totalBytesSent
        self.totalBytesReceived = totalBytesReceived
        self.latencyMs = latencyMs
        self.openPorts = openPorts
        self.services = services
        self.firstDiscovered = firstDiscovered
        self.lastSeen = lastSeen
        self.isLocalDevice = isLocalDevice
        self.isGateway = isGateway
        self.serviceCheckState = serviceCheckState
    }
    
    public var displayName: String {
        if !annotation.name.isEmpty { return annotation.name }
        if hasResolvedHostname {
            return hostname
        }
        if isGateway {
            return "Gateway (\(vendor))"
        }
        if isLocalDevice {
            return "This iPhone (\(vendor))"
        }
        return "\(vendor) (\(ipAddress))"
    }
    
    public var formattedUpload: String {
        guard isLocalDevice else { return "Unavailable" }
        return String(format: "%.1f KB/s", uploadSpeedKbps)
    }

    public var hasKnownMACAddress: Bool {
        let clean = macAddress.replacingOccurrences(of: ":", with: "").replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: ".", with: "")
        return clean.count == 12 && clean.utf8.allSatisfy { (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }
    }

    public var hasResolvedHostname: Bool {
        let name = hostname.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty && name != ipAddress && name.lowercased() != "unknown"
    }

    public var needsIdentityUpdate: Bool {
        guard !isLocalDevice else { return false }
        return !hasResolvedHostname || ["", "unknown", "network device", "generic device"].contains(vendor.lowercased())
    }

    public var identityAddressLabel: String { hasKnownMACAddress ? "MAC:" : "Host:" }
    public var identityAddressValue: String { hasKnownMACAddress ? macAddress : (hasResolvedHostname ? hostname : "Unresolved") }

    public var securityFindings: [DeviceSecurityFinding] {
        var findings: [DeviceSecurityFinding] = []
        if evidence.contains(where: { $0.source == "HTTP authentication" }) {
            findings.append(DeviceSecurityFinding(id: "basic-auth", title: "Unencrypted web login observed", detail: "The web service offered HTTP Basic authentication over HTTP. Credentials sent through this interface lack transport encryption.", requiresReview: true))
        }
        if !isLocalDevice && !hasResolvedHostname && ["", "unknown", "network device", "generic device"].contains(vendor.lowercased()) {
            findings.append(DeviceSecurityFinding(id: "identity", title: "Identity unresolved", detail: "The device has not advertised a recognizable name or manufacturer. Missing MAC addresses are normal on iOS.", requiresReview: false))
        }
        if openPorts.contains(21) {
            findings.append(DeviceSecurityFinding(id: "ftp", title: "FTP-associated port 21 reachable", detail: "TCP 21 is commonly used for FTP. If FTP is running, require TLS to protect credentials or disable it if unneeded.", requiresReview: true))
        }
        if openPorts.contains(23) {
            findings.append(DeviceSecurityFinding(id: "telnet", title: "Telnet-associated port 23 reachable", detail: "TCP 23 is commonly used for Telnet, which transmits credentials and commands without encryption. Confirm the service and prefer SSH if applicable.", requiresReview: true))
        }
        if openPorts.contains(139) || openPorts.contains(445) {
            findings.append(DeviceSecurityFinding(id: "smb", title: "File-sharing ports reachable", detail: "TCP 139/445 are commonly used for SMB/NetBIOS. Confirm the service, restrict sharing to intended users, and keep the device updated.", requiresReview: true))
        }
        if openPorts.contains(3389) {
            findings.append(DeviceSecurityFinding(id: "rdp", title: "Remote-desktop port 3389 reachable", detail: "TCP 3389 is commonly used for RDP. Confirm the service and protect intended remote access with strong authentication.", requiresReview: true))
        }
        return findings
    }
    
    public var formattedDownload: String {
        guard isLocalDevice else { return "Unavailable" }
        return String(format: "%.1f KB/s", downloadSpeedKbps)
    }
    
    public var formattedTotalTransfer: String {
        guard isLocalDevice else { return "Unavailable" }
        let total = Double(totalBytesSent) + Double(totalBytesReceived)
        if total >= 1_000_000_000 {
            return String(format: "%.2f GB", total / 1_000_000_000)
        } else if total >= 1_000_000 {
            return String(format: "%.2f MB", total / 1_000_000)
        } else if total >= 1_000 {
            return String(format: "%.1f KB", total / 1_000)
        } else {
            return "\(Int(total)) B"
        }
    }
}

public enum ServiceCheckState: String, Codable {
    case notChecked = "Not checked"
    case checking = "Checking selected services"
    case checked = "Selected services checked"
}

public enum DeviceUpdateKind: Equatable {
    case identity
    case ports
    case annotation
}

public struct DeviceAnnotation: Codable, Equatable {
    public var name = ""
    public var location = ""
    public var notes = ""
    public var recognized = false
    public init() {}
    public var isEmpty: Bool { name.isEmpty && location.isEmpty && notes.isEmpty && !recognized }
}

public enum SavedDeviceMatch: String, Codable {
    case none = "No saved identity"
    case current = "Labeled by you this scan"
    case mac = "Saved label: MAC match"
    case hostname = "Saved label: hostname match—verify device"
    case address = "Saved address label—verify device"
}

public struct IdentityEvidence: Codable, Equatable, Identifiable {
    public var source: String
    public var observation: String
    public var date: Date
    public var id: String { source + ":" + observation }
    public init(source: String, observation: String, date: Date = Date()) {
        self.source = source
        self.observation = String(observation.prefix(256))
        self.date = date
    }
}

public struct DeviceIdentityResult {
    public var vendor: String
    public var deviceType: DeviceType
    public var resolvedHostname: String?
    public var evidence: [IdentityEvidence]
}

public struct DeviceSecurityFinding: Identifiable, Equatable {
    public let id: String
    public let title: String
    public let detail: String
    public let requiresReview: Bool
    public var recommendedAction: String {
        switch id {
        case "ftp": return "Confirm whether FTP is needed. Prefer SFTP or properly configured FTPS; otherwise disable the service."
        case "telnet": return "Disable Telnet if the device supports it. Otherwise restrict access using your router or an isolated IoT network."
        case "smb": return "Review sharing permissions, require authentication, and restrict access to intended devices."
        case "rdp": return "Allow remote desktop only where needed; use strong authentication and avoid internet port forwarding."
        case "basic-auth": return "Prefer HTTPS if supported. Use a unique device password and restrict who can reach this interface."
        default: return "Compare the device with your router's client list and appliance labels before assigning it a name."
        }
    }
}
