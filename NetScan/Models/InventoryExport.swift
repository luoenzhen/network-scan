import Foundation

public enum ExportFormat: String, CaseIterable, Identifiable {
    case text = "Text"
    case csv = "CSV"
    case json = "JSON"

    public var id: String { rawValue }
}

/// Spreadsheet and machine-readable device exports. Redaction omits the same fields as the text report.
public enum InventoryExport {
    public static func render(_ format: ExportFormat, devices: [NetworkDevice], history: [ScanSnapshot],
                              redacted: Bool = true, date: Date = Date()) -> String {
        switch format {
        case .text: return NetworkReport.text(devices: devices, history: history, redacted: redacted, date: date)
        case .csv: return csv(devices: devices, redacted: redacted)
        case .json: return json(devices: devices, history: history, redacted: redacted, date: date)
        }
    }

    public static func csv(devices: [NetworkDevice], redacted: Bool = true) -> String {
        var header = ["device", "category", "service_checks", "reachable_tcp_ports", "definite_response_ports", "findings"]
        if !redacted {
            header += ["name", "ip", "mac", "hostname", "manufacturer_estimate", "location", "notes", "saved_association", "recognized_by_owner"]
        }
        var rows = [header]
        for (index, device) in devices.enumerated() {
            var row = [String(index + 1), device.deviceType.rawValue, device.serviceCheckState.rawValue,
                       device.openPorts.sorted().map(String.init).joined(separator: " "),
                       device.assessedPorts.sorted().map(String.init).joined(separator: " "),
                       device.securityFindings.map(\.title).joined(separator: "; ")]
            if !redacted {
                row += [device.displayName, device.ipAddress, device.hasKnownMACAddress ? device.macAddress : "",
                        device.hasResolvedHostname ? device.hostname : "", device.vendor, device.annotation.location,
                        device.annotation.notes, device.savedMatch.rawValue, device.annotation.recognized ? "yes" : "no"]
            }
            rows.append(row)
        }
        return rows.map { $0.map(csvField).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }

    /// Quotes when needed and neutralizes leading formula characters so spreadsheets show text, not formulas.
    static func csvField(_ value: String) -> String {
        var text = String(value.prefix(2000))
        if let first = text.first, "=+-@\t\r".contains(first) { text = "'" + text }
        // isNewline also covers "\r\n", which Swift treats as one Character.
        guard text.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline }) else { return text }
        return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private struct ExportDocument: Encodable {
        var generated: Date
        var redacted: Bool
        var note: String
        var devices: [ExportDevice]
        var history: [ExportScan]
    }

    private struct ExportDevice: Encodable {
        var category: String
        var serviceChecks: String
        var reachableTCPPorts: [Int]
        var definiteResponsePorts: [Int]
        var findings: [String]
        var name: String?
        var ip: String?
        var mac: String?
        var hostname: String?
        var manufacturerEstimate: String?
        var location: String?
        var notes: String?
        var savedAssociation: String?
        var recognizedByOwner: Bool?
        var evidence: [IdentityEvidence]?
    }

    private struct ExportScan: Encodable {
        var date: Date
        var devices: Int
        var identityChecks: String
        var serviceChecks: String
        var network: String?
    }

    public static func json(devices: [NetworkDevice], history: [ScanSnapshot], redacted: Bool = true, date: Date = Date()) -> String {
        let document = ExportDocument(
            generated: date,
            redacted: redacted,
            note: "Findings describe observable risks, not proof of malicious activity. Unanswered probes are inconclusive.",
            devices: devices.map { device in
                var item = ExportDevice(category: device.deviceType.rawValue, serviceChecks: device.serviceCheckState.rawValue,
                                        reachableTCPPorts: device.openPorts.sorted(), definiteResponsePorts: device.assessedPorts.sorted(),
                                        findings: device.securityFindings.map(\.title))
                if !redacted {
                    item.name = device.displayName
                    item.ip = device.ipAddress
                    item.mac = device.hasKnownMACAddress ? device.macAddress : nil
                    item.hostname = device.hasResolvedHostname ? device.hostname : nil
                    item.manufacturerEstimate = device.vendor
                    item.location = device.annotation.location
                    item.notes = device.annotation.notes
                    item.savedAssociation = device.savedMatch.rawValue
                    item.recognizedByOwner = device.annotation.recognized
                    item.evidence = device.evidence
                }
                return item
            },
            history: history.map {
                ExportScan(date: $0.date, devices: $0.devices.count, identityChecks: $0.identityCoverage.rawValue,
                           serviceChecks: $0.serviceCoverage.rawValue, network: redacted ? nil : $0.network)
            })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(document) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}
