//
//  DNSLookupService.swift
//  NetScan
//
//  Forward (A/AAAA) and reverse (PTR) lookups through the system resolver.
//

import Foundation
#if canImport(Darwin)
import Darwin
#endif

public struct DNSLookupResult: Equatable {
    public var query: String
    public var addresses: [String]
    public var reverseName: String?
    public var milliseconds: Double

    public init(query: String, addresses: [String], reverseName: String? = nil, milliseconds: Double) {
        self.query = query
        self.addresses = addresses
        self.reverseName = reverseName
        self.milliseconds = milliseconds
    }
}

public enum DNSLookupService {
    public static func isIPAddress(_ text: String) -> Bool {
        var v4 = in_addr()
        var v6 = in6_addr()
        return inet_pton(AF_INET, text, &v4) == 1 || inet_pton(AF_INET6, text, &v6) == 1
    }

    /// Looks up an address's PTR name, or a hostname's IPv4 and IPv6 addresses. Nil on failure or timeout.
    public static func resolve(_ query: String, timeout: TimeInterval = 3) async -> DNSLookupResult? {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, query.count <= 253, timeout.isFinite, timeout > 0 else { return nil }
        let start = CFAbsoluteTimeGetCurrent()
        if isIPAddress(query) {
            guard let name = await OUIVendorDatabase.resolveReverseDNS(ip: query, timeout: timeout) else { return nil }
            return DNSLookupResult(query: query, addresses: [query], reverseName: name, milliseconds: elapsed(since: start))
        }
        let addresses = await withCheckedContinuation { (continuation: CheckedContinuation<[String]?, Never>) in
            let lock = NSLock()
            var completed = false
            let finish: ([String]?) -> Void = { value in
                lock.lock()
                defer { lock.unlock() }
                guard !completed else { return }
                completed = true
                continuation.resume(returning: value)
            }
            // getaddrinfo cannot be cancelled; a late answer is discarded.
            DispatchQueue.global().asyncAfter(deadline: .now() + min(timeout, 30)) { finish(nil) }
            DispatchQueue.global(qos: .userInitiated).async { finish(addressInfo(query)) }
        }
        guard let found = addresses, !found.isEmpty else { return nil }
        return DNSLookupResult(query: query, addresses: found, milliseconds: elapsed(since: start))
    }

    private static func elapsed(since start: CFAbsoluteTime) -> Double {
        round((CFAbsoluteTimeGetCurrent() - start) * 10_000) / 10
    }

    private static func addressInfo(_ host: String) -> [String]? {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        var list: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &list) == 0 else { return nil }
        defer { freeaddrinfo(list) }
        var addresses: [String] = []
        var pointer = list
        while let entry = pointer?.pointee {
            if let address = entry.ai_addr {
                var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(address, entry.ai_addrlen, &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 {
                    let text = String(cString: buffer)
                    if !addresses.contains(text) { addresses.append(text) }
                }
            }
            pointer = entry.ai_next
        }
        // IPv4 first; IPv6 addresses keep resolver order after them.
        return addresses.filter { !$0.contains(":") } + addresses.filter { $0.contains(":") }
    }
}
