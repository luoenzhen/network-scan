import XCTest
import Foundation
import Darwin
import Network
import Combine
@testable import NetScanCore

final class InventoryTests: XCTestCase {
    private func device(_ ip: String = "192.168.1.31", host: String = "hf-a21.lan", mac: String = "Unknown MAC") -> NetworkDevice {
        NetworkDevice(ipAddress: ip, macAddress: mac, hostname: host, vendor: "Network Device")
    }
    private func label(_ device: NetworkDevice, store: DeviceInventory, network: String = "home") -> NetworkDevice {
        var device = store.associate(device, network: network, certainNetwork: true)
        var annotation = DeviceAnnotation()
        annotation.name = "GoodWe Inverter"
        annotation.notes = "Installed outside"
        annotation.location = "Garage"
        annotation.recognized = true
        store.saveAnnotation(annotation, device: device, network: network)
        device.annotation = annotation
        device.savedMatch = .current
        return device
    }

    func testMACMatchPersistsLabelAcrossAddressChangeAndNetworkIsScoped() {
        let store = DeviceInventory(file: nil)
        let original = label(device(mac: "28:9C:6E:00:00:01"), store: store)
        let next = store.associate(device("192.168.1.40", mac: "28-9C-6E-00-00-01"), network: "home", certainNetwork: true)
        XCTAssertEqual(next.inventoryID, original.inventoryID)
        XCTAssertEqual(next.displayName, "GoodWe Inverter")
        XCTAssertEqual(next.savedMatch, .mac)
        XCTAssertTrue(next.annotation.recognized)
        XCTAssertTrue(store.associate(device(mac: "28:9C:6E:00:00:01"), network: "other", certainNetwork: true).annotation.isEmpty)
    }

    func testHostnameAndAddressAssociationsDoNotTransferRecognition() {
        let store = DeviceInventory(file: nil)
        let original = label(device(), store: store)
        let hostMatch = store.associate(device("192.168.1.42"), network: "home", certainNetwork: true)
        XCTAssertEqual(hostMatch.inventoryID, original.inventoryID)
        XCTAssertEqual(hostMatch.savedMatch, .hostname)
        XCTAssertFalse(hostMatch.annotation.recognized)
        let addressMatch = store.associate(device("192.168.1.42", host: "192.168.1.42"), network: "home", certainNetwork: true)
        XCTAssertEqual(addressMatch.savedMatch, .address)
        XCTAssertFalse(addressMatch.annotation.recognized)
        XCTAssertEqual(addressMatch.annotation.notes, "Installed outside")
    }

    func testConflictingMACAndChangedHostnameDoNotInheritLabels() {
        let store = DeviceInventory(file: nil)
        let original = label(device(mac: "28:9C:6E:00:00:01"), store: store)
        let replacement = store.associate(device(mac: "28:9C:6E:00:00:02"), network: "home", certainNetwork: true)
        XCTAssertNotEqual(replacement.inventoryID, original.inventoryID)
        XCTAssertTrue(replacement.annotation.isEmpty)
        let changedHost = store.associate(device(host: "different.lan"), network: "home", certainNetwork: true)
        XCTAssertTrue(changedHost.annotation.isEmpty)
    }

    func testDuplicateHostnamesAndUncertainNetworkCannotTransferRecognition() {
        let store = DeviceInventory(file: nil)
        _ = label(device(), store: store)
        let duplicate = store.associate(device("192.168.1.80"), network: "home", certainNetwork: true, duplicateHostnames: ["hf-a21.lan"])
        XCTAssertTrue(duplicate.annotation.isEmpty)
        let weak = store.associate(device(), network: "home", certainNetwork: false)
        XCTAssertEqual(weak.savedMatch, .address)
        XCTAssertFalse(weak.annotation.recognized)
    }

    func testPersistenceReloadPruningAndCorruptFilePreservation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let file = directory.appendingPathComponent("inventory.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DeviceInventory(file: file)
        let saved = label(device(), store: store)
        for _ in 0..<23 { store.recordScan(id: UUID(), network: "home", devices: [saved]) }
        store.flush()
        let restored = DeviceInventory(file: file)
        XCTAssertNil(restored.storageMessage)
        XCTAssertEqual(restored.allHistory.count, 20)
        XCTAssertEqual(restored.associate(device(), network: "home", certainNetwork: true).annotation.name, "GoodWe Inverter")
        let bad = Data("not inventory data".utf8)
        try bad.write(to: file)
        let corrupt = DeviceInventory(file: file)
        XCTAssertNotNil(corrupt.storageMessage)
        corrupt.recordScan(id: UUID(), network: "home", devices: [])
        corrupt.flush()
        XCTAssertEqual(try Data(contentsOf: file), bad)
    }

    func testHistoryRequiresComparablePortCoverageAndKeepsCancelledChecks() {
        let store = DeviceInventory(file: nil)
        var first = label(device(mac: "28:9C:6E:00:00:01"), store: store)
        first.openPorts = [23]
        first.assessedPorts = [23]
        first.serviceCheckState = .checked
        store.recordScan(id: UUID(), network: "home", devices: [first])
        let previous = store.allHistory[0]
        var next = store.associate(device("192.168.1.42", mac: "28:9C:6E:00:00:01"), network: "home", certainNetwork: true)
        let id = UUID()
        store.recordScan(id: id, network: "home", devices: [next])
        var changes = store.allHistory[0].changes(since: previous)
        XCTAssertEqual(changes.filter { $0.title == "Address changed" }.count, 1)
        XCTAssertFalse(changes.contains { $0.title == "Port no longer detected" })
        next.assessedPorts = [23]
        store.updateScan(id: id, devices: [next], identity: .cancelled, services: .completed)
        changes = store.allHistory[0].changes(since: previous)
        XCTAssertTrue(changes.contains { $0.title == "Port no longer detected" })
        XCTAssertEqual(store.allHistory[0].identityCoverage, .cancelled)
        let count = store.allHistory.count
        store.updateScan(id: UUID(), devices: [], identity: .completed, services: .completed)
        XCTAssertEqual(store.allHistory.count, count)
    }

    func testNetworkScopeIgnoresPhoneDHCPChangeAndSubnetFiltering() {
        var interface = NetworkInterfaceInfo(ipAddress: "192.168.87.2", cidrPrefix: 24, gatewayIP: "192.168.87.1", ssid: "Home")
        let scope = DeviceInventory.networkScope(interface)
        interface.ipAddress = "192.168.87.99"
        XCTAssertEqual(DeviceInventory.networkScope(interface), scope)
        XCTAssertTrue(interface.containsIPv4("192.168.87.31"))
        XCTAssertFalse(interface.containsIPv4("192.168.88.31"))
        XCTAssertFalse(interface.containsIPv4("999.168.87.31"))
    }

    @MainActor
    func testProductionFallbackNetworkIsUncertainAndSyntheticBSSIDIsExcluded() {
        let interface = NetworkInterfaceInfo(ipAddress: "192.168.87.2", ssid: "Local Wi-Fi Network",
                                             bssid: "02:00:00:00:00:00", isConnected: true, isLAN: true)
        let model = DeviceListViewModel(observeNetwork: false)
        model.handleInterfaceChange(interface, pathResolved: false)
        XCTAssertFalse(model.networkIsCertain)
        XCTAssertFalse(DeviceInventory.networkScope(interface).contains("02:00:00:00:00:00"))
    }

    @MainActor
    func testBonjourFirstThenLocalRecordPreservesStrongerFields() {
        let model = DeviceListViewModel(observeNetwork: false)
        model.devices = [device("192.168.1.2", host: "phone.local")]
        let id = model.devices[0].id
        let local = NetworkDevice(ipAddress: "192.168.1.2", macAddress: "00:17:F2:00:00:01", hostname: "iPhone",
                                  vendor: "Apple Inc.", deviceType: .phone, isLocalDevice: true)
        model.mergeDiscoveredDevice(local)
        XCTAssertEqual(model.devices[0].id, id)
        XCTAssertTrue(model.devices[0].isLocalDevice)
        XCTAssertEqual(model.devices[0].hostname, "phone.local")
        XCTAssertEqual(model.devices[0].vendor, "Apple Inc.")
        XCTAssertTrue(model.devices[0].hasKnownMACAddress)
    }

    func testDuplicateMACsDoNotCoalesceSeparateObservations() {
        let store = DeviceInventory(file: nil)
        let mac = "28:9C:6E:00:00:01"
        let first = store.associate(device(mac: mac), network: "home", certainNetwork: true, duplicateMACs: ["289c6e000001"])
        let second = store.associate(device("192.168.1.32", mac: mac), network: "home", certainNetwork: true, duplicateMACs: ["289c6e000001"])
        XCTAssertNotEqual(first.inventoryID, second.inventoryID)
    }

    func testSaveFailureIsSurfacedAndEditsRemainInMemory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let blocker = directory.appendingPathComponent("file-not-folder")
        try Data("keep".utf8).write(to: blocker)
        let store = DeviceInventory(file: blocker.appendingPathComponent("inventory.json"))
        _ = label(device(), store: store)
        XCTAssertFalse(store.flush())
        XCTAssertNotNil(store.storageMessage)
        XCTAssertEqual(store.associate(device(), network: "home", certainNetwork: true).annotation.name, "GoodWe Inverter")
        XCTAssertEqual(try String(contentsOf: blocker), "keep")
        try FileManager.default.removeItem(at: blocker)
        XCTAssertTrue(store.flush())
        XCTAssertNil(store.storageMessage)
        let restored = DeviceInventory(file: blocker.appendingPathComponent("inventory.json"))
        XCTAssertEqual(restored.associate(device(), network: "home", certainNetwork: true).annotation.name, "GoodWe Inverter")
    }

    func testUnknownOUIWithRecognizableHostnameIsNotOUIEvidence() async {
        let result = await OUIVendorDatabase.identifyDeviceWithEvidence(ipAddress: nil, macAddress: "FE:00:00:00:00:01",
                                                                      hostname: "raspberrypi.local", reverseDNS: { _ in nil }, onlineLookup: { _ in nil })
        XCTAssertEqual(result.vendor, "Raspberry Pi Foundation")
        XCTAssertFalse(result.evidence.contains { $0.source.contains("OUI") })
        XCTAssertTrue(result.evidence.contains { $0.source == "Hostname classification (inferred)" })
    }

    func testImmediateConnectFailureIsNotAnOpenPort() {
        SubnetScannerService().probeHost(ip: "255.255.255.255", timeout: 0.1) { XCTAssertNil($0) }
    }

    func testInconclusiveFirstSocketDoesNotHideSecondResponse() {
        var calls = 0
        let result = SubnetScannerService.waitForHostResponse(
            descriptors: [pollfd(fd: 10, events: Int16(POLLOUT), revents: 0), pollfd(fd: 11, events: Int16(POLLOUT), revents: 0)],
            ports: [80, 443], timeout: 0.3,
            pollSockets: { descriptors, milliseconds in
                calls += 1
                XCTAssertGreaterThan(milliseconds, 0)
                descriptors[0].revents = Int16(POLLOUT)
                return 1
            }, socketError: { $0 == 10 ? EHOSTUNREACH : 0 })
        XCTAssertEqual(calls, 2)
        XCTAssertTrue(result.alive)
        XCTAssertEqual(result.openPort, 443)
    }

    func testRedactionOmitsSensitiveStringsStructurally() {
        let store = DeviceInventory(file: nil)
        var device = label(self.device(mac: "28:9C:6E:00:00:01"), store: store)
        device.annotation.notes = "password-secret\n192.168.87.31 <script>alert(1)</script>"
        device.evidence = [IdentityEvidence(source: "HTTP header", observation: "private-evidence-secret")]
        device.openPorts = [23]
        store.recordScan(id: UUID(), network: "ssid-secret|bssid-secret", devices: [device])
        let report = NetworkReport.text(devices: [device], history: store.allHistory)
        for secret in ["GoodWe", "Installed outside", "Garage", "password-secret", "hf-a21", "192.168", "28:9C", "private-evidence", "ssid-secret", "bssid-secret", "script"] {
            XCTAssertFalse(report.contains(secret), secret)
        }
        XCTAssertTrue(report.contains("Device 1"))
        XCTAssertTrue(report.contains("Telnet"))
        XCTAssertTrue(NetworkReport.text(devices: [device], history: store.allHistory, redacted: false).contains("password-secret"))
    }

    func testRecognitionDoesNotSuppressActionableRisks() {
        var device = self.device()
        device.annotation.recognized = true
        device.openPorts = [23]
        device.evidence = [IdentityEvidence(source: "HTTP authentication", observation: "Basic over HTTP")]
        XCTAssertEqual(device.securityFindings.filter(\.requiresReview).count, 2)
        XCTAssertTrue(device.securityFindings.allSatisfy { !$0.recommendedAction.isEmpty })
    }

    func testEvidenceDistinguishesOUIFromDNSObservations() async {
        let result = await OUIVendorDatabase.identifyDeviceWithEvidence(ipAddress: "192.168.1.31", macAddress: "B8:27:EB:00:00:01", hostname: "", reverseDNS: { _ in "office-pi.local" })
        XCTAssertTrue(result.evidence.contains { $0.source.hasPrefix("Reverse DNS") && $0.observation == "office-pi.local" })
        XCTAssertTrue(result.evidence.contains { $0.source == "Local OUI allocation" && $0.observation.contains("component") == false && $0.observation.contains("embedded module") })
    }

    func testBonjourAddressParserRejectsInvalidAndIPv6Data() {
        XCTAssertNil(BonjourDiscoveryService.ipv4Address(Data()))
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        inet_pton(AF_INET, "192.168.1.31", &address.sin_addr)
        XCTAssertEqual(BonjourDiscoveryService.ipv4Address(withUnsafeBytes(of: &address) { Data($0) }), "192.168.1.31")
        address.sin_family = sa_family_t(AF_INET6)
        XCTAssertNil(BonjourDiscoveryService.ipv4Address(withUnsafeBytes(of: &address) { Data($0) }))
    }

    @MainActor
    func testBonjourPublishesBrowsesAndResolvesIPv4Service() async {
        let name = "NetScan-Test-\(UUID().uuidString)"
        let advertised = NetService(domain: "local.", type: "_http._tcp.", name: name, port: 32123)
        let browser = BonjourDiscoveryService()
        let resolved = expectation(description: "published service resolved through Bonjour")
        resolved.assertForOverFulfill = false
        browser.startBrowsing { observation in
            if observation.name == name {
                XCTAssertFalse(observation.address.isEmpty)
                XCTAssertFalse(observation.hostname.isEmpty)
                XCTAssertEqual(observation.port, 32123)
                resolved.fulfill()
            }
        }
        advertised.publish()
        defer { advertised.stop(); browser.stopBrowsing() }
        await fulfillment(of: [resolved], timeout: 8)
    }

    @MainActor
    func testCompletedDiscoverySurvivesCancelledEnrichment() {
        let model = DeviceListViewModel(observeNetwork: false)
        model.devices = [device()]
        model.identityLookup = { _ in ("Network Device", .unknown, nil) }
        model.isScanning = true
        model.completeDiscovery(run: model.activeScanID)
        XCTAssertEqual(model.history.count, 1)
        model.stopScan()
        XCTAssertEqual(model.history.count, 1)
        XCTAssertEqual(model.history[0].identityCoverage, .cancelled)
        XCTAssertEqual(model.history[0].serviceCoverage, .cancelled)
    }

    @MainActor
    func testStaleAndOutOfSubnetBonjourCallbacksAreIgnored() {
        let model = DeviceListViewModel(observeNetwork: false)
        let interface = NetworkInterfaceInfo(ipAddress: "192.168.1.2")
        model.isScanning = true
        let observed = BonjourObservation(address: "192.168.1.31", hostname: "hf-a21.lan", name: "Inverter", type: "_http._tcp.", port: 80)
        model.acceptBonjour(observed, interface: interface, run: UUID())
        XCTAssertTrue(model.devices.isEmpty)
        var outside = observed
        outside.address = "192.168.2.31"
        model.acceptBonjour(outside, interface: interface, run: model.activeScanID)
        XCTAssertTrue(model.devices.isEmpty)
        model.acceptBonjour(observed, interface: interface, run: model.activeScanID)
        model.acceptBonjour(observed, interface: interface, run: model.activeScanID)
        XCTAssertEqual(model.devices.count, 1)
        XCTAssertEqual(model.devices[0].evidence.count, 1)
        XCTAssertTrue(model.devices[0].openPorts.isEmpty, "Advertisements are not reachability checks")
        model.stopScan()
        model.acceptBonjour(observed, interface: interface, run: model.activeScanID)
        XCTAssertEqual(model.devices.count, 1)
        XCTAssertTrue(model.history.isEmpty, "Cancelled discovery must not become a completed scan")
    }

    func testDiscoveryFindsNonHTTPListenerWithinOneTimeout() throws {
        let listener = try NWListener(using: .tcp, on: .any)
        let ready = expectation(description: "listener ready")
        listener.stateUpdateHandler = { if case .ready = $0 { ready.fulfill() } }
        listener.newConnectionHandler = { $0.cancel() }
        listener.start(queue: .global())
        defer { listener.cancel() }
        wait(for: [ready], timeout: 2)
        let port = try XCTUnwrap(listener.port)
        let start = Date()
        SubnetScannerService().probeHost(ip: "127.0.0.1", timeout: 0.3, ports: [port.rawValue]) { device in
            XCTAssertNotNil(device)
            XCTAssertTrue(device?.openPorts.contains(Int(port.rawValue)) == true)
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.6)
    }
}
