import XCTest

final class DeviceDetailUITests: XCTestCase {
    func testOpenDeviceFindVendorAndReturnToList() {
        let app = XCUIApplication()
        app.launchEnvironment["NETSCAN_UI_TESTING"] = "1"
        app.launchEnvironment["NETSCAN_UI_RESET"] = "1"
        app.launch()
        app.tabBars.buttons["Devices"].tap()
        let row = app.descendants(matching: .any)["device-00000000-0000-0000-0000-000000000001"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        let findVendor = app.buttons["find-vendor"]
        for _ in 0..<3 {
            if findVendor.exists && findVendor.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(findVendor.waitForExistence(timeout: 5))
        XCTAssertTrue(findVendor.isHittable)
        findVendor.tap()
        let vendor = app.staticTexts["Raspberry Pi Foundation"].firstMatch
        XCTAssertTrue(vendor.waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Network Devices"].waitForExistence(timeout: 5))
        XCTAssertTrue(row.waitForExistence(timeout: 5))
    }

    func testSaveIdentityAcrossRestartAndPreviewRedactedReport() {
        let app = XCUIApplication()
        app.launchEnvironment["NETSCAN_UI_TESTING"] = "1"
        app.launchEnvironment["NETSCAN_UI_RESET"] = "1"
        app.launch()
        app.tabBars.buttons["Devices"].tap()
        let row = app.descendants(matching: .any)["device-00000000-0000-0000-0000-000000000001"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        app.buttons["edit-device"].tap()
        let name = app.textFields["device-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("GoodWe Inverter")
        app.textFields["device-location"].tap()
        app.textFields["device-location"].typeText("Garage")
        app.buttons["save-device"].tap()
        XCTAssertTrue(app.staticTexts["GoodWe Inverter"].firstMatch.waitForExistence(timeout: 5))
        app.terminate()
        app.launchEnvironment.removeValue(forKey: "NETSCAN_UI_RESET")
        app.launch()
        app.tabBars.buttons["Devices"].tap()
        XCTAssertTrue(app.staticTexts["GoodWe Inverter"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["Scan"].tap()
        app.buttons["scan-history"].tap()
        XCTAssertTrue(app.navigationBars["Scan History"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No comparable changes detected."].firstMatch.exists)
        app.buttons["Done"].tap()
        app.buttons["export-report"].tap()
        let preview = app.staticTexts["report-preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        func previewText() -> String { preview.label + " " + (preview.value as? String ?? "") }
        XCTAssertTrue(previewText().contains("NetScan network report"), "The preview must expose the actual report text")
        XCTAssertFalse(previewText().contains("GoodWe"))
        XCTAssertFalse(previewText().contains("Garage"))
        XCTAssertFalse(previewText().contains("127.0.0.1"))
        let privacy = app.switches["redact-report"]
        privacy.tap()
        let switchedOff = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '0'"), object: privacy)
        XCTAssertEqual(XCTWaiter.wait(for: [switchedOff], timeout: 3), .completed)
        let updated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            previewText().contains("GoodWe Inverter") && previewText().contains("Garage")
        }, object: preview)
        let result = XCTWaiter.wait(for: [updated], timeout: 5)
        if result != .completed {
            print("REPORT SWITCH: \(privacy.debugDescription)")
            print("REPORT PREVIEW: \(preview.debugDescription)")
            print("REPORT VALUE: \(preview.value as? String ?? "nil")")
            print("REPORT LABEL: \(preview.label)")
        }
        XCTAssertEqual(result, .completed)
    }
}
