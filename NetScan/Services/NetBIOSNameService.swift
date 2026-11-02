//
//  NetBIOSNameService.swift
//  NetScan
//
//  Unicast NetBIOS node-status query (UDP 137) for Windows, Samba and NAS names.
//  Unicast needs only Local Network access, not the multicast entitlement.
//

import Foundation
#if canImport(Darwin)
import Darwin
#endif

public enum NetBIOSNameService {
    /// The host's workstation or server name, or nil when it does not answer within the timeout.
    public static func queryName(ip: String, timeout: TimeInterval = 0.8) async -> String? {
        guard timeout.isFinite, timeout > 0 else { return nil }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: query(ip: ip, timeout: min(timeout, 3)))
            }
        }
    }

    private static func query(ip: String, timeout: TimeInterval) -> String? {
        var address = sockaddr_in()
        #if canImport(Darwin)
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        #endif
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = UInt16(137).bigEndian
        guard inet_pton(AF_INET, ip, &address.sin_addr) == 1 else { return nil }
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        let transactionID = UInt16.random(in: 1...UInt16.max)
        let request = statusRequest(transactionID: transactionID)
        let sent = request.withUnsafeBytes { buffer in
            withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(fd, buffer.baseAddress, buffer.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        guard sent == request.count else { return nil }
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        let capacity = 1024
        var buffer = [UInt8](repeating: 0, count: capacity)
        while true {
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else { return nil }
            var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptor, 1, Int32(max(1, remaining * 1000)))
            if ready < 0 && errno == EINTR { continue }
            guard ready > 0 else { return nil }
            var from = sockaddr_in()
            var fromLength = socklen_t(MemoryLayout<sockaddr_in>.size)
            let count = withUnsafeMutablePointer(to: &from) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { recvfrom(fd, &buffer, capacity, 0, $0, &fromLength) }
            }
            guard count > 0 else { return nil }
            // Ignore datagrams from other hosts or for other queries.
            guard from.sin_addr.s_addr == address.sin_addr.s_addr else { continue }
            let data = Data(buffer[0..<count])
            guard data.count >= 2, UInt16(data[0]) << 8 | UInt16(data[1]) == transactionID else { continue }
            return parseStatusResponse(data)
        }
    }

    /// NBSTAT query for the wildcard name "*".
    static func statusRequest(transactionID: UInt16) -> Data {
        var bytes: [UInt8] = [UInt8(transactionID >> 8), UInt8(transactionID & 0xFF),
                              0x00, 0x00, // flags: query
                              0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
        bytes.append(0x20)
        // First-level encoding: each nibble of "*" + 15 NULs becomes 'A' + nibble.
        for byte in [UInt8(0x2A)] + [UInt8](repeating: 0, count: 15) {
            bytes.append(0x41 + (byte >> 4))
            bytes.append(0x41 + (byte & 0x0F))
        }
        bytes += [0x00, 0x00, 0x21, 0x00, 0x01] // end of name, NBSTAT, IN
        return Data(bytes)
    }

    /// Picks the first unique workstation (0x00) name, falling back to the server (0x20) name.
    static func parseStatusResponse(_ data: Data) -> String? {
        let bytes = [UInt8](data)
        guard bytes.count >= 12, bytes[2] & 0x80 != 0, UInt16(bytes[6]) << 8 | UInt16(bytes[7]) >= 1 else { return nil }
        var index = 12
        // Answer name: a pointer or a sequence of labels.
        if index < bytes.count && bytes[index] & 0xC0 == 0xC0 {
            index += 2
        } else {
            while index < bytes.count && bytes[index] != 0 {
                index += Int(bytes[index]) + 1
            }
            index += 1
        }
        // TYPE(2) CLASS(2) TTL(4) RDLENGTH(2)
        guard index + 10 <= bytes.count, bytes[index] == 0x00, bytes[index + 1] == 0x21 else { return nil }
        let rdLength = Int(bytes[index + 8]) << 8 | Int(bytes[index + 9])
        index += 10
        guard rdLength >= 1, index + rdLength <= bytes.count else { return nil }
        let nameCount = Int(bytes[index])
        index += 1
        guard nameCount * 18 <= rdLength - 1 else { return nil }
        var workstation: String?
        var server: String?
        for entry in 0..<nameCount {
            let start = index + entry * 18
            let suffix = bytes[start + 15]
            let isGroup = bytes[start + 16] & 0x80 != 0
            guard !isGroup else { continue }
            let raw = bytes[start..<(start + 15)]
            guard raw.allSatisfy({ $0 >= 0x20 && $0 < 0x7F }) else { continue }
            let name = String(decoding: raw, as: UTF8.self).trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, name != "*" else { continue }
            if suffix == 0x00 && workstation == nil { workstation = name }
            if suffix == 0x20 && server == nil { server = name }
        }
        return workstation ?? server
    }
}
