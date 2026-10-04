//
//  PortScanResult.swift
//  NetScan
//
//  Represents an open port found during diagnostic port scanning.
//

import Foundation

public struct PortScanResult: Identifiable, Codable, Equatable {
    public var id: Int { port }
    public let port: Int
    public let serviceName: String
    public let isOpen: Bool
    public let banner: String?
    
    public init(port: Int, serviceName: String, isOpen: Bool = true, banner: String? = nil) {
        self.port = port
        self.serviceName = serviceName
        self.isOpen = isOpen
        self.banner = banner
    }
}

public struct KnownPorts {
    public static let standardServiceMap: [Int: String] = [
        21: "FTP (File Transfer)",
        22: "SSH (Secure Shell)",
        23: "Telnet",
        25: "SMTP (Mail)",
        53: "DNS (Domain Name Service)",
        80: "HTTP (Web Server)",
        110: "POP3 (Mail)",
        139: "NetBIOS Session Service",
        143: "IMAP (Mail)",
        443: "HTTPS (Secure Web)",
        445: "SMB (Windows File Sharing)",
        548: "AFP (Apple Filing Protocol)",
        554: "RTSP (Streaming Video / Camera)",
        631: "IPP (CUPS Internet Printing)",
        8080: "HTTP-Proxy / Alt-Web",
        8443: "HTTPS-Alt",
        9000: "Storage / Microservice",
        3389: "RDP (Remote Desktop)",
        5000: "UPnP / AirPlay Service",
        5353: "mDNS (Bonjour Discovery)",
        7000: "AirPlay Mirroring",
        8008: "Google Cast HTTP",
        8009: "Google Cast Protobuf",
        9100: "RAW JetDirect Printer"
    ]
    
    public static func service(for port: Int) -> String {
        return standardServiceMap[port] ?? "TCP Port \(port)"
    }
}
