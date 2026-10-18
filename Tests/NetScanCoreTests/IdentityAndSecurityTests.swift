import XCTest
import Foundation
import Combine
@testable import NetScanCore

final class IdentityAndSecurityTests: XCTestCase {
    func testKnownManufacturerStillResolvesMissingHostname() async {
        let result = await OUIVendorDatabase.identifyDeviceAsync(
            ipAddress: "192.168.1.10", macAddress: "B8:27:EB:00:00:01", hostname: "192.168.1.10",
            reverseDNS: { _ in "office-pi.local" })
        XCTAssertEqual(result.vendor, "Raspberry Pi Foundation")
        XCTAssertEqual(result.deviceType, .computer)
        XCTAssertEqual(result.resolvedHostname, "office-pi.local")
        let noName = await OUIVendorDatabase.identifyDeviceAsync(
            ipAddress: "192.168.1.10", macAddress: "B8:27:EB:00:00:01", hostname: "Unknown",
            reverseDNS: { _ in nil })
        XCTAssertEqual(noName.vendor, "Raspberry Pi Foundation")
        XCTAssertEqual(noName.deviceType, .computer)
        XCTAssertNil(noName.resolvedHostname)
    }

    @MainActor
    func testOlderAutomaticLookupCannotReplaceManualIdentity() async {
        let model = DeviceListViewModel(observeNetwork: false)
        model.devices = [NetworkDevice(ipAddress: "192.168.1.10", vendor: "Network Device")]
        let started = expectation(description: "automatic lookup suspended")
        let lock = NSLock()
        var pending: CheckedContinuation<(vendor: String, deviceType: DeviceType, resolvedHostname: String?), Never>?
        model.identityLookup = { _ in
            await withCheckedContinuation { continuation in
                lock.withLock { pending = continuation }
                started.fulfill()
            }
        }
        model.enrichVendorsOnline()
        await fulfillment(of: [started], timeout: 2)
        var updated = model.devices[0]
        updated.hostname = "manual-host.local"
        updated.vendor = "Manual Vendor"
        updated.deviceType = .computer
        model.updateDevice(updated, kind: .identity)
        let finished = expectation(description: "automatic result processed")
        let observation = model.$isUpdatingIdentities.filter { !$0 }.first().sink { _ in finished.fulfill() }
        defer { observation.cancel() }
        lock.withLock { pending }?.resume(returning: ("Old Vendor", .router, "old-host.local"))
        await fulfillment(of: [finished], timeout: 2)
        XCTAssertEqual(model.devices[0].hostname, "manual-host.local")
        XCTAssertEqual(model.devices[0].vendor, "Manual Vendor")
        XCTAssertEqual(model.devices[0].deviceType, .computer)
        model.stopDeviceUpdates()
    }

    @MainActor
    func testIdentityRetriesOnceAndPreservesHostnameWithoutMAC() async {
        let model = DeviceListViewModel(observeNetwork: false)
        model.devices = [NetworkDevice(ipAddress: "192.168.1.10", macAddress: "Unknown MAC", vendor: "Network Device")]
        model.identityRetryDelay = 0
        let lock = NSLock()
        var calls = 0
        let lookups = expectation(description: "one initial attempt and one retry")
        lookups.expectedFulfillmentCount = 2
        model.identityLookup = { _ in
            let count = lock.withLock { calls += 1; return calls }
            lookups.fulfill()
            return ("Network Device", .unknown, count == 1 ? "office-nas.local" : nil)
        }
        model.enrichVendorsOnline()
        await fulfillment(of: [lookups], timeout: 2)
        await Task.yield()
        XCTAssertEqual(lock.withLock { calls }, 2)
        XCTAssertEqual(model.devices[0].hostname, "office-nas.local")
        XCTAssertEqual(model.devices[0].displayName, "office-nas.local")
        XCTAssertEqual(model.devices[0].identityAddressLabel, "Host:")
        XCTAssertEqual(model.devices[0].identityAddressValue, "office-nas.local")
        XCTAssertFalse(model.isUpdatingIdentities)
    }

    @MainActor
    func testResolvedIdentityIsNotRetriedAndTrafficIsPreserved() async {
        let model = DeviceListViewModel(observeNetwork: false)
        model.devices = [NetworkDevice(ipAddress: "192.168.1.10", macAddress: "Unknown MAC", vendor: "Network Device", totalBytesSent: 1024)]
        model.identityRetryDelay = 0
        let lookup = expectation(description: "initial identity lookup")
        let lock = NSLock()
        var calls = 0
        model.identityLookup = { _ in
            lock.withLock { calls += 1 }
            lookup.fulfill()
            return ("Raspberry Pi Foundation", .computer, "raspberrypi.local")
        }
        model.enrichVendorsOnline()
        await fulfillment(of: [lookup], timeout: 2)
        await Task.yield()
        XCTAssertEqual(lock.withLock { calls }, 1)
        XCTAssertEqual(model.devices[0].vendor, "Raspberry Pi Foundation")
        XCTAssertEqual(model.devices[0].deviceType, .computer)
        XCTAssertEqual(model.devices[0].totalBytesSent, 1024)
        model.stopDeviceUpdates()
    }

    @MainActor
    func testCancelledLookupCannotOverwriteNewNetworkWithSameIP() async {
        let model = DeviceListViewModel(observeNetwork: false)
        model.devices = [NetworkDevice(ipAddress: "192.168.1.10", vendor: "Network Device")]
        let started = expectation(description: "lookup suspended")
        let lock = NSLock()
        var pending: CheckedContinuation<(vendor: String, deviceType: DeviceType, resolvedHostname: String?), Never>?
        model.identityLookup = { _ in
            await withCheckedContinuation { continuation in
                lock.withLock { pending = continuation }
                started.fulfill()
            }
        }
        model.enrichVendorsOnline()
        await fulfillment(of: [started], timeout: 2)
        model.handleInterfaceChange(NetworkInterfaceInfo(), pathResolved: true)
        let replacement = NetworkDevice(ipAddress: "192.168.1.10", hostname: "new-network-host", vendor: "New Vendor")
        model.devices = [replacement]
        lock.withLock { pending }?.resume(returning: ("Old Vendor", .computer, "old-host.local"))
        await Task.yield()
        XCTAssertEqual(model.devices[0].id, replacement.id)
        XCTAssertEqual(model.devices[0].vendor, "New Vendor")
        XCTAssertEqual(model.devices[0].hostname, "new-network-host")
        XCTAssertFalse(model.isUpdatingIdentities)
    }

    @MainActor
    func testSecurityChecksAreBoundedAndCancellationDoesNotHang() async {
        let model = DeviceListViewModel(observeNetwork: false)
        model.devices = (1...5).map { _ in NetworkDevice(ipAddress: "127.0.0.1") }
        model.checkDeviceServices()
        XCTAssertEqual(model.activeServiceCheckCount, 2)
        XCTAssertEqual(model.devices.filter { $0.serviceCheckState == .checking }.count, 2)
        model.stopDeviceUpdates()
        XCTAssertEqual(model.activeServiceCheckCount, 0)
        XCTAssertTrue(model.devices.allSatisfy { $0.serviceCheckState == .notChecked })
        try? await Task.sleep(nanoseconds: 600_000_000)
        XCTAssertTrue(model.devices.allSatisfy { $0.serviceCheckState == .notChecked })
    }

    @MainActor
    func testAutomaticServiceMergePreservesPortsOutsideSubsetAndRemovesClosedSubset() {
        let model = DeviceListViewModel(observeNetwork: false)
        let device = NetworkDevice(ipAddress: "127.0.0.1", openPorts: [22, 23, 80, 443, 9000])
        model.devices = [device]
        model.mergeServiceCheck([PortScanResult(port: 445, serviceName: "SMB")], into: device.id)
        XCTAssertEqual(model.devices[0].openPorts, [22, 80, 443, 445, 9000])
        XCTAssertEqual(model.devices[0].serviceCheckState, .checked)
    }

    @MainActor
    func testManualPortResultsSupersedeInFlightAutomaticCheck() async {
        let model = DeviceListViewModel(observeNetwork: false)
        var device = NetworkDevice(ipAddress: "127.0.0.1")
        model.devices = [device]
        model.checkDeviceServices()
        device.openPorts = [22, 9000]
        device.serviceCheckState = .checked
        model.updateDevice(device, kind: .ports)
        try? await Task.sleep(nanoseconds: 600_000_000)
        XCTAssertEqual(model.devices[0].openPorts, [22, 9000])
        XCTAssertEqual(model.devices[0].serviceCheckState, .checked)
    }

    func testRiskRulesAreObservationsAndIgnoreNormalMissingMAC() {
        var device = NetworkDevice(ipAddress: "192.168.1.10", macAddress: "Unknown MAC", hostname: "office-mac.local", vendor: "Apple", openPorts: [22, 80, 443])
        XCTAssertTrue(device.securityFindings.isEmpty)
        device.openPorts = [21, 23, 139, 445, 3389]
        XCTAssertEqual(Set(device.securityFindings.map(\.id)), ["ftp", "telnet", "smb", "rdp"])
        XCTAssertTrue(device.securityFindings.allSatisfy(\.requiresReview))
        device.hostname = device.ipAddress
        device.vendor = "Network Device"
        device.openPorts = []
        XCTAssertEqual(device.securityFindings.map(\.id), ["identity"])
        XCTAssertFalse(device.securityFindings[0].requiresReview)
        XCTAssertEqual(device.serviceCheckState, .notChecked)
    }

    @MainActor
    func testStaleIdentityAndPortSnapshotsMergeOnlyTheirOwnFields() {
        let model = DeviceListViewModel(observeNetwork: false)
        var original = NetworkDevice(ipAddress: "127.0.0.1", hostname: "old-host", vendor: "Old Vendor", openPorts: [80])
        model.devices = [original]
        var current = original
        current.hostname = "new-host"
        current.vendor = "New Vendor"
        current.openPorts = [23, 443]
        current.serviceCheckState = .checked
        model.devices = [current]
        original.hostname = "resolved-host"
        model.updateDevice(original, kind: .identity)
        XCTAssertEqual(model.devices[0].openPorts, [23, 443])
        XCTAssertEqual(model.devices[0].serviceCheckState, .checked)
        original.openPorts = [22, 9000]
        model.updateDevice(original, kind: .ports)
        XCTAssertEqual(model.devices[0].hostname, "resolved-host")
        XCTAssertEqual(model.devices[0].openPorts, [22, 9000])
    }

    @MainActor
    func testCancelledManualScanDoesNotRemainChecking() {
        let detail = DeviceDetailViewModel(device: NetworkDevice(ipAddress: "127.0.0.1"))
        detail.runPortScan()
        XCTAssertEqual(detail.device.serviceCheckState, .checking)
        detail.stopPacketObserving()
        XCTAssertFalse(detail.isScanningPorts)
        XCTAssertEqual(detail.device.serviceCheckState, .notChecked)
    }

    func testHostnameIsUsedOnlyWhenMACUnavailable() {
        var device = NetworkDevice(ipAddress: "192.168.1.10", macAddress: "Unknown MAC", hostname: "printer.local")
        XCTAssertEqual(device.identityAddressValue, "printer.local")
        device.macAddress = "00:11:22:33:44:55"
        XCTAssertEqual(device.identityAddressLabel, "MAC:")
        XCTAssertEqual(device.identityAddressValue, "00:11:22:33:44:55")
        device.macAddress = "Unknown MAC"
        device.hostname = "Unknown"
        XCTAssertEqual(device.identityAddressValue, "Unresolved")
        XCTAssertNotEqual(device.displayName, "Unknown")
    }
}
