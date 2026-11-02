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
        9100: "RAW JetDirect Printer",
        62078: "Apple device sync (iPhone / iPad)"
    ]
    
    public static func service(for port: Int) -> String {
        return standardServiceMap[port] ?? "TCP Port \(port)"
    }

    public static let defaultScanPorts = [21, 22, 23, 25, 53, 80, 110, 139, 143, 443, 445, 548, 554, 631, 8080, 8443, 9000, 3389, 5000, 5353, 7000, 8008, 9100]
    public static let httpPorts: Set<Int> = [80, 443, 5000, 8000, 8008, 8080, 8443, 8888, 9000]
    public static let tlsPorts: Set<Int> = [443, 8443]
    public static let maxCustomPorts = 1024

    /// Parses "22, 80-90 443" into sorted unique ports. Returns an error message for invalid or oversized lists.
    public static func parsePortList(_ text: String) -> (ports: [Int], error: String?) {
        let tokens = text.split { $0 == "," || $0 == " " || $0 == "\n" || $0 == ";" }
        guard !tokens.isEmpty else { return ([], "Enter ports such as 22, 80, 8000-8100.") }
        var ports = Set<Int>()
        for token in tokens {
            let bounds = token.split(separator: "-", omittingEmptySubsequences: false)
            guard (1...2).contains(bounds.count),
                  let low = Int(bounds[0].trimmingCharacters(in: .whitespaces)),
                  let high = Int(bounds[bounds.count - 1].trimmingCharacters(in: .whitespaces)),
                  (1...65535).contains(low), (1...65535).contains(high), low <= high else {
                return ([], "\"\(token)\" is not a port or range between 1 and 65535.")
            }
            guard high - low < maxCustomPorts else { return ([], "Scan at most \(maxCustomPorts) ports at a time.") }
            ports.formUnion(low...high)
            guard ports.count <= maxCustomPorts else { return ([], "Scan at most \(maxCustomPorts) ports at a time.") }
        }
        return (ports.sorted(), nil)
    }

    /// Web address for a device's admin page on a web port, or nil for other services.
    public static func adminURL(host: String, port: Int) -> URL? {
        let host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        // IPv6 literals are left out; the tools target IPv4 LAN hosts and names.
        guard httpPorts.contains(port), !host.isEmpty,
              host.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }) else { return nil }
        var components = URLComponents()
        components.scheme = tlsPorts.contains(port) ? "https" : "http"
        components.host = host
        if port != 80 && port != 443 { components.port = port }
        components.path = "/"
        return components.url
    }
}
