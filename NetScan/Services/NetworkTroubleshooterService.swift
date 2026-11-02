//
//  NetworkTroubleshooterService.swift
//  NetScan
//
//  Ordered "is it me or the network?" checks: router, DNS, internet,
//  captive portal, public IP and a short download test.
//

import Foundation
import Network

public enum TCPReachability {
    /// Milliseconds until the host accepted or explicitly refused a TCP connection; nil when unanswered.
    public static func probe(host: String, port: UInt16, timeout: TimeInterval = 1.5) async -> Double? {
        let host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty, timeout.isFinite, let endpointPort = NWEndpoint.Port(rawValue: port), port > 0 else { return nil }
        let queue = DispatchQueue(label: "com.netscan.reachability")
        return await withCheckedContinuation { continuation in
            let connection = NWConnection(host: NWEndpoint.Host(host), port: endpointPort, using: .tcp)
            let start = CFAbsoluteTimeGetCurrent()
            var finished = false
            // Every event runs on `queue`, so completion is one-shot.
            let finish: (Bool) -> Void = { responded in
                guard !finished else { return }
                finished = true
                connection.stateUpdateHandler = nil
                connection.cancel()
                continuation.resume(returning: responded ? round((CFAbsoluteTimeGetCurrent() - start) * 10_000) / 10 : nil)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    finish(true)
                case .waiting(let error), .failed(let error):
                    // Only an explicit refusal proves that the host answered.
                    if error == .posix(.ECONNREFUSED) { finish(true) } else if case .failed = state { finish(false) }
                default:
                    break
                }
            }
            queue.asyncAfter(deadline: .now() + max(0.05, min(timeout, 10))) { finish(false) }
            connection.start(queue: queue)
        }
    }
}

public enum TroubleshootStep: String, CaseIterable, Identifiable {
    case router = "Router reachable"
    case dns = "DNS resolution"
    case internet = "Internet reachable"
    case captivePortal = "No captive portal"
    case publicIP = "Public IP address"
    case speed = "Download speed"

    public var id: String { rawValue }

    /// A step is skipped when any of these failed or were themselves skipped by a failure.
    public var dependencies: [TroubleshootStep] {
        switch self {
        case .router: return []
        case .dns, .internet: return [.router]
        case .captivePortal: return [.dns, .internet]
        case .publicIP, .speed: return [.captivePortal]
        }
    }
}

public enum TroubleshootStatus: String {
    case passed = "Passed"
    case warning = "Warning"
    case failed = "Failed"
    case skipped = "Skipped"
}

public struct TroubleshootResult: Identifiable, Equatable {
    public var step: TroubleshootStep
    public var status: TroubleshootStatus
    public var detail: String
    public var id: String { step.rawValue }

    public init(step: TroubleshootStep, status: TroubleshootStatus, detail: String) {
        self.step = step
        self.status = status
        self.detail = detail
    }
}

public enum CaptivePortalState: Equatable {
    case open
    case captive
    case unreachable
}

public struct TroubleshootChecks {
    public var router: (String) async -> Double?
    public var dns: (String) async -> DNSLookupResult?
    public var internet: () async -> Double?
    public var captivePortal: () async -> CaptivePortalState
    public var publicIP: () async -> String?
    public var downloadMbps: () async -> Double?

    public init(router: @escaping (String) async -> Double?,
                dns: @escaping (String) async -> DNSLookupResult?,
                internet: @escaping () async -> Double?,
                captivePortal: @escaping () async -> CaptivePortalState,
                publicIP: @escaping () async -> String?,
                downloadMbps: @escaping () async -> Double?) {
        self.router = router
        self.dns = dns
        self.internet = internet
        self.captivePortal = captivePortal
        self.publicIP = publicIP
        self.downloadMbps = downloadMbps
    }
}

public enum NetworkTroubleshooter {
    static let dnsTestHost = "www.apple.com"
    static let captivePortalURL = URL(string: "http://captive.apple.com/hotspot-detect.html")!
    static let traceURL = URL(string: "https://1.1.1.1/cdn-cgi/trace")!
    static let downloadBytes = 5_000_000
    static var downloadURL: URL { URL(string: "https://speed.cloudflare.com/__down?bytes=\(downloadBytes)")! }

    /// Runs the steps in order, reporting each as it finishes. Cancellation skips the remaining steps.
    public static func run(gateway: String, checks: TroubleshootChecks,
                           report: @escaping @MainActor (TroubleshootResult) -> Void) async -> [TroubleshootResult] {
        var results: [TroubleshootResult] = []
        var blocking = Set<TroubleshootStep>()
        for step in TroubleshootStep.allCases {
            let result: TroubleshootResult
            if Task.isCancelled {
                result = TroubleshootResult(step: step, status: .skipped, detail: "Cancelled.")
            } else if let blocker = step.dependencies.first(where: blocking.contains) {
                result = TroubleshootResult(step: step, status: .skipped, detail: "Skipped because \"\(blocker.rawValue)\" did not pass.")
            } else {
                result = await check(step, gateway: gateway, checks: checks)
            }
            if result.status == .failed || (result.status == .skipped && result.detail != notOnLAN) { blocking.insert(step) }
            results.append(result)
            await report(result)
        }
        return results
    }

    static let notOnLAN = "Not connected to a Wi-Fi or Ethernet LAN; the router check was skipped."

    private static func check(_ step: TroubleshootStep, gateway: String, checks: TroubleshootChecks) async -> TroubleshootResult {
        switch step {
        case .router:
            guard !gateway.isEmpty else { return TroubleshootResult(step: step, status: .skipped, detail: notOnLAN) }
            guard let ms = await checks.router(gateway) else {
                return TroubleshootResult(step: step, status: .failed, detail: "The router at \(gateway) did not answer on TCP 80, 443 or 53. Check that Wi-Fi is connected and the router is powered on.")
            }
            return TroubleshootResult(step: step, status: .passed, detail: "The router at \(gateway) answered in \(format(ms)) ms.")
        case .dns:
            guard let lookup = await checks.dns(dnsTestHost), !lookup.addresses.isEmpty else {
                return TroubleshootResult(step: step, status: .failed, detail: "\(dnsTestHost) could not be resolved. The DNS server may be down or misconfigured.")
            }
            let status: TroubleshootStatus = lookup.milliseconds > 500 ? .warning : .passed
            return TroubleshootResult(step: step, status: status, detail: "\(dnsTestHost) resolved in \(format(lookup.milliseconds)) ms\(status == .warning ? " (slow)" : "").")
        case .internet:
            guard let ms = await checks.internet() else {
                return TroubleshootResult(step: step, status: .failed, detail: "1.1.1.1 did not answer on TCP 443. The router may have no internet connection.")
            }
            return TroubleshootResult(step: step, status: .passed, detail: "1.1.1.1 answered on TCP 443 in \(format(ms)) ms, without using DNS.")
        case .captivePortal:
            switch await checks.captivePortal() {
            case .open:
                return TroubleshootResult(step: step, status: .passed, detail: "captive.apple.com returned its expected page.")
            case .captive:
                return TroubleshootResult(step: step, status: .failed, detail: "Web traffic is being redirected, usually by a hotel or guest-network sign-in page. Open Safari to sign in.")
            case .unreachable:
                return TroubleshootResult(step: step, status: .warning, detail: "captive.apple.com could not be reached, so a sign-in page could not be ruled out.")
            }
        case .publicIP:
            guard let address = await checks.publicIP() else {
                return TroubleshootResult(step: step, status: .warning, detail: "The public IP address could not be read.")
            }
            return TroubleshootResult(step: step, status: .passed, detail: "Seen on the internet as \(address).")
        case .speed:
            guard let mbps = await checks.downloadMbps() else {
                return TroubleshootResult(step: step, status: .warning, detail: "The download test did not finish.")
            }
            let status: TroubleshootStatus = mbps < 1 ? .warning : .passed
            return TroubleshootResult(step: step, status: status, detail: "About \(format(mbps)) Mbit/s over a 5 MB download\(status == .warning ? " (very slow)" : "").")
        }
    }

    /// One line naming the first failing step, or the warnings when nothing failed.
    public static func summary(_ results: [TroubleshootResult]) -> String {
        if let failed = results.first(where: { $0.status == .failed }) {
            return "Problem found at \"\(failed.step.rawValue)\". \(failed.detail)"
        }
        let warnings = results.filter { $0.status == .warning }
        if !warnings.isEmpty {
            return "Connected, with warnings: " + warnings.map(\.step.rawValue).joined(separator: ", ") + "."
        }
        if results.contains(where: { $0.status == .skipped && $0.detail == "Cancelled." }) { return "Diagnosis cancelled." }
        return results.isEmpty ? "" : "All checks passed."
    }

    static func format(_ value: Double) -> String { String(format: value < 10 ? "%.1f" : "%.0f", value) }

    /// Reads the `ip=` line of a Cloudflare trace response.
    public static func parseTraceIP(_ text: String) -> String? {
        for line in text.split(whereSeparator: \.isNewline) where line.hasPrefix("ip=") {
            let value = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            if DNSLookupService.isIPAddress(value) { return value }
        }
        return nil
    }

    public static func megabitsPerSecond(bytes: Int, seconds: TimeInterval) -> Double? {
        guard bytes > 0, seconds > 0, seconds.isFinite else { return nil }
        return Double(bytes) * 8 / seconds / 1_000_000
    }

    /// Apple's probe page contains "Success" only when nothing intercepted the request.
    public static func captivePortalState(statusCode: Int?, body: String?) -> CaptivePortalState {
        guard let statusCode = statusCode else { return .unreachable }
        return statusCode == 200 && (body ?? "").contains("Success") ? .open : .captive
    }

    public static let live = TroubleshootChecks(
        router: { gateway in
            for port: UInt16 in [80, 443, 53] {
                if let ms = await TCPReachability.probe(host: gateway, port: port, timeout: 1) { return ms }
            }
            return nil
        },
        dns: { await DNSLookupService.resolve($0, timeout: 3) },
        internet: { await TCPReachability.probe(host: "1.1.1.1", port: 443, timeout: 3) },
        captivePortal: {
            let session = URLSession(configuration: ephemeral(timeout: 5))
            defer { session.finishTasksAndInvalidate() }
            guard let loaded = try? await session.data(from: captivePortalURL) else { return .unreachable }
            return captivePortalState(statusCode: (loaded.1 as? HTTPURLResponse)?.statusCode,
                                      body: String(decoding: loaded.0.prefix(4096), as: UTF8.self))
        },
        publicIP: {
            let session = URLSession(configuration: ephemeral(timeout: 5))
            defer { session.finishTasksAndInvalidate() }
            guard let loaded = try? await session.data(from: traceURL) else { return nil }
            return parseTraceIP(String(decoding: loaded.0.prefix(4096), as: UTF8.self))
        },
        downloadMbps: {
            let session = URLSession(configuration: ephemeral(timeout: 15))
            defer { session.finishTasksAndInvalidate() }
            let start = CFAbsoluteTimeGetCurrent()
            guard let loaded = try? await session.data(from: downloadURL),
                  (loaded.1 as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return megabitsPerSecond(bytes: loaded.0.count, seconds: CFAbsoluteTimeGetCurrent() - start)
        })

    private static func ephemeral(timeout: TimeInterval) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.waitsForConnectivity = false
        return configuration
    }
}
