import XCTest
import Foundation
import Darwin
import Network
@testable import NetScanCore

final class EdgeCaseTests: XCTestCase {
    func testVendorDefaultsPreserveSpecificDeviceCategories() {
        for (mac, expected) in [("70:11:24:00:00:01", DeviceType.tv), ("00:17:F2:00:00:01", .computer),
                                ("00:00:F0:00:00:01", .tv), ("70:9E:29:00:00:01", .gaming),
                                ("50:C7:BF:00:00:01", .smartHome)] {
            XCTAssertEqual(OUIVendorDatabase.identifyDevice(macAddress: mac, hostname: "192.168.1.20").deviceType, expected)
        }
        XCTAssertEqual(OUIVendorDatabase.identifyDevice(macAddress: "00:17:F2:00:00:01", hostname: "office-iphone").deviceType, .phone)
    }
    func testWakePacketContentsAndMACValidation() throws {
        let packet = try XCTUnwrap(WakeOnLANService.magicPacket(macAddress: " 00:11:22:33:44:55 "))
        XCTAssertEqual(packet.count, 102)
        XCTAssertEqual(Array(packet.prefix(6)), [UInt8](repeating: 255, count: 6))
        for offset in stride(from: 6, to: 102, by: 6) {
            XCTAssertEqual(Array(packet[offset..<offset + 6]), [0, 17, 34, 51, 68, 85])
        }
        XCTAssertEqual(WakeOnLANService.magicPacket(macAddress: "0011.2233.4455"), packet)
        for invalid in ["Unknown MAC", "00:11:22:33:44", "00:11:22:33:44:GG", "😀00112233445"] {
            XCTAssertNil(WakeOnLANService.magicPacket(macAddress: invalid))
        }
    }

    func testWakePacketActuallyArrivesViaUDP() throws {
        let descriptor = socket(AF_INET, SOCK_DGRAM, 0)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        guard descriptor >= 0 else { return }
        defer { close(descriptor) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        inet_pton(AF_INET, "127.0.0.1", &address.sin_addr)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        XCTAssertEqual(bound, 0)
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        XCTAssertEqual(withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(descriptor, $0, &length) }
        }, 0)
        let sent = expectation(description: "UDP submission callback on main")
        sent.assertForOverFulfill = true
        WakeOnLANService().sendWakePacket(macAddress: "00:11:22:33:44:55", broadcastIP: "127.0.0.1",
                                          port: UInt16(bigEndian: address.sin_port), interfaceName: "lo0") { success, _ in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertTrue(success)
            sent.fulfill()
        }
        wait(for: [sent], timeout: 2)
        var pending = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
        XCTAssertEqual(poll(&pending, 1, 1000), 1)
        var buffer = [UInt8](repeating: 0, count: 128)
        let received = recv(descriptor, &buffer, buffer.count, MSG_DONTWAIT)
        XCTAssertEqual(received, 102)
        if received == 102 {
            XCTAssertEqual(Data(buffer.prefix(received)), WakeOnLANService.magicPacket(macAddress: "001122334455"))
        }
        XCTAssertNotNil(TrafficMonitorService.interfaceBytes(name: "lo0"))
        XCTAssertNil(TrafficMonitorService.interfaceBytes(name: "missing-interface"))
    }

    func testWakePacketRejectsInvalidDestinationsAndInterfaceOnMain() {
        let done = expectation(description: "all invalid sends fail")
        done.expectedFulfillmentCount = 3
        for (ip, port, interface) in [("bad host", UInt16(9), "lo0"), ("127.0.0.1", 0, "lo0"), ("127.0.0.1", 9, "missing-interface")] {
            WakeOnLANService().sendWakePacket(macAddress: "001122334455", broadcastIP: ip, port: port, interfaceName: interface) { success, _ in
                XCTAssertTrue(Thread.isMainThread)
                XCTAssertFalse(success)
                done.fulfill()
            }
        }
        wait(for: [done], timeout: 2)
    }

    func testNonLANScanSupersedesPreviousDiscovery() {
        let scanner = SubnetScannerService()
        let old = expectation(description: "old LAN scan suppressed")
        old.isInverted = true
        scanner.scanSubnet(interface: NetworkInterfaceInfo(ipAddress: "127.0.0.1", cidrPrefix: 32, isConnected: true, isLAN: true),
                           onProgress: { _ in old.fulfill() }, onDeviceFound: { _ in old.fulfill() }, onCompletion: { _ in old.fulfill() })
        let done = expectation(description: "offline replacement completes")
        scanner.scanSubnet(interface: NetworkInterfaceInfo(), onProgress: { _ in }, onDeviceFound: { _ in XCTFail() }, onCompletion: {
            XCTAssertTrue($0.isEmpty)
            done.fulfill()
        })
        wait(for: [old, done], timeout: 0.5)
    }

    func testPaddedPortTargetFindsLoopbackListener() throws {
        let listener = try NWListener(using: .tcp, on: .any)
        listener.newConnectionHandler = { $0.cancel() }
        let ready = expectation(description: "listener ready")
        listener.stateUpdateHandler = { if case .ready = $0 { ready.fulfill() } }
        listener.start(queue: .main)
        defer { listener.cancel() }
        wait(for: [ready], timeout: 2)
        let port = Int(try XCTUnwrap(listener.port).rawValue)
        let done = expectation(description: "padded target scanned")
        PortScannerService().scanPorts(targetIP: " \t127.0.0.1\n", ports: [port], onPortFound: { _ in }, onProgress: { _ in }, onCompletion: {
            XCTAssertEqual($0.map(\.port), [port])
            done.fulfill()
        })
        wait(for: [done], timeout: 2)
    }

    @MainActor
    func testDetailRefreshesDisplayedPortsWithoutDuplicatingIDs() {
        var device = NetworkDevice(ipAddress: "127.0.0.1", openPorts: [80])
        let detail = DeviceDetailViewModel(device: device)
        device.openPorts = [443, 22, 443]
        detail.updateLiveDevice(device)
        XCTAssertEqual(detail.openPorts.map(\.port), [22, 443])
    }

    @MainActor
    func testRapidPingToggleUsesServiceStateAndStopCancelsToolScan() {
        let model = NetworkToolsViewModel()
        model.pingTarget = "127.0.0.1"
        model.togglePing()
        XCTAssertTrue(model.isPinging)
        model.togglePing()
        XCTAssertFalse(model.isPinging)
        model.portScanTarget = "127.0.0.1"
        model.runPortScan()
        model.stopDiagnostics()
        XCTAssertFalse(model.isScanningPorts)
    }

    func testHTTPIdentityUsesHEADBannerWithoutWaitingForBody() async {
        HTTPProbeProtocol.configure(server: "Synology", body: Data())
        let start = Date()
        let result = await OUIVendorDatabase.probeHTTPIdentity(ip: "127.0.0.1", configuration: configuration())
        XCTAssertEqual(result?.vendor, "Synology Inc.")
        XCTAssertLessThan(Date().timeIntervalSince(start), 1)
    }

    func testHTTPIdentityFallsBackFromUnrecognizedHEADToBoundedGET() async {
        let stopped = expectation(description: "stream cancelled after prefix")
        let prefix = Data(("<title>Raspberry Pi</title>" + String(repeating: "x", count: 2048)).utf8)
        HTTPProbeProtocol.configure(server: nil, body: prefix, stopped: { stopped.fulfill() })
        let result = await OUIVendorDatabase.probeHTTPIdentity(ip: "127.0.0.1", configuration: configuration())
        XCTAssertEqual(result?.vendor, "Raspberry Pi Foundation")
        await fulfillment(of: [stopped], timeout: 2)
    }

    func testHTTPIdentityDoesNotInspectTitleBeyondByteLimit() async {
        let stopped = expectation(description: "oversized stream cancelled")
        let body = Data((String(repeating: "x", count: 2048) + "<title>Raspberry Pi</title>").utf8)
        HTTPProbeProtocol.configure(server: nil, body: body, stopped: { stopped.fulfill() })
        let result = await OUIVendorDatabase.probeHTTPIdentity(ip: "127.0.0.1", configuration: configuration())
        XCTAssertNil(result)
        await fulfillment(of: [stopped], timeout: 2)
    }

    func testRealHTTPServerIdentifiesFromHeadersWhileBodyStalls() async throws {
        let listener = try NWListener(using: .tcp, on: .any)
        let ready = expectation(description: "HTTP listener ready")
        let connections = HTTPServerConnections()
        listener.stateUpdateHandler = { if case .ready = $0 { ready.fulfill() } }
        listener.newConnectionHandler = { connection in
            connections.add(connection)
            connection.start(queue: .global())
            connection.receive(minimumIncompleteLength: 1, maximumLength: 2048) { data, _, _, error in
                XCTAssertNil(error)
                XCTAssertTrue(String(data: data ?? Data(), encoding: .utf8)?.hasPrefix("HEAD /") == true)
                let headers = "HTTP/1.1 200 OK\r\nServer: Synology\r\nContent-Type: text/plain\r\nContent-Length: 1024\r\nConnection: keep-alive\r\n\r\n"
                connection.send(content: Data(headers.utf8), completion: .contentProcessed { XCTAssertNil($0) })
            }
        }
        listener.start(queue: .global())
        defer {
            listener.cancel()
            connections.close()
        }
        await fulfillment(of: [ready], timeout: 2)
        let port = try XCTUnwrap(listener.port)
        let start = Date()
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForResource = 2
        let result = await OUIVendorDatabase.probeHTTPIdentity(ip: "127.0.0.1:\(port.rawValue)", configuration: config)
        XCTAssertEqual(result?.vendor, "Synology Inc.")
        XCTAssertLessThan(Date().timeIntervalSince(start), 1)
    }

    func testCancelledVendorSearchDoesNotStartHTTP() async {
        let request = expectation(description: "cancelled lookup must not request HTTP")
        request.isInverted = true
        HTTPProbeProtocol.configure(server: "Synology", body: Data(), started: { request.fulfill() })
        let config = configuration()
        let lookup = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await OUIVendorDatabase.probeHTTPIdentity(ip: "127.0.0.1", configuration: config)
        }
        let result = await lookup.value
        XCTAssertNil(result)
        await fulfillment(of: [request], timeout: 0.2)
    }

    func testCancellationDuringHEADPreventsGETFallback() async {
        let lock = NSLock()
        var requests = 0
        var lookup: Task<(vendor: String, deviceType: DeviceType)?, Never>?
        HTTPProbeProtocol.configure(server: nil, body: Data(), started: {
            lock.withLock {
                requests += 1
                lookup?.cancel()
            }
        })
        let config = configuration()
        let task = lock.withLock {
            let task = Task { await OUIVendorDatabase.probeHTTPIdentity(ip: "127.0.0.1", configuration: config) }
            lookup = task
            return task
        }
        let result = await task.value
        XCTAssertNil(result)
        XCTAssertEqual(lock.withLock { requests }, 1)
    }

    private func configuration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [HTTPProbeProtocol.self]
        config.timeoutIntervalForResource = 2
        return config
    }

    func testTrafficDeltasAndCounterReset() {
        let monitor = TrafficMonitorService()
        monitor.stopMonitoring()
        let interface = NetworkInterfaceInfo(ipAddress: "127.0.0.1", isConnected: true, isLAN: true)
        let start = Date()
        monitor.recordSample(interface: interface, counters: (100, 200), time: start)
        XCTAssertEqual(monitor.currentUploadKbps, 0)
        monitor.recordSample(interface: interface, counters: (2148, 4296), time: start.addingTimeInterval(2))
        XCTAssertEqual(monitor.currentUploadKbps, 1)
        XCTAssertEqual(monitor.currentDownloadKbps, 2)
        XCTAssertEqual(monitor.totalBytesUploaded, 2048)
        XCTAssertEqual(monitor.totalBytesDownloaded, 4096)
        monitor.recordSample(interface: interface, counters: (5, 10), time: start.addingTimeInterval(3))
        XCTAssertEqual(monitor.currentUploadKbps, 0)
        XCTAssertEqual(monitor.totalBytesUploaded, 2048)
    }

    func testTrafficDisconnectAndInterfaceChangeResetBaseline() {
        let monitor = TrafficMonitorService()
        monitor.stopMonitoring()
        var interface = NetworkInterfaceInfo(ipAddress: "127.0.0.1", isConnected: true, isLAN: true)
        let start = Date()
        monitor.recordSample(interface: interface, counters: (100, 200), time: start)
        interface.interfaceName = "other-interface"
        monitor.recordSample(interface: interface, counters: (10000, 20000), time: start.addingTimeInterval(1))
        XCTAssertEqual(monitor.totalBytesUploaded, 0)
        interface.isConnected = false
        monitor.recordSample(interface: interface, counters: nil, time: start.addingTimeInterval(2))
        interface.isConnected = true
        monitor.recordSample(interface: interface, counters: (20000, 40000), time: start.addingTimeInterval(3))
        XCTAssertEqual(monitor.currentUploadKbps, 0)
        XCTAssertEqual(monitor.totalBytesUploaded, 0)
    }

    func testTrafficHistoryIsBoundedAndStopClearsVisibleRates() {
        let monitor = TrafficMonitorService()
        monitor.stopMonitoring()
        let interface = NetworkInterfaceInfo(ipAddress: "127.0.0.1", isConnected: true, isLAN: true)
        let start = Date()
        for index in 0...40 {
            monitor.recordSample(interface: interface, counters: (UInt64(index * 1024), UInt64(index * 2048)),
                                 time: start.addingTimeInterval(Double(index)))
        }
        XCTAssertEqual(monitor.recentThroughputPoints.count, 30)
        XCTAssertEqual(monitor.currentUploadKbps, 1)
        monitor.stopMonitoring()
        XCTAssertEqual(monitor.currentUploadKbps, 0)
        XCTAssertEqual(monitor.currentDownloadKbps, 0)
    }

}

private final class HTTPServerConnections: @unchecked Sendable {
    private let lock = NSLock()
    private var connections: [NWConnection] = []

    func add(_ connection: NWConnection) { lock.withLock { connections.append(connection) } }
    func close() {
        let snapshot = lock.withLock { connections }
        snapshot.forEach { $0.cancel() }
    }
}

private final class HTTPProbeProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var fixture: (server: String?, body: Data, started: (() -> Void)?, stopped: (() -> Void)?) = (nil, Data(), nil, nil)
    private var stopped: (() -> Void)?

    static func configure(server: String?, body: Data, started: (() -> Void)? = nil, stopped: (() -> Void)? = nil) {
        lock.withLock { fixture = (server, body, started, stopped) }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let snapshot = Self.lock.withLock { Self.fixture }
        Self.lock.withLock { stopped = request.httpMethod == "GET" ? snapshot.stopped : nil }
        snapshot.started?()
        var headers = ["Content-Type": "text/plain", "Content-Length": "1048576"]
        if let server = snapshot.server { headers["server"] = server }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if request.httpMethod == "HEAD" {
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        if !snapshot.body.isEmpty { client?.urlProtocol(self, didLoad: snapshot.body) }
        // Deliberately never finish: production must return from headers or the byte cap.
    }
    override func stopLoading() { Self.lock.withLock { stopped }?() }
}
