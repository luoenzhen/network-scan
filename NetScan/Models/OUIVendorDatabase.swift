//
//  OUIVendorDatabase.swift
//  NetScan
//
//  IEEE Organizationally Unique Identifier (OUI) database for hardware vendor lookup.
//

import Foundation

public struct OUIVendorDatabase {
    // Official IEEE MAC OUI prefix database (first 3 octets, uppercase without colons or dashes)
    private static let vendorPrefixes: [String: (vendor: String, defaultType: DeviceType)] = [
        // Raspberry Pi Foundation & Trading Ltd (All official IEEE allocations)
        "B827EB": ("Raspberry Pi Foundation", .computer),
        "DCA632": ("Raspberry Pi Foundation", .computer),
        "E45F01": ("Raspberry Pi Foundation", .computer),
        "28CDC1": ("Raspberry Pi Foundation", .computer),
        "D83ADD": ("Raspberry Pi (RPi 4/5/Zero)", .computer),
        "2CCF67": ("Raspberry Pi (RPi 5/CM4)", .computer),
        "B81F5E": ("Raspberry Pi Ltd", .computer),
        "004B12": ("Raspberry Pi Ltd", .computer),
        
        // Apple
        "0017F2": ("Apple", .computer),
        "001C42": ("Apple / Parallels", .computer),
        "001E52": ("Apple", .computer),
        "002500": ("Apple", .phone),
        "0026BB": ("Apple", .computer),
        "040C5C": ("Apple", .phone),
        "0C4DE9": ("Apple", .phone),
        "109ADD": ("Apple", .tablet),
        "147DDA": ("Apple", .phone),
        "286A81": ("Apple", .phone),
        "3C22FB": ("Apple", .computer),
        "3CE072": ("Apple", .phone),
        "406C8F": ("Apple", .phone),
        "701124": ("Apple", .tv),
        "7CE9D3": ("Apple", .phone),
        "8C8590": ("Apple", .phone),
        "A4C361": ("Apple", .computer),
        "ACBC32": ("Apple", .computer),
        "BC52B7": ("Apple", .phone),
        "F01898": ("Apple", .phone),
        "F4F15A": ("Apple", .phone),
        "A8515B": ("Apple", .phone),
        "907240": ("Apple", .phone),
        "186590": ("Apple", .computer),
        
        // Samsung Electronics
        "0000F0": ("Samsung", .tv),
        "0012FB": ("Samsung", .phone),
        "00166C": ("Samsung", .phone),
        "0808C2": ("Samsung", .phone),
        "144D67": ("Samsung", .phone),
        "244B03": ("Samsung", .phone),
        "3423BA": ("Samsung", .tv),
        "508569": ("Samsung", .phone),
        "842519": ("Samsung", .phone),
        "94350A": ("Samsung", .phone),
        "A0821F": ("Samsung", .phone),
        "C0BDD1": ("Samsung", .tv),
        "E458B8": ("Samsung", .phone),
        "F4D9FB": ("Samsung", .tv),
        "4C3CD7": ("Samsung", .tv),
        
        // Google / Nest
        "001A11": ("Google", .smartHome),
        "20DFB9": ("Google (Nest)", .smartHome),
        "3CE1A1": ("Google (Chromecast)", .tv),
        "546009": ("Google", .phone),
        "94E979": ("Google", .phone),
        "A47733": ("Google (Nest)", .smartHome),
        "D4F547": ("Google", .phone),
        "F4F5DB": ("Google", .phone),
        
        // Amazon
        "00FC8B": ("Amazon (Echo/Fire)", .smartHome),
        "38F73D": ("Amazon (Echo)", .smartHome),
        "44650D": ("Amazon (Fire TV)", .tv),
        "50F5DA": ("Amazon (Echo)", .smartHome),
        "6837E9": ("Amazon (Fire Tablet)", .tablet),
        "74C246": ("Amazon (Echo)", .smartHome),
        "84D6D0": ("Amazon (Echo)", .smartHome),
        "FC65DE": ("Amazon (Echo)", .smartHome),
        
        // Router & Network Vendors
        "0014D1": ("TP-Link", .router),
        "14CC20": ("TP-Link", .router),
        "50C7BF": ("TP-Link (Kasa Smart)", .smartHome),
        "6032B1": ("TP-Link", .router),
        "98DED0": ("TP-Link", .router),
        "E848B8": ("TP-Link", .router),
        "000C43": ("Ralink / MediaTek", .router),
        "0018E7": ("Netgear", .router),
        "20E52A": ("Netgear", .router),
        "28C68E": ("Netgear", .router),
        "B07FB9": ("Netgear (Orbi)", .router),
        "001DD8": ("Microsoft", .gaming),
        "281878": ("Microsoft (Surface)", .tablet),
        "7C1E52": ("Microsoft (Xbox)", .gaming),
        "000420": ("Slim Devices", .smartHome),
        "001B63": ("Apple AirPort", .router),
        "00248C": ("ASUSTek", .router),
        "04D4C4": ("ASUSTek", .computer),
        "10BF48": ("ASUSTek", .router),
        "001E8C": ("Sony", .tv),
        "001FDE": ("Sony", .gaming),
        "709E29": ("Sony (PlayStation)", .gaming),
        "FC0F4B": ("Sony (PlayStation)", .gaming),
        
        // Espressif / IoT
        "18FE34": ("Espressif (ESP8266 IoT)", .smartHome),
        "240AC4": ("Espressif (ESP32 IoT)", .smartHome),
        "30AEA4": ("Espressif (ESP32 IoT)", .smartHome),
        "84F3EB": ("Espressif (ESP8266 IoT)", .smartHome),
        
        // Printers
        "00110A": ("HP (Hewlett-Packard)", .printer),
        "001E0B": ("HP", .printer),
        "3CD92B": ("HP (OfficeJet / LaserJet)", .printer),
        "705A0F": ("HP", .printer),
        "000085": ("Canon", .printer),
        "001E8F": ("Canon (PIXMA)", .printer),
        "0021B7": ("Epson", .printer),
        "0026AB": ("Epson", .printer),
        "008077": ("Brother", .printer),
        "30055C": ("Brother", .printer)
    ]
    
    public static func lookup(macAddress: String) -> (vendor: String, defaultType: DeviceType)? {
        let clean = macAddress.uppercased().replacingOccurrences(of: ":", with: "")
                                           .replacingOccurrences(of: "-", with: "")
                                           .replacingOccurrences(of: ".", with: "")
        guard clean.count >= 6 else { return nil }
        let prefix = String(clean.prefix(6))
        return vendorPrefixes[prefix]
    }
    
    public static func inferDeviceType(hostname: String, vendor: String) -> DeviceType {
        let lowerHost = hostname.lowercased()
        let lowerVendor = vendor.lowercased()
        
        // Raspberry Pi detection takes top priority
        if lowerHost.contains("raspberry") || lowerHost.contains("rpi") || lowerHost.contains("octopi") ||
           lowerHost.contains("retropie") || lowerHost.contains("dietpi") || lowerHost.contains("pihole") ||
           lowerHost.contains("pi-hole") || lowerHost.contains("pigateway") || lowerHost.contains("pivpn") ||
           lowerVendor.contains("raspberry") {
            return .computer
        }
        
        if lowerHost.contains("iphone") || lowerHost.contains("pixel") || lowerHost.contains("galaxy") || lowerHost.contains("phone") {
            return .phone
        }
        if lowerHost.contains("ipad") || lowerHost.contains("tablet") {
            return .tablet
        }
        if lowerHost.contains("macbook") || lowerHost.contains("imac") || lowerHost.contains("pc") ||
           lowerHost.contains("desktop") || lowerHost.contains("laptop") || lowerHost.contains("thinkpad") {
            return .computer
        }
        if lowerHost.contains("router") || lowerHost.contains("gateway") || lowerHost.contains("ap-") ||
           lowerHost.contains("mesh") || lowerHost.contains("openwrt") {
            return .router
        }
        if lowerHost.contains("tv") || lowerHost.contains("roku") || lowerHost.contains("chromecast") ||
           lowerHost.contains("bravia") || lowerHost.contains("appletv") {
            return .tv
        }
        if lowerHost.contains("xbox") || lowerHost.contains("playstation") || lowerHost.contains("ps5") ||
           lowerHost.contains("ps4") || lowerHost.contains("nintendo") || lowerHost.contains("switch") {
            return .gaming
        }
        if lowerHost.contains("printer") || lowerHost.contains("epson") || lowerHost.contains("laserjet") || lowerHost.contains("brother") {
            return .printer
        }
        if lowerHost.contains("echo") || lowerHost.contains("alexa") || lowerHost.contains("nest") ||
           lowerHost.contains("homepod") || lowerHost.contains("bulb") || lowerHost.contains("kasa") ||
           lowerHost.contains("tasmota") || lowerHost.contains("esp32") || lowerHost.contains("esp8266") {
            return .smartHome
        }
        
        if lowerVendor.contains("apple") { return .phone }
        if lowerVendor.contains("samsung") { return .phone }
        if lowerVendor.contains("tp-link") || lowerVendor.contains("netgear") || lowerVendor.contains("asus") { return .router }
        if lowerVendor.contains("espressif") { return .smartHome }
        if lowerVendor.contains("hp") || lowerVendor.contains("canon") || lowerVendor.contains("epson") || lowerVendor.contains("brother") { return .printer }
        if lowerVendor.contains("amazon") { return .smartHome }
        if lowerVendor.contains("sony") { return .tv }
        
        return .unknown
    }
    
    public static func identifyDevice(macAddress: String?, hostname: String) -> (vendor: String, deviceType: DeviceType) {
        // 1. Direct MAC OUI lookup
        if let mac = macAddress, let res = lookup(macAddress: mac) {
            let type = inferDeviceType(hostname: hostname, vendor: res.vendor)
            return (res.vendor, type == .unknown ? res.defaultType : type)
        }
        
        // 2. Hostname-based detection
        let lowerHost = hostname.lowercased()
        if lowerHost.contains("raspberry") || lowerHost.contains("rpi") || lowerHost.contains("octopi") ||
           lowerHost.contains("retropie") || lowerHost.contains("dietpi") || lowerHost.contains("pihole") ||
           lowerHost.contains("pi-hole") {
            return ("Raspberry Pi Foundation", .computer)
        }
        if lowerHost.contains("apple") || lowerHost.contains("iphone") || lowerHost.contains("ipad") ||
           lowerHost.contains("macbook") || lowerHost.contains("imac") || lowerHost.contains("airplay") {
            return ("Apple Inc.", inferDeviceType(hostname: hostname, vendor: "Apple"))
        }
        if lowerHost.contains("samsung") || lowerHost.contains("galaxy") {
            return ("Samsung Electronics", inferDeviceType(hostname: hostname, vendor: "Samsung"))
        }
        if lowerHost.contains("google") || lowerHost.contains("nest") || lowerHost.contains("chromecast") {
            return ("Google LLC", inferDeviceType(hostname: hostname, vendor: "Google"))
        }
        if lowerHost.contains("esp32") || lowerHost.contains("esp8266") || lowerHost.contains("tasmota") {
            return ("Espressif Systems", .smartHome)
        }
        if lowerHost.contains("router") || lowerHost.contains("gateway") {
            return ("Network Gateway", .router)
        }
        if lowerHost.contains("printer") || lowerHost.contains("laserjet") || lowerHost.contains("officejet") {
            return ("Network Printer", .printer)
        }
        
        return ("Network Device", .unknown)
    }
}
