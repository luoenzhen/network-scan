import XCTest

final class DeviceDetailUITests: XCTestCase {
    func testOpenDeviceFindVendorAndReturnToList() {
        let app = XCUIApplication()
        app.launchEnvironment["NETSCAN_UI_TESTING"] = "1"
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
}
