import XCTest
import Network
@testable import NetScanCore

final class RegressionTests: XCTestCase {
    func testVendorDictionaryInitializesAndMatchesBundledAssignments() {
        XCTAssertEqual(OUIVendorDatabase.lookup(macAddress: "00:1E:67:00:00:01")?.vendor, "Intel Corporation")
        XCTAssertEqual(OUIVendorDatabase.lookup(macAddress: "00:15:58:00:00:01")?.vendor, "Foxconn")
        XCTAssertEqual(OUIVendorDatabase.lookup(macAddress: "B8:27:EB:00:00:01")?.vendor, "Raspberry Pi Foundation")
        XCTAssertNil(OUIVendorDatabase.lookup(macAddress: "Unknown MAC"))
        XCTAssertNil(OUIVendorDatabase.lookup(macAddress: "Self (Current Device)"))
        XCTAssertNil(OUIVendorDatabase.lookup(macAddress: ""))
    }

    func testSubnetRangesAndBroadcastRespectPrefix() {
        let service = NetworkInterfaceService()
        let small = service.generateSubnetIPs(localIP: "192.168.4.180", cidr: 25)
        XCTAssertEqual(small.count, 126)
        XCTAssertEqual(small.first, "192.168.4.129")
        XCTAssertEqual(small.last, "192.168.4.254")
        let large = service.generateSubnetIPs(localIP: "192.168.5.10", cidr: 23)
        XCTAssertEqual(large.count, 510)
        XCTAssertEqual(large.first, "192.168.4.1")
        XCTAssertEqual(large.last, "192.168.5.254")
        XCTAssertEqual(NetworkInterfaceService.inferBroadcast(ip: "192.168.4.10", mask: "255.255.255.128"), "192.168.4.127")
        XCTAssertEqual(NetworkInterfaceService.inferBroadcast(ip: "192.168.4.10", mask: "255.255.254.0"), "192.168.5.255")
        XCTAssertEqual(NetworkInterfaceService.calculateCIDR(netmask: "0.0.0.0"), 0)
        XCTAssertEqual(NetworkInterfaceService.calculateCIDR(netmask: "255.255.255.255"), 32)
    }

    func testPointToPointSubnetsInvalidInputsAndScanCap() {
        let service = NetworkInterfaceService()
        XCTAssertEqual(service.generateSubnetIPs(localIP: "10.0.0.4", cidr: 31), ["10.0.0.4", "10.0.0.5"])
        XCTAssertEqual(service.generateSubnetIPs(localIP: "10.0.0.4", cidr: 32), ["10.0.0.4"])
        XCTAssertTrue(service.generateSubnetIPs(localIP: "1..2.3.4", cidr: 24).isEmpty)
        XCTAssertTrue(service.generateSubnetIPs(localIP: "300.1.1.1", cidr: 24).isEmpty)
        XCTAssertTrue(service.generateSubnetIPs(localIP: "10.0.0.1", cidr: -1).isEmpty)
        XCTAssertTrue(service.generateSubnetIPs(localIP: "10.0.0.1", cidr: 33).isEmpty)
        let capped = service.generateSubnetIPs(localIP: "10.200.100.50", cidr: 8)
        XCTAssertEqual(capped.count, 4096)
        XCTAssertTrue(capped.contains("10.200.100.50"))
        XCTAssertTrue(capped.allSatisfy { $0.hasPrefix("10.") })
    }

    func testInterfaceIdentityChangesWithLocalAddress() {
        var first = NetworkInterfaceInfo(ipAddress: "192.168.1.2", isConnected: true, isLAN: true)
        var second = first
        second.ipAddress = "192.168.2.2"
        XCTAssertNotEqual(first.networkIdentifier, second.networkIdentifier)
        first.cidrPrefix = -1
        XCTAssertEqual(first.estimatedHostCount, 0)
        first.cidrPrefix = 31
        XCTAssertEqual(first.estimatedHostCount, 2)
    }

    @MainActor
    func testDetailUpdatesDoNotOverwriteTrafficOrAnotherScan() {
        let previousSetting = UserDefaults.standard.object(forKey: "autoRefreshOnLaunch")
        UserDefaults.standard.set(false, forKey: "autoRefreshOnLaunch")
        defer { UserDefaults.standard.set(previousSetting, forKey: "autoRefreshOnLaunch") }
        let model = DeviceListViewModel()
        var current = NetworkDevice(ipAddress: "192.168.1.2", totalBytesSent: 500)
        model.devices = [current]
        var updated = current
        updated.vendor = "Resolved Vendor"
        updated.totalBytesSent = 1
        model.updateDevice(updated)
        XCTAssertEqual(model.devices[0].vendor, "Resolved Vendor")
        XCTAssertEqual(model.devices[0].totalBytesSent, 500)
        current.id = UUID()
        current.vendor = "New Network Device"
        model.devices = [current]
        model.updateDevice(updated)
        XCTAssertEqual(model.devices[0].vendor, "New Network Device")
    }

    @MainActor
    func testDetailDeduplicatesPortsAndReceivesLiveUpdates() {
        var device = NetworkDevice(ipAddress: "192.168.1.2", openPorts: [80, 80, 443])
        let detail = DeviceDetailViewModel(device: device)
        XCTAssertEqual(detail.openPorts.map(\.port), [80, 443])
        device.downloadSpeedKbps = 42
        detail.updateLiveDevice(device)
        XCTAssertEqual(detail.device.downloadSpeedKbps, 42)
        detail.updateLiveDevice(NetworkDevice(ipAddress: device.ipAddress))
        XCTAssertEqual(detail.device.id, device.id)
    }

    @MainActor
    func testLaunchScanWaitsForResolvedNetworkPath() {
        let previousSetting = UserDefaults.standard.object(forKey: "autoRefreshOnLaunch")
        UserDefaults.standard.set(false, forKey: "autoRefreshOnLaunch")
        defer { UserDefaults.standard.set(previousSetting, forKey: "autoRefreshOnLaunch") }
        let model = DeviceListViewModel()
        var interface = NetworkInterfaceInfo(ipAddress: "192.168.1.2", isConnected: true, isLAN: true)
        model.handleInterfaceChange(interface, pathResolved: false)
        XCTAssertFalse(model.didAutoScan)
        interface.gatewayIP = "192.168.1.1"
        model.handleInterfaceChange(interface, pathResolved: true)
        XCTAssertTrue(model.didAutoScan)
        XCTAssertFalse(model.isScanning) // The disabled preference is respected.
    }

    func testRemoteTrafficUnavailableAndLocalTotalsDoNotOverflow() {
        var device = NetworkDevice(ipAddress: "192.168.1.2", totalBytesSent: .max, totalBytesReceived: .max)
        XCTAssertEqual(device.formattedDownload, "Unavailable")
        XCTAssertEqual(device.formattedTotalTransfer, "Unavailable")
        device.isLocalDevice = true
        XCTAssertTrue(device.formattedTotalTransfer.hasSuffix("GB"))
    }

    func testInvalidPortsCompleteOnMainWithoutTrapping() {
        let done = expectation(description: "invalid port scan completes")
        let scanner = PortScannerService()
        scanner.scanPorts(targetIP: "127.0.0.1", ports: [-1, 0, 65536, Int.max], onPortFound: { _ in
            XCTFail("Invalid ports cannot be open")
        }, onProgress: { _ in }, onCompletion: { results in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertTrue(results.isEmpty)
            done.fulfill()
        })
        wait(for: [done], timeout: 2)
    }

    func testPortProbeCompletesOnceAndDeduplicatesResults() throws {
        let ready = expectation(description: "loopback listener ready")
        let listener = try NWListener(using: .tcp, on: .any)
        listener.newConnectionHandler = { $0.cancel() }
        listener.stateUpdateHandler = { state in
            if case .ready = state { ready.fulfill() }
        }
        listener.start(queue: .main)
        defer { listener.cancel() }
        wait(for: [ready], timeout: 2)
        let port = try XCTUnwrap(listener.port).rawValue
        let done = expectation(description: "port scan completes once")
        done.assertForOverFulfill = true
        let scanner = PortScannerService()
        var found = 0
        scanner.scanPorts(targetIP: "127.0.0.1", ports: [Int(port), Int(port)], onPortFound: { result in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertEqual(result.port, Int(port))
            found += 1
        }, onProgress: { value in
            XCTAssertTrue((0...1).contains(value))
        }, onCompletion: { results in
            XCTAssertEqual(results.map(\.port), [Int(port)])
            XCTAssertEqual(found, 1)
            done.fulfill()
        })
        wait(for: [done], timeout: 3)
        let settled = expectation(description: "late timeout settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { settled.fulfill() }
        wait(for: [settled], timeout: 2)
    }

    func testCancelledPortRunCannotDeliverIntoRestart() {
        let scanner = PortScannerService()
        let old = expectation(description: "cancelled run callbacks suppressed")
        old.isInverted = true
        scanner.scanPorts(targetIP: "127.0.0.1", ports: [1, 2, 3],
                          onPortFound: { _ in old.fulfill() }, onProgress: { _ in old.fulfill() },
                          onCompletion: { _ in old.fulfill() })
        scanner.cancel()
        let done = expectation(description: "replacement run completes")
        scanner.scanPorts(targetIP: "127.0.0.1", ports: [], onPortFound: { _ in },
                          onProgress: { _ in }, onCompletion: { _ in done.fulfill() })
        wait(for: [done, old], timeout: 1)
    }

    func testReverseDNSInvalidAddressAndZeroTimeoutReturnPromptly() async {
        let start = Date()
        let result = await OUIVendorDatabase.resolveReverseDNS(ip: "not an IP", timeout: 0)
        XCTAssertNil(result)
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.5)
        let invalidTimeout = await OUIVendorDatabase.resolveReverseDNS(ip: "127.0.0.1", timeout: .infinity)
        XCTAssertNil(invalidTimeout)
    }

    func testCancelledSubnetRunCannotDeliverIntoRestart() {
        let scanner = SubnetScannerService()
        let interface = NetworkInterfaceInfo(ipAddress: "127.0.0.1", cidrPrefix: 32, isConnected: true, isLAN: true)
        let old = expectation(description: "cancelled discovery callbacks suppressed")
        old.isInverted = true
        scanner.scanSubnet(interface: interface, onProgress: { _ in old.fulfill() },
                           onDeviceFound: { _ in old.fulfill() }, onCompletion: { _ in old.fulfill() })
        scanner.cancelScan()
        let done = expectation(description: "replacement discovery completes")
        var found = 0
        scanner.scanSubnet(interface: interface, onProgress: { _ in }, onDeviceFound: { _ in found += 1 },
                           onCompletion: { devices in
            XCTAssertEqual(devices.count, 1)
            XCTAssertEqual(found, 1)
            done.fulfill()
        })
        wait(for: [done, old], timeout: 1)
    }

    func testReverseDNSTimeoutDoesNotWaitForBlockingResolverOrResumeTwice() async {
        let start = Date()
        let result = await OUIVendorDatabase.resolveReverseDNS(timeout: 0.01) {
            Thread.sleep(forTimeInterval: 0.4)
            return "late.local"
        }
        XCTAssertNil(result)
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.2)
        // Let the late resolver complete to exercise the one-shot continuation guard.
        try? await Task.sleep(nanoseconds: 500_000_000)
    }

    @MainActor
    func testStoppedPingCannotAppendAndNewSessionResetsStatistics() async {
        let ping = PingDiagnosticService()
        ping.startPinging(host: "127.0.0.1")
        ping.stop()
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        XCTAssertTrue(ping.history.isEmpty)
        ping.avgRtt = 100
        ping.minRtt = 90
        ping.maxRtt = 110
        ping.packetLossPercent = 50
        ping.startPinging(host: "127.0.0.1")
        XCTAssertEqual(ping.avgRtt, 0)
        XCTAssertEqual(ping.minRtt, 0)
        XCTAssertEqual(ping.maxRtt, 0)
        XCTAssertEqual(ping.packetLossPercent, 0)
        ping.stop()
    }
}
