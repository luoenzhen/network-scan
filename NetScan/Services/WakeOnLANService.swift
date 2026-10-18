//
//  WakeOnLANService.swift
//  NetScan
//
//  Sends a UDP magic packet using the broadcast-capable BSD socket API.
//

import Foundation
import Darwin

public class WakeOnLANService {
    public static let shared = WakeOnLANService()

    public init() {}

    public func sendWakePacket(macAddress: String, broadcastIP: String = "255.255.255.255", port: UInt16 = 9,
                               interfaceName: String? = nil, completion: @escaping (Bool, String) -> Void) {
        guard let packet = Self.magicPacket(macAddress: macAddress) else {
            DispatchQueue.main.async { completion(false, "Enter a MAC address containing 12 hexadecimal digits.") }
            return
        }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        guard port > 0, inet_pton(AF_INET, broadcastIP, &address.sin_addr) == 1 else {
            DispatchQueue.main.async { completion(false, "Enter a valid IPv4 destination and nonzero UDP port.") }
            return
        }
        let destination = address
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try Self.send(packet: packet, to: destination, interfaceName: interfaceName)
                DispatchQueue.main.async {
                    completion(true, "Magic packet sent. The receiving device must support and enable Wake-on-LAN.")
                }
            } catch {
                let permissionDenied = (error as? POSIXError)?.code == .EACCES || (error as? POSIXError)?.code == .EPERM
                let message = permissionDenied
                    ? "Allow Local Network access. On iOS, broadcast Wake-on-LAN also requires Multicast Networking permission in the app's signing profile."
                    : "Could not send magic packet: \(error.localizedDescription)"
                DispatchQueue.main.async { completion(false, message) }
            }
        }
    }

    static func magicPacket(macAddress: String) -> Data? {
        let clean = macAddress.uppercased().replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "").replacingOccurrences(of: ".", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count == 12, clean.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) }) else { return nil }
        var bytes: [UInt8] = []
        for offset in stride(from: 0, to: 12, by: 2) {
            let start = clean.index(clean.startIndex, offsetBy: offset)
            guard let byte = UInt8(clean[start..<clean.index(start, offsetBy: 2)], radix: 16) else { return nil }
            bytes.append(byte)
        }
        var packet = Data(repeating: 0xFF, count: 6)
        for _ in 0..<16 { packet.append(contentsOf: bytes) }
        return packet
    }

    private static func send(packet: Data, to destination: sockaddr_in, interfaceName: String?) throws {
        let descriptor = socket(AF_INET, SOCK_DGRAM, 0)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(descriptor) }
        var broadcast: Int32 = 1
        guard setsockopt(descriptor, SOL_SOCKET, SO_BROADCAST, &broadcast, socklen_t(MemoryLayout<Int32>.size)) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        let flags = fcntl(descriptor, F_GETFL, 0)
        guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        if let name = interfaceName {
            var index = if_nametoindex(name)
            guard index > 0 else { throw POSIXError(.ENXIO) }
            guard setsockopt(descriptor, IPPROTO_IP, IP_BOUND_IF, &index, socklen_t(MemoryLayout<UInt32>.size)) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        }
        var address = destination
        let sent = packet.withUnsafeBytes { buffer in
            withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(descriptor, buffer.baseAddress, buffer.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        guard sent == packet.count else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }
}
