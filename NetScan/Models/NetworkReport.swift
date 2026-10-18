import Foundation

public enum NetworkReport {
    public static func text(devices: [NetworkDevice], history: [ScanSnapshot], redacted: Bool = true, date: Date = Date()) -> String {
        func plain(_ text: String) -> String {
            String(text.unicodeScalars.map { CharacterSet.controlCharacters.contains($0) ? " " : String($0) }.joined().prefix(2000))
        }
        let formatter = ISO8601DateFormatter()
        var lines = ["NetScan network report", "Generated: \(formatter.string(from: date))",
                     redacted ? "Privacy: redacted. Device labels, notes, locations, addresses, hostnames, network identifiers and raw evidence are omitted." : "Privacy: includes device names, notes, addresses and identification evidence. Review before sharing.",
                     "Devices observed: \(devices.count)",
                     "Findings describe observable risks, not proof of malicious activity. Unanswered probes are inconclusive. No other devices' traffic was captured."]
        for (index, device) in devices.enumerated() {
            lines += ["", "Device \(index + 1)", "Category: \(device.deviceType.rawValue)",
                      "Service checks: \(device.serviceCheckState.rawValue)",
                      "Reachable TCP ports: \(device.openPorts.sorted().map(String.init).joined(separator: ", "))",
                      "Ports with a definite response: \(device.assessedPorts.sorted().map(String.init).joined(separator: ", "))"]
            if !redacted {
                lines += ["Name: \(plain(device.displayName))", "IP: \(plain(device.ipAddress))",
                          "MAC: \(plain(device.macAddress))", "Hostname: \(plain(device.hostname))",
                          "Manufacturer estimate: \(plain(device.vendor))", "Location: \(plain(device.annotation.location))",
                          "Notes: \(plain(device.annotation.notes))", "Saved association: \(device.savedMatch.rawValue)",
                          "Recognized by owner: \(device.annotation.recognized ? "recorded assertion; check association" : "not recorded")"]
                lines += device.evidence.map { "Evidence [\(formatter.string(from: $0.date))] \(plain($0.source)): \(plain($0.observation))" }
            }
            for finding in device.securityFindings {
                lines += ["\(finding.requiresReview ? "Review" : "Information"): \(finding.title)", finding.detail, "Suggested action: \(finding.recommendedAction)"]
            }
        }
        lines += ["", "Scan history (latest \(history.count))"]
        for scan in history {
            lines.append("\(formatter.string(from: scan.date)): \(scan.devices.count) devices; identity checks: \(scan.identityCoverage.rawValue); service checks: \(scan.serviceCoverage.rawValue)")
            if !redacted { lines.append("Network profile: \(plain(scan.network))") }
        }
        return lines.joined(separator: "\n")
    }
}
