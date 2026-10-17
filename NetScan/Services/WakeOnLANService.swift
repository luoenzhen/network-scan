//
//  WakeOnLANService.swift
//  NetScan
//
//  Sends Wake-on-LAN (WOL) magic packets across the broadcast domain.
//

import Foundation
import Network

public class WakeOnLANService {
    public static let shared = WakeOnLANService()
    
    public init() {}
    
    public func sendWakePacket(macAddress: String, broadcastIP: String = "255.255.255.255", port: UInt16 = 9, completion: @escaping (Bool, String) -> Void) {
        let cleanMac = macAddress.uppercased().replacingOccurrences(of: ":", with: "")
                                             .replacingOccurrences(of: "-", with: "")
        guard cleanMac.count == 12 else {
            completion(false, "Invalid MAC address format (must be 12 hex chars)")
            return
        }
        
        var macBytes = [UInt8]()
        for i in stride(from: 0, to: 12, by: 2) {
            let start = cleanMac.index(cleanMac.startIndex, offsetBy: i)
            let end = cleanMac.index(start, offsetBy: 2)
            if let byte = UInt8(cleanMac[start..<end], radix: 16) {
                macBytes.append(byte)
            }
        }
        
        guard macBytes.count == 6 else {
            completion(false, "Could not parse MAC bytes")
            return
        }
        
        // WOL Magic Packet: 6x 0xFF followed by 16x MAC Address = 102 bytes total
        var magicPacket = [UInt8](repeating: 0xFF, count: 6)
        for _ in 0..<16 {
            magicPacket.append(contentsOf: macBytes)
        }
        
        let host = NWEndpoint.Host(broadcastIP)
        guard port > 0, let endpointPort = NWEndpoint.Port(rawValue: port) else {
            completion(false, "Invalid UDP Port")
            return
        }
        
        let connection = NWConnection(host: host, port: endpointPort, using: .udp)
        let queue = DispatchQueue(label: "com.netscan.wol")
        var finished = false
        let finish: (Bool, String) -> Void = { success, message in
            guard !finished else { return }
            finished = true
            connection.stateUpdateHandler = nil
            connection.cancel()
            DispatchQueue.main.async { completion(success, message) }
        }
        let timeoutWork = DispatchWorkItem { finish(false, "Timed out sending Wake-on-LAN packet") }
        queue.asyncAfter(deadline: .now() + 2, execute: timeoutWork)
        connection.stateUpdateHandler = { state in
            guard !finished else { return }
            if case .ready = state {
                connection.send(content: Data(magicPacket), completion: .contentProcessed { error in
                    timeoutWork.cancel()
                    if let err = error {
                        finish(false, "Failed to send packet: \(err.localizedDescription)")
                    } else {
                        finish(true, "Magic packet successfully sent to \(macAddress)")
                    }
                })
            } else if case .failed(let err) = state {
                timeoutWork.cancel()
                finish(false, "Connection error: \(err.localizedDescription)")
            }
        }
        connection.start(queue: queue)
    }
}
