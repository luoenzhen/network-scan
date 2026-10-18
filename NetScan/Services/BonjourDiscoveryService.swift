import Foundation
import Darwin

public struct BonjourObservation {
    public var address: String
    public var hostname: String
    public var name: String
    public var type: String
    public var port: Int
}

/// Browsers and NetService delegates live on the main run loop; no service TCP connection is opened.
public final class BonjourDiscoveryService: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    public static let shared = BonjourDiscoveryService()
    public let serviceTypes = ["_http._tcp", "_airplay._tcp", "_googlecast._tcp", "_smb._tcp",
                               "_companion-link._tcp", "_raop._tcp", "_printer._tcp", "_ipp._tcp",
                               "_ssh._tcp", "_workstation._tcp", "_device-info._tcp"]
    private var browsers: [NetServiceBrowser] = []
    private var services: [NetService] = []
    private var pending: [NetService] = []
    private var resolving: [NetService] = []
    private var callback: ((BonjourObservation) -> Void)?

    public override init() { super.init() }

    public func startBrowsing(onServiceFound: @escaping (BonjourObservation) -> Void) {
        stopBrowsing()
        callback = onServiceFound
        for type in serviceTypes {
            let browser = NetServiceBrowser()
            browser.delegate = self
            browsers.append(browser)
            browser.searchForServices(ofType: type, inDomain: "local.")
        }
    }

    public func stopBrowsing() {
        callback = nil
        browsers.forEach { $0.delegate = nil; $0.stop() }
        services.forEach { $0.delegate = nil; $0.stop() }
        browsers.removeAll()
        services.removeAll()
        pending.removeAll()
        resolving.removeAll()
    }

    public func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        guard browsers.contains(where: { $0 === browser }), services.count < 512,
              !services.contains(where: { $0.name == service.name && $0.type == service.type && $0.domain == service.domain }) else { return }
        services.append(service)
        pending.append(service)
        resolveNext()
    }

    private func resolveNext() {
        while resolving.count < 8 && !pending.isEmpty {
            let service = pending.removeFirst()
            resolving.append(service)
            service.delegate = self
            service.resolve(withTimeout: 2)
        }
    }

    public func netServiceDidResolveAddress(_ sender: NetService) {
        guard resolving.contains(where: { $0 === sender }) else { return }
        for data in sender.addresses ?? [] {
            if let ip = Self.ipv4Address(data) {
                callback?(BonjourObservation(address: ip, hostname: sender.hostName ?? "", name: sender.name,
                                             type: sender.type, port: sender.port))
            }
        }
        finish(sender)
    }

    public func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) { finish(sender) }

    private func finish(_ service: NetService) {
        service.delegate = nil
        service.stop()
        resolving.removeAll { $0 === service }
        resolveNext()
    }

    static func ipv4Address(_ data: Data) -> String? {
        guard data.count >= MemoryLayout<sockaddr_in>.size else { return nil }
        var address = sockaddr_in()
        _ = withUnsafeMutableBytes(of: &address) { data.copyBytes(to: $0) }
        guard address.sin_family == sa_family_t(AF_INET) else { return nil }
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        guard inet_ntop(AF_INET, &address.sin_addr, &buffer, socklen_t(buffer.count)) != nil else { return nil }
        return String(cString: buffer)
    }
}
