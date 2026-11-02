import XCTest
import Foundation
import Network
@testable import NetScanCore

final class FeatureTests: XCTestCase {
    // MARK: Port lists, admin pages and banners

    func testCustomPortListParsesRangesAndRejectsInvalidInput() {
        XCTAssertEqual(KnownPorts.parsePortList("22, 80-82 443;80").ports, [22, 80, 81, 82, 443])
        XCTAssertNil(KnownPorts.parsePortList("1-1024").error)
        XCTAssertNotNil(KnownPorts.parsePortList("").error)
        XCTAssertNotNil(KnownPorts.parsePortList("0").error)
        XCTAssertNotNil(KnownPorts.parsePortList("90-80").error)
        XCTAssertNotNil(KnownPorts.parsePortList("80-").error)
        XCTAssertNotNil(KnownPorts.parsePortList("ssh").error)
        XCTAssertNotNil(KnownPorts.parsePortList("1-2000").error)
        XCTAssertNotNil(KnownPorts.parsePortList("1-1000, 2000-2100").error)
    }

    func testAdminURLOnlyForWebPortsAndPlainHosts() {
        XCTAssertEqual(KnownPorts.adminURL(host: "192.168.1.1", port: 80)?.absoluteString, "http://192.168.1.1/")
        XCTAssertEqual(KnownPorts.adminURL(host: "192.168.1.1", port: 8443)?.absoluteString, "https://192.168.1.1:8443/")
        XCTAssertEqual(KnownPorts.adminURL(host: " nas.local ", port: 5000)?.absoluteString, "http://nas.local:5000/")
        XCTAssertNil(KnownPorts.adminURL(host: "192.168.1.1", port: 22))
        XCTAssertNil(KnownPorts.adminURL(host: "evil.com/@x", port: 80))
        XCTAssertNil(KnownPorts.adminURL(host: "", port: 80))
    }

    func testBannerSanitizingKeepsOnePrintableLine() {
        XCTAssertEqual(PortScannerService.sanitizeBanner(Data("SSH-2.0-OpenSSH_9.6\r\nmore".utf8), isHTTP: false), "SSH-2.0-OpenSSH_9.6")
        XCTAssertEqual(PortScannerService.sanitizeBanner(Data("HTTP/1.1 200 OK\r\nServer: lighttpd/1.4\r\n\r\n".utf8), isHTTP: true), "lighttpd/1.4")
        XCTAssertEqual(PortScannerService.sanitizeBanner(Data("HTTP/1.0 401 Unauthorized\r\n\r\n".utf8), isHTTP: true), "HTTP/1.0 401 Unauthorized")
        XCTAssertNil(PortScannerService.sanitizeBanner(Data([0x00, 0x01, 0x02]), isHTTP: false))
        let long = String(repeating: "a", count: 500)
        XCTAssertEqual(PortScannerService.sanitizeBanner(Data(long.utf8), isHTTP: false)?.count, 120)
    }

    func testPortScanReadsServiceBannerFromLoopbackListener() throws {
        let ready = expectation(description: "listener ready")
        let listener = try NWListener(using: .tcp, on: .any)
        listener.newConnectionHandler = { connection in
            connection.start(queue: .main)
            // The completion keeps the connection alive until the banner is written, then closes it gracefully.
            connection.send(content: Data("SSH-2.0-NetScanTest\r\n".utf8), completion: .contentProcessed { _ in connection.cancel() })
        }
        listener.stateUpdateHandler = { if case .ready = $0 { ready.fulfill() } }
        listener.start(queue: .main)
        defer { listener.cancel() }
        wait(for: [ready], timeout: 2)
        let port = Int(try XCTUnwrap(listener.port).rawValue)
        let done = expectation(description: "banner scan completes")
        PortScannerService().scanPorts(targetIP: "127.0.0.1", ports: [port], grabBanners: true,
                                       onPortFound: { _ in }, onProgress: { _ in }, onCompletion: { results in
            XCTAssertEqual(results.first?.banner, "SSH-2.0-NetScanTest")
            done.fulfill()
        })
        wait(for: [done], timeout: 3)
    }

    // MARK: NetBIOS

    func testNetBIOSStatusRequestEncodesWildcardName() {
        let request = [UInt8](NetBIOSNameService.statusRequest(transactionID: 0x1234))
        XCTAssertEqual(request.count, 50)
        XCTAssertEqual(Array(request[0..<2]), [0x12, 0x34])
        XCTAssertEqual(request[12], 0x20)
        XCTAssertEqual(Array(request[13..<15]), [0x43, 0x4B]) // "*" -> "CK"
        XCTAssertTrue(request[15..<45].allSatisfy { $0 == 0x41 })
        XCTAssertEqual(Array(request[45..<50]), [0x00, 0x00, 0x21, 0x00, 0x01])
    }

    private func netbiosEntry(_ name: String, suffix: UInt8, group: Bool) -> [UInt8] {
        let padded = Array(name.utf8.prefix(15)) + [UInt8](repeating: 0x20, count: max(0, 15 - name.utf8.count))
        return padded + [suffix, group ? 0x84 : 0x04, 0x00]
    }

    func testNetBIOSResponsePrefersUniqueWorkstationName() {
        let request = [UInt8](NetBIOSNameService.statusRequest(transactionID: 0x1234))
        let entries = netbiosEntry("WORKGROUP", suffix: 0x00, group: true)
            + netbiosEntry("OFFICE-PC", suffix: 0x20, group: false)
            + netbiosEntry("OFFICE-PC", suffix: 0x00, group: false)
        let rdata: [UInt8] = [3] + entries + [UInt8](repeating: 0, count: 6)
        var response: [UInt8] = [0x12, 0x34, 0x84, 0x00, 0, 0, 0, 1, 0, 0, 0, 0]
        response += Array(request[12..<46])
        response += [0x00, 0x21, 0x00, 0x01, 0, 0, 0, 0, UInt8(rdata.count >> 8), UInt8(rdata.count & 0xFF)]
        response += rdata
        XCTAssertEqual(NetBIOSNameService.parseStatusResponse(Data(response)), "OFFICE-PC")
        XCTAssertNil(NetBIOSNameService.parseStatusResponse(Data(response.prefix(60))))
        var query = response
        query[2] = 0x00 // not a response
        XCTAssertNil(NetBIOSNameService.parseStatusResponse(Data(query)))
    }

    func testIdentityUsesNetBIOSNameWhenReverseDNSIsMissing() async {
        let result = await OUIVendorDatabase.identifyDeviceWithEvidence(
            ipAddress: "192.168.1.50", macAddress: "B8:27:EB:00:00:01", hostname: "",
            reverseDNS: { _ in nil }, netbiosName: { _ in "OFFICE-PC" }, onlineLookup: { _ in nil })
        XCTAssertEqual(result.resolvedHostname, "OFFICE-PC")
        XCTAssertTrue(result.evidence.contains { $0.source == "NetBIOS name (self-reported)" })
    }

    // MARK: TLS certificates

    /// Self-signed P-256 certificate for CN=netscan-test, valid 2025-01-01 to 2030-06-15 12:00:00 UTC.
    private let certificate = Data(base64Encoded: "MIIBgzCCASmgAwIBAgIUZNxMTQmZhwM8VZOtB4QboPKUrpUwCgYIKoZIzj0EAwIwFzEVMBMGA1UEAwwMbmV0c2Nhbi10ZXN0MB4XDTI1MDEwMTAwMDAwMFoXDTMwMDYxNTEyMDAwMFowFzEVMBMGA1UEAwwMbmV0c2Nhbi10ZXN0MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEjTCQAyZzJ1ISwGwkxZ28M0l84I/3Jt3vHZnmjzGkTy1R0Cbr8uELTeZ1PUvrTmhn1Vps+mTzVDomiK3SdbiI7KNTMFEwHQYDVR0OBBYEFBJMEWjTRqF4ujmZ44BX/bpWDZqYMB8GA1UdIwQYMBaAFBJMEWjTRqF4ujmZ44BX/bpWDZqYMA8GA1UdEwEB/wQFMAMBAf8wCgYIKoZIzj0EAwIDSAAwRQIhANxNuua/n45zaoKMJ7l0aEucN/n2OZ1kpMZZZhbO9wWuAiA2RdYiILPC8kNsLNaRNIhZ7BM754HSyHPYKHBIqLwegA==")!

    func testCertificateExpiryIsReadFromDER() {
        XCTAssertEqual(TLSInspector.notAfter(der: certificate), Date(timeIntervalSince1970: 1_907_755_200))
        XCTAssertNil(TLSInspector.notAfter(der: Data([0x30, 0x03, 0x02, 0x01, 0x01])))
        XCTAssertNil(TLSInspector.notAfter(der: Data()))
    }

    func testCertificateTimesRejectInvalidDates() {
        XCTAssertEqual(TLSInspector.time(tag: 0x18, text: "20500101000000Z"), Date(timeIntervalSince1970: 2_524_608_000))
        XCTAssertEqual(TLSInspector.time(tag: 0x17, text: "991231235959Z"), Date(timeIntervalSince1970: 946_684_799))
        XCTAssertNil(TLSInspector.time(tag: 0x17, text: "250230000000Z"))
        XCTAssertNil(TLSInspector.time(tag: 0x17, text: "250101000000+0100"))
        XCTAssertNil(TLSInspector.time(tag: 0x18, text: "250101000000Z"))
    }

    func testCertificateFindingsFlagExpiryAndSelfSigning() {
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        let expired = TLSCertificateReport(subject: "router", notAfter: now.addingTimeInterval(-3 * 86_400), selfSigned: true, trusted: false)
        XCTAssertEqual(expired.daysRemaining(now: now), -3)
        XCTAssertTrue(expired.findings(now: now)[0].contains("expired 3 days ago"))
        XCTAssertTrue(expired.findings(now: now).contains { $0.hasPrefix("Self-signed") })
        let good = TLSCertificateReport(subject: "nas", notAfter: now.addingTimeInterval(200 * 86_400), selfSigned: false, trusted: true)
        XCTAssertEqual(good.findings(now: now), ["Trusted by iOS and not close to expiry."])
    }

    // MARK: Troubleshooter

    private func checks(router: Double? = 2, dns: DNSLookupResult? = DNSLookupResult(query: "www.apple.com", addresses: ["17.253.144.10"], milliseconds: 20),
                        captive: CaptivePortalState = .open) -> TroubleshootChecks {
        TroubleshootChecks(router: { _ in router }, dns: { _ in dns }, internet: { 15 },
                           captivePortal: { captive }, publicIP: { "203.0.113.7" }, downloadMbps: { 80 })
    }

    func testTroubleshooterPassesWhenEverythingAnswers() async {
        let results = await NetworkTroubleshooter.run(gateway: "192.168.1.1", checks: checks()) { _ in }
        XCTAssertEqual(results.map(\.status), Array(repeating: .passed, count: 6))
        XCTAssertEqual(NetworkTroubleshooter.summary(results), "All checks passed.")
    }

    func testTroubleshooterNamesFirstFailureAndSkipsDependents() async {
        var reported: [TroubleshootStep] = []
        let results = await NetworkTroubleshooter.run(gateway: "192.168.1.1", checks: checks(router: nil)) { reported.append($0.step) }
        XCTAssertEqual(reported, TroubleshootStep.allCases)
        XCTAssertEqual(results[0].status, .failed)
        XCTAssertTrue(results.dropFirst().allSatisfy { $0.status == .skipped })
        XCTAssertTrue(NetworkTroubleshooter.summary(results).hasPrefix("Problem found at \"Router reachable\""))
    }

    func testTroubleshooterKeepsInternetCheckWhenOnlyDNSFails() async {
        let results = await NetworkTroubleshooter.run(gateway: "192.168.1.1", checks: checks(dns: nil)) { _ in }
        XCTAssertEqual(results.map(\.status), [.passed, .failed, .passed, .skipped, .skipped, .skipped])
    }

    func testTroubleshooterWithoutLANStillTestsInternetAndFlagsCaptivePortal() async {
        let results = await NetworkTroubleshooter.run(gateway: "", checks: checks(captive: .captive)) { _ in }
        XCTAssertEqual(results.map(\.status), [.skipped, .passed, .passed, .failed, .skipped, .skipped])
        XCTAssertTrue(NetworkTroubleshooter.summary(results).contains("No captive portal"))
    }

    func testTroubleshooterParsingHelpers() {
        XCTAssertEqual(NetworkTroubleshooter.parseTraceIP("fl=1\nip=203.0.113.7\nts=1"), "203.0.113.7")
        XCTAssertEqual(NetworkTroubleshooter.parseTraceIP("ip=2001:db8::1\n"), "2001:db8::1")
        XCTAssertNil(NetworkTroubleshooter.parseTraceIP("ip=<html>"))
        XCTAssertEqual(NetworkTroubleshooter.megabitsPerSecond(bytes: 5_000_000, seconds: 2), 20)
        XCTAssertNil(NetworkTroubleshooter.megabitsPerSecond(bytes: 0, seconds: 1))
        XCTAssertEqual(NetworkTroubleshooter.captivePortalState(statusCode: 200, body: "<HTML><TITLE>Success</TITLE></HTML>"), .open)
        XCTAssertEqual(NetworkTroubleshooter.captivePortalState(statusCode: 302, body: nil), .captive)
        XCTAssertEqual(NetworkTroubleshooter.captivePortalState(statusCode: 200, body: "<title>Hotel login</title>"), .captive)
        XCTAssertEqual(NetworkTroubleshooter.captivePortalState(statusCode: nil, body: nil), .unreachable)
    }

    // MARK: DNS

    func testDNSLookupRecognizesAddressesAndResolvesLocalhost() async {
        XCTAssertTrue(DNSLookupService.isIPAddress("192.168.1.1"))
        XCTAssertTrue(DNSLookupService.isIPAddress("fe80::1"))
        XCTAssertFalse(DNSLookupService.isIPAddress("www.apple.com"))
        XCTAssertFalse(DNSLookupService.isIPAddress("999.1.1.1"))
        let result = await DNSLookupService.resolve("localhost", timeout: 3)
        XCTAssertTrue(result?.addresses.contains("127.0.0.1") == true)
        let empty = await DNSLookupService.resolve("  ", timeout: 3)
        XCTAssertNil(empty)
    }

    // MARK: Network fingerprint and watch mode

    private func gateway(host: String = "router.lan", server: String = "lighttpd") -> NetworkDevice {
        var device = NetworkDevice(ipAddress: "192.168.1.1", hostname: host, vendor: "TP-Link", isGateway: true)
        device.evidence = [IdentityEvidence(source: "HTTP Server header (self-reported)", observation: server)]
        return device
    }

    func testRouterIdentityConfirmsOnlyAMatchingRouter() {
        let store = DeviceInventory(file: nil)
        let identity = DeviceInventory.routerIdentity(gateway())
        XCTAssertTrue(identity.contains("host:router.lan"))
        XCTAssertEqual(DeviceInventory.routerIdentity(NetworkDevice(ipAddress: "192.168.1.1", vendor: "Network Device")), "")
        XCTAssertFalse(store.confirmRouter(identity, network: "home"), "The first sighting is stored, not trusted")
        XCTAssertTrue(store.confirmRouter(identity, network: "home"))
        XCTAssertFalse(store.confirmRouter(DeviceInventory.routerIdentity(gateway(server: "nginx")), network: "home"))
        XCTAssertTrue(store.confirmRouter(identity, network: "home"), "A different router never replaces the stored one")
        XCTAssertFalse(store.confirmRouter("", network: "home"))
    }

    func testInventoryWithoutRouterIdentitiesStillLoads() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("netscan-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data(#"{"version":1,"records":{},"scans":[]}"#.utf8).write(to: file)
        let store = DeviceInventory(file: file)
        XCTAssertNil(store.storageMessage)
        XCTAssertFalse(store.hasRouterIdentity(network: "home"))
    }

    func testFingerprintMakesHiddenNetworkCertainOnLaterScans() {
        let store = DeviceInventory(file: nil)
        let first = DeviceListViewModel(observeNetwork: false, inventory: store)
        first.devices = [gateway()]
        first.refreshNetworkFingerprint()
        XCTAssertFalse(first.networkIsCertain)
        XCTAssertNotNil(first.networkProfileNote)
        let second = DeviceListViewModel(observeNetwork: false, inventory: store)
        second.devices = [gateway()]
        second.refreshNetworkFingerprint()
        XCTAssertTrue(second.networkIsCertain)
        let changed = DeviceListViewModel(observeNetwork: false, inventory: store)
        changed.devices = [gateway(host: "other-router")]
        changed.refreshNetworkFingerprint()
        XCTAssertFalse(changed.networkIsCertain)
    }

    func testNewDeviceAlertsSkipBaselineKnownRecognizedAndLocalDevices() {
        let store = DeviceInventory(file: nil)
        let known = store.associate(NetworkDevice(ipAddress: "192.168.1.10", hostname: "tv.lan"), network: "home", certainNetwork: true)
        XCTAssertTrue(DeviceListViewModel.newDeviceAlerts(devices: [known], history: []).isEmpty, "The first scan is a baseline")
        store.recordScan(id: UUID(), network: "home", devices: [known])
        let stranger = store.associate(NetworkDevice(ipAddress: "192.168.1.77", hostname: "esp-1234.lan"), network: "home", certainNetwork: true)
        var labeled = store.associate(NetworkDevice(ipAddress: "192.168.1.78", hostname: "plug.lan"), network: "home", certainNetwork: true)
        labeled.annotation.recognized = true
        let local = NetworkDevice(ipAddress: "192.168.1.5", isLocalDevice: true)
        let alerts = DeviceListViewModel.newDeviceAlerts(devices: [known, stranger, labeled, local], history: store.history(network: "home"))
        XCTAssertEqual(alerts.map(\.ipAddress), ["192.168.1.77"])
    }

    @MainActor
    func testWatchModeSchedulesRescansAndAlertsOnlyForUnseenDevices() {
        let model = DeviceListViewModel(observeNetwork: false, inventory: DeviceInventory(file: nil))
        let notifier = RecordingNotifier()
        model.notifier = notifier
        model.identityLookup = { _ in ("Network Device", .unknown, nil) }
        model.setWatchMode(true)
        defer {
            model.stopScan()
            model.setWatchMode(false)
        }
        XCTAssertEqual(notifier.authorizationRequests, 1)
        XCTAssertNotNil(model.nextWatchScan)
        model.pauseWatch()
        XCTAssertNil(model.nextWatchScan)
        model.resumeWatch()
        XCTAssertNotNil(model.nextWatchScan)

        model.devices = [NetworkDevice(ipAddress: "127.0.0.1", hostname: "known.lan")]
        model.isScanning = true
        model.completeDiscovery(run: model.activeScanID)
        XCTAssertTrue(notifier.notified.isEmpty, "The first scan is a baseline")
        XCTAssertNil(model.latestNewDeviceAlert)

        model.devices.append(NetworkDevice(ipAddress: "127.0.0.2", hostname: "stranger.lan"))
        model.isScanning = true
        model.completeDiscovery(run: model.activeScanID)
        XCTAssertEqual(notifier.notified.map { $0.map(\.ipAddress) }, [["127.0.0.2"]])
        XCTAssertNotNil(model.latestNewDeviceAlert)
        XCTAssertNotNil(model.nextWatchScan, "A completed scan schedules the next one")
    }

    func testScheduledWatchScansWaitWhileADeviceIsOpen() {
        let model = DeviceListViewModel(observeNetwork: false, inventory: DeviceInventory(file: nil))
        XCTAssertFalse(model.canStartWatchScan, "No LAN")
        model.isLANConnected = true
        XCTAssertTrue(model.canStartWatchScan)
        model.holdWatchScans(true)
        XCTAssertFalse(model.canStartWatchScan)
        model.holdWatchScans(false)
        XCTAssertTrue(model.canStartWatchScan)
        model.isScanning = true
        XCTAssertFalse(model.canStartWatchScan)
    }

    func testNewDeviceMessageNamesAtMostTwoDevices() {
        XCTAssertNil(NewDeviceNotifier.message(for: []))
        let devices = (1...3).map { NetworkDevice(ipAddress: "192.168.1.\($0)", hostname: "host\($0).lan") }
        let message = NewDeviceNotifier.message(for: devices)
        XCTAssertEqual(message?.title, "3 new devices on your network")
        XCTAssertTrue(message?.body.hasPrefix("host1.lan, host2.lan and 1 more") == true)
        XCTAssertFalse(message?.body.contains("192.168.1.") == true)
    }

    // MARK: Export

    private func labeledDevice() -> NetworkDevice {
        var device = NetworkDevice(ipAddress: "192.168.1.31", hostname: "=cmd.lan", vendor: "GoodWe", openPorts: [23])
        device.annotation.name = "Inverter, garage"
        device.annotation.notes = "Says \"hi\""
        return device
    }

    func testCSVExportRedactsAndEscapes() {
        let redacted = InventoryExport.csv(devices: [labeledDevice()])
        XCTAssertFalse(redacted.contains("192.168.1.31"))
        XCTAssertFalse(redacted.contains("Inverter"))
        XCTAssertTrue(redacted.contains("Telnet-associated port 23 reachable"))
        let full = InventoryExport.csv(devices: [labeledDevice()], redacted: false)
        XCTAssertTrue(full.contains("\"Inverter, garage\""))
        XCTAssertTrue(full.contains("\"Says \"\"hi\"\"\""))
        XCTAssertTrue(full.contains(",'=cmd.lan,"), "Formula-like values must be neutralized")
        XCTAssertEqual(InventoryExport.csvField("-1"), "'-1")
        XCTAssertEqual(InventoryExport.csvField("line one\r\nline two"), "\"line one\r\nline two\"")
        XCTAssertEqual(InventoryExport.csvField("plain"), "plain")
    }

    func testJSONExportRedactsIdentifyingFields() throws {
        let redacted = InventoryExport.json(devices: [labeledDevice()], history: [])
        XCTAssertFalse(redacted.contains("192.168.1.31"))
        XCTAssertFalse(redacted.contains("Inverter"))
        let object = try JSONSerialization.jsonObject(with: Data(redacted.utf8)) as? [String: Any]
        XCTAssertEqual(object?["redacted"] as? Bool, true)
        let full = InventoryExport.json(devices: [labeledDevice()], history: [], redacted: false)
        XCTAssertTrue(full.contains("192.168.1.31"))
        XCTAssertTrue(InventoryExport.render(.text, devices: [], history: []).hasPrefix("NetScan network report"))
    }
}

private final class RecordingNotifier: NewDeviceNotifying {
    var authorizationRequests = 0
    var notified: [[NetworkDevice]] = []

    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        authorizationRequests += 1
        completion(true)
    }

    func notify(newDevices: [NetworkDevice]) {
        notified.append(newDevices)
    }
}
