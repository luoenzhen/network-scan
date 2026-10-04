//
//  OUIVendorDatabase.swift
//  NetScan
//
//  Comprehensive IEEE Organizationally Unique Identifier (OUI) database.
//  Includes built-in support for all major device brands, local full 52,000+
//  entry bundle database loading, and asynchronous online fallback query
//  (api.maclookup.app & api.macvendors.com) when a vendor cannot be identified locally.
//

import Foundation

public struct OUIVendorDatabase {
    // Thread-safe runtime caches
    private static var fullDatabase: [String: String]? = nil
    private static var isDatabaseLoading = false
    private static var onlineCache: [String: (vendor: String, defaultType: DeviceType)] = [:]
    private static let lock = NSLock()
    
    // Built-in high priority vendor prefixes for instant offline recognition
    private static let vendorPrefixes: [String: (vendor: String, defaultType: DeviceType)] = [
        // =========================================================================
        // Raspberry Pi Foundation & Raspberry Pi Ltd (All Official IEEE Allocations)
        // =========================================================================
        "B827EB": ("Raspberry Pi Foundation", .computer),
        "DCA632": ("Raspberry Pi Trading Ltd", .computer),
        "E45F01": ("Raspberry Pi Trading Ltd", .computer),
        "28CDC1": ("Raspberry Pi Trading Ltd", .computer),
        "D83ADD": ("Raspberry Pi Ltd (RPi 4/5)", .computer),
        "2CCF67": ("Raspberry Pi Ltd (RPi 5/CM4)", .computer),
        "88A29E": ("Raspberry Pi Ltd", .computer),
        "B81F5E": ("Raspberry Pi Ltd", .computer),
        "004B12": ("Raspberry Pi Ltd", .computer),
        
        // =========================================================================
        // Apple Inc. (iPhone, iPad, Mac, Watch, Apple TV, AirPort)
        // =========================================================================
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
        "701124": ("Apple (Apple TV)", .tv),
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
        "000393": ("Apple", .computer),
        "000A27": ("Apple", .computer),
        "0010FA": ("Apple", .computer),
        "001451": ("Apple", .computer),
        "0016CB": ("Apple", .computer),
        "001D4F": ("Apple", .computer),
        "001F5B": ("Apple", .phone),
        "002312": ("Apple", .phone),
        "002332": ("Apple", .phone),
        "00236C": ("Apple", .computer),
        "0023DF": ("Apple", .phone),
        "002436": ("Apple", .phone),
        "00254B": ("Apple", .phone),
        "0025BC": ("Apple", .phone),
        "002608": ("Apple", .computer),
        "00264A": ("Apple", .phone),
        "0026B0": ("Apple", .phone),
        "18AF61": ("Apple", .phone),
        "20A2E4": ("Apple", .phone),
        "24AB81": ("Apple", .computer),
        "28E14C": ("Apple", .phone),
        "28CFE9": ("Apple", .phone),
        "3408BC": ("Apple", .phone),
        "38C986": ("Apple", .phone),
        "3C0754": ("Apple", .phone),
        "40D32D": ("Apple", .phone),
        "4860BC": ("Apple", .computer),
        "4C3275": ("Apple", .phone),
        "54E43A": ("Apple", .phone),
        "5855CA": ("Apple", .phone),
        "5C97F3": ("Apple", .phone),
        "600308": ("Apple", .phone),
        "64B0A6": ("Apple", .computer),
        "68AE20": ("Apple", .phone),
        "6C4008": ("Apple", .phone),
        "70DEE2": ("Apple", .phone),
        "784F43": ("Apple", .phone),
        "7C04D0": ("Apple", .phone),
        "80E650": ("Apple", .phone),
        "88665A": ("Apple", .phone),
        "8C7C92": ("Apple", .phone),
        "908D6C": ("Apple", .phone),
        "941625": ("Apple", .phone),
        "9801A7": ("Apple", .phone),
        "9C207B": ("Apple", .phone),
        "A03BF7": ("Apple", .phone),
        "A483E7": ("Apple", .phone),
        "A860B6": ("Apple", .phone),
        "AC87A3": ("Apple", .phone),
        "B065BD": ("Apple", .phone),
        "B418D1": ("Apple", .phone),
        "B8782E": ("Apple", .phone),
        "BC6778": ("Apple", .phone),
        "C0847A": ("Apple", .phone),
        "C42C03": ("Apple", .phone),
        "C869CD": ("Apple", .phone),
        "CC29F5": ("Apple", .phone),
        "D023DB": ("Apple", .phone),
        "D4619D": ("Apple", .phone),
        "D81C79": ("Apple", .phone),
        "DC2B61": ("Apple", .phone),
        "E0B55F": ("Apple", .phone),
        "E49A79": ("Apple", .phone),
        "E8802E": ("Apple", .phone),
        "EC3586": ("Apple", .phone),
        "F0DBF8": ("Apple", .phone),
        "F40F24": ("Apple", .phone),
        "F81EDF": ("Apple", .phone),
        "FC25EC": ("Apple", .phone),
        
        // =========================================================================
        // Samsung Electronics (Galaxy Phones, QLED/NeoQLED Smart TVs, Soundbars)
        // =========================================================================
        "0000F0": ("Samsung Electronics", .tv),
        "0012FB": ("Samsung Electronics", .phone),
        "00166C": ("Samsung Electronics", .phone),
        "0808C2": ("Samsung Electronics", .phone),
        "144D67": ("Samsung Electronics", .phone),
        "244B03": ("Samsung Electronics", .phone),
        "3423BA": ("Samsung Electronics", .tv),
        "508569": ("Samsung Electronics", .phone),
        "842519": ("Samsung Electronics", .phone),
        "94350A": ("Samsung Electronics", .phone),
        "A0821F": ("Samsung Electronics", .phone),
        "C0BDD1": ("Samsung Electronics", .tv),
        "E458B8": ("Samsung Electronics", .phone),
        "F4D9FB": ("Samsung Electronics", .tv),
        "4C3CD7": ("Samsung Electronics", .tv),
        "000278": ("Samsung Electro-Mechanics", .smartHome),
        "0007AB": ("Samsung Electronics", .tv),
        "001247": ("Samsung Electronics", .phone),
        "001377": ("Samsung Electronics", .tv),
        "001599": ("Samsung Electronics", .phone),
        "0017D5": ("Samsung Electronics", .phone),
        "001A8A": ("Samsung Electronics", .phone),
        "001D25": ("Samsung Electronics", .phone),
        "001E7D": ("Samsung Electronics", .phone),
        "002119": ("Samsung Electronics", .phone),
        "002339": ("Samsung Electronics", .phone),
        "002454": ("Samsung Electronics", .phone),
        "002637": ("Samsung Electronics", .phone),
        "08373D": ("Samsung Electronics", .phone),
        "08D46A": ("Samsung Electronics", .phone),
        "0C1420": ("Samsung Electronics", .phone),
        "1077B1": ("Samsung Electronics", .phone),
        "1867B0": ("Samsung Electronics", .phone),
        "205531": ("Samsung Electronics", .phone),
        "247189": ("Samsung Electronics", .phone),
        "28987B": ("Samsung Electronics", .phone),
        "30074D": ("Samsung Electronics", .phone),
        "380146": ("Samsung Electronics", .tv),
        "40163B": ("Samsung Electronics", .phone),
        "4480EB": ("Samsung Electronics", .phone),
        "4C63EB": ("Samsung Electronics", .phone),
        "5492BE": ("Samsung Electronics", .phone),
        "58C38B": ("Samsung Electronics", .phone),
        "606C66": ("Samsung Electronics", .phone),
        "641CB0": ("Samsung Electronics", .phone),
        "68EBDE": ("Samsung Electronics", .phone),
        "702C1F": ("Samsung Electronics", .tv),
        "78471D": ("Samsung Electronics", .phone),
        "7C9122": ("Samsung Electronics", .phone),
        "805B39": ("Samsung Electronics", .phone),
        "843838": ("Samsung Electronics", .phone),
        "8C7712": ("Samsung Electronics", .phone),
        "9097F3": ("Samsung Electronics", .phone),
        "98398E": ("Samsung Electronics", .phone),
        "A470D2": ("Samsung Electronics", .phone),
        "A87C01": ("Samsung Electronics", .phone),
        "AC5A14": ("Samsung Electronics", .phone),
        "B0C4E7": ("Samsung Electronics", .phone),
        "B407F6": ("Samsung Electronics", .phone),
        "BC72B9": ("Samsung Electronics", .phone),
        "C4731E": ("Samsung Electronics", .phone),
        "CCB11A": ("Samsung Electronics", .phone),
        "D4E8B2": ("Samsung Electronics", .phone),
        "DC7144": ("Samsung Electronics", .phone),
        "E47CF9": ("Samsung Electronics", .phone),
        "E8E5D6": ("Samsung Electronics", .phone),
        "F02572": ("Samsung Electronics", .phone),
        "F8042E": ("Samsung Electronics", .phone),
        "FC039F": ("Samsung Electronics", .phone),
        
        // =========================================================================
        // Google LLC / Nest / Chromecast / Pixel
        // =========================================================================
        "001A11": ("Google LLC", .smartHome),
        "20DFB9": ("Google (Nest)", .smartHome),
        "3CE1A1": ("Google (Chromecast)", .tv),
        "546009": ("Google (Pixel)", .phone),
        "94E979": ("Google (Pixel)", .phone),
        "A47733": ("Google (Nest)", .smartHome),
        "D4F547": ("Google (Pixel)", .phone),
        "F4F5DB": ("Google (Pixel)", .phone),
        "24E853": ("Google LLC", .smartHome),
        "388B59": ("Google LLC", .smartHome),
        "44070B": ("Google LLC", .smartHome),
        "48D6D5": ("Google (Nest Hub)", .smartHome),
        "5882A8": ("Google LLC", .smartHome),
        "641666": ("Google (Nest)", .smartHome),
        "703A51": ("Google (Nest Cam)", .smartHome),
        "800588": ("Google LLC", .smartHome),
        "940E6B": ("Google LLC", .smartHome),
        "A0CEFC": ("Google LLC", .smartHome),
        "C43018": ("Google LLC", .smartHome),
        "DC5360": ("Google (Pixel)", .phone),
        "E076D0": ("Google (Nest)", .smartHome),
        "E4F042": ("Google LLC", .smartHome),
        "F80F69": ("Google LLC", .smartHome),
        
        // =========================================================================
        // Amazon (Echo, Fire TV, Fire Tablet, Ring, Blink, Eero)
        // =========================================================================
        "00FC8B": ("Amazon (Echo / Fire)", .smartHome),
        "38F73D": ("Amazon (Echo)", .smartHome),
        "44650D": ("Amazon (Fire TV)", .tv),
        "50F5DA": ("Amazon (Echo)", .smartHome),
        "6837E9": ("Amazon (Fire Tablet)", .tablet),
        "74C246": ("Amazon (Echo)", .smartHome),
        "84D6D0": ("Amazon (Echo)", .smartHome),
        "FC65DE": ("Amazon (Echo)", .smartHome),
        "0C47C9": ("Amazon (Blink / Ring)", .smartHome),
        "18742E": ("Amazon (Echo Show)", .smartHome),
        "34D270": ("Amazon (Echo Dot)", .smartHome),
        "40B4CD": ("Amazon (Fire TV Stick)", .tv),
        "4C1744": ("Amazon Technologies", .smartHome),
        "5C2479": ("Amazon (Echo)", .smartHome),
        "68545A": ("Amazon (Fire TV)", .tv),
        "78E103": ("Amazon (Ring Video Doorbell)", .smartHome),
        "8871E5": ("Amazon Technologies", .smartHome),
        "9C7613": ("Amazon (Fire TV)", .tv),
        "A002DC": ("Amazon (Echo Studio)", .smartHome),
        "B47C9C": ("Amazon Technologies", .smartHome),
        "CCF411": ("Amazon (Eero Mesh)", .router),
        "E08B39": ("Amazon (Ring)", .smartHome),
        "F08173": ("Amazon Technologies", .smartHome),
        
        // =========================================================================
        // Sony (PlayStation 4/5, BRAVIA Smart TVs, Audio)
        // =========================================================================
        "001E8C": ("Sony (BRAVIA TV)", .tv),
        "001FDE": ("Sony (PlayStation)", .gaming),
        "709E29": ("Sony (PlayStation 4)", .gaming),
        "FC0F4B": ("Sony (PlayStation 5)", .gaming),
        "00014A": ("Sony Corporation", .tv),
        "00041F": ("Sony Corporation", .tv),
        "0013A9": ("Sony (PlayStation 3)", .gaming),
        "0015C1": ("Sony Corporation", .tv),
        "0019C5": ("Sony (BRAVIA TV)", .tv),
        "0024BE": ("Sony (PlayStation)", .gaming),
        "280D5C": ("Sony (PlayStation 5)", .gaming),
        "30F772": ("Sony (BRAVIA 4K)", .tv),
        "78843C": ("Sony Interactive", .gaming),
        "A8E3EE": ("Sony (PlayStation 5)", .gaming),
        "BC60A7": ("Sony (BRAVIA TV)", .tv),
        "E063E5": ("Sony Interactive", .gaming),
        "F8461C": ("Sony (PlayStation 4)", .gaming),
        
        // =========================================================================
        // Microsoft (Xbox 360 / One / Series X, Surface)
        // =========================================================================
        "001DD8": ("Microsoft (Xbox)", .gaming),
        "281878": ("Microsoft (Surface)", .tablet),
        "7C1E52": ("Microsoft (Xbox Series X/S)", .gaming),
        "0003FF": ("Microsoft Corporation", .computer),
        "000D3A": ("Microsoft (Virtual)", .computer),
        "00125A": ("Microsoft (Xbox 360)", .gaming),
        "00155D": ("Microsoft (Hyper-V)", .computer),
        "0017FA": ("Microsoft (Xbox 360)", .gaming),
        "002248": ("Microsoft (Xbox 360)", .gaming),
        "0025AE": ("Microsoft (Xbox One)", .gaming),
        "3059B7": ("Microsoft (Surface Laptop)", .computer),
        "588694": ("Microsoft (Xbox One S)", .gaming),
        "6045BD": ("Microsoft (Xbox)", .gaming),
        "703217": ("Microsoft (Surface Pro)", .tablet),
        "985FD3": ("Microsoft (Xbox)", .gaming),
        "B4AE2B": ("Microsoft (Surface)", .computer),
        "DC537C": ("Microsoft (Xbox Series X)", .gaming),
        
        // =========================================================================
        // Nintendo (Switch, Switch OLED, Wii U, 3DS)
        // =========================================================================
        "0009BF": ("Nintendo", .gaming),
        "001656": ("Nintendo (Wii)", .gaming),
        "0017AB": ("Nintendo", .gaming),
        "0019FD": ("Nintendo (DS)", .gaming),
        "001BEA": ("Nintendo", .gaming),
        "001F32": ("Nintendo (Wii)", .gaming),
        "002147": ("Nintendo (DSi)", .gaming),
        "0022AA": ("Nintendo", .gaming),
        "002331": ("Nintendo (3DS)", .gaming),
        "00241E": ("Nintendo", .gaming),
        "0024F3": ("Nintendo", .gaming),
        "0025A0": ("Nintendo (Wii U)", .gaming),
        "002659": ("Nintendo", .gaming),
        "34AF2C": ("Nintendo (Switch)", .gaming),
        "40F407": ("Nintendo (Switch)", .gaming),
        "582F40": ("Nintendo (Switch)", .gaming),
        "70480F": ("Nintendo (Switch OLED)", .gaming),
        "78A2A0": ("Nintendo (Switch)", .gaming),
        "98B6E9": ("Nintendo (Switch)", .gaming),
        "B88687": ("Nintendo (Switch)", .gaming),
        "CC9E00": ("Nintendo (Switch)", .gaming),
        "E0E751": ("Nintendo (Switch)", .gaming),
        
        // =========================================================================
        // LG Electronics (OLED / QNED Smart TV, ThinQ Smart Appliances)
        // =========================================================================
        "0005F9": ("LG Electronics", .tv),
        "0014E8": ("LG Electronics", .tv),
        "001C62": ("LG Electronics", .tv),
        "001E75": ("LG Electronics", .tv),
        "001F6B": ("LG Electronics", .tv),
        "002483": ("LG Electronics", .tv),
        "04254E": ("LG Electronics (webOS TV)", .tv),
        "085B9E": ("LG Electronics", .tv),
        "10683F": ("LG Electronics (OLED TV)", .tv),
        "14C913": ("LG Electronics", .tv),
        "1868CB": ("LG Electronics (ThinQ)", .smartHome),
        "203DB0": ("LG Electronics", .tv),
        "2C598A": ("LG Electronics", .tv),
        "307512": ("LG Electronics", .tv),
        "3C0771": ("LG Electronics", .tv),
        "4827EA": ("LG Electronics", .tv),
        "58A2B5": ("LG Electronics", .tv),
        "64995D": ("LG Electronics (OLED TV)", .tv),
        "706D15": ("LG Electronics", .tv),
        "88C9D0": ("LG Electronics", .tv),
        "A823FE": ("LG Electronics", .tv),
        "B86C46": ("LG Electronics", .tv),
        "C4366C": ("LG Electronics", .tv),
        "CC2D8C": ("LG Electronics", .tv),
        "DC0B34": ("LG Electronics", .tv),
        "E85B5B": ("LG Electronics", .tv),
        
        // =========================================================================
        // TP-Link Technologies (Archer Routers, Deco Mesh, Tapo, Kasa Smart)
        // =========================================================================
        "0014D1": ("TP-Link Technologies", .router),
        "14CC20": ("TP-Link Technologies", .router),
        "50C7BF": ("TP-Link (Kasa Smart)", .smartHome),
        "6032B1": ("TP-Link Technologies", .router),
        "98DED0": ("TP-Link Technologies", .router),
        "E848B8": ("TP-Link Technologies", .router),
        "000A37": ("TP-Link Technologies", .router),
        "001D0F": ("TP-Link Technologies", .router),
        "002586": ("TP-Link Technologies", .router),
        "002719": ("TP-Link Technologies", .router),
        "040E3C": ("TP-Link Technologies", .router),
        "1027F5": ("TP-Link Technologies", .router),
        "147590": ("TP-Link (Tapo Smart)", .smartHome),
        "18A6F7": ("TP-Link Technologies", .router),
        "2047DA": ("TP-Link (Deco Mesh)", .router),
        "2469A5": ("TP-Link Technologies", .router),
        "30B5C2": ("TP-Link Technologies", .router),
        "3C46D8": ("TP-Link Technologies", .router),
        "403F8C": ("TP-Link Technologies", .router),
        "503AA0": ("TP-Link Technologies", .router),
        "54AF97": ("TP-Link Technologies", .router),
        "5C63BF": ("TP-Link Technologies", .router),
        "647002": ("TP-Link Technologies", .router),
        "704F57": ("TP-Link Technologies", .router),
        "788A20": ("TP-Link Technologies", .router),
        "7C8BCA": ("TP-Link Technologies", .router),
        "8416F9": ("TP-Link Technologies", .router),
        "90F652": ("TP-Link (Tapo Smart)", .smartHome),
        "9C216A": ("TP-Link Technologies", .router),
        "A42BB0": ("TP-Link Technologies", .router),
        "B0487A": ("TP-Link Technologies", .router),
        "C006C3": ("TP-Link Technologies", .router),
        "D807B6": ("TP-Link Technologies", .router),
        "E4C32A": ("TP-Link Technologies", .router),
        "F4F26D": ("TP-Link Technologies", .router),
        
        // =========================================================================
        // Netgear (Nighthawk, Orbi Mesh, ProSafe)
        // =========================================================================
        "0018E7": ("Netgear", .router),
        "20E52A": ("Netgear", .router),
        "28C68E": ("Netgear", .router),
        "B07FB9": ("Netgear (Orbi Mesh)", .router),
        "00095B": ("Netgear", .router),
        "000FB5": ("Netgear", .router),
        "00146C": ("Netgear", .router),
        "001B2F": ("Netgear", .router),
        "001F33": ("Netgear", .router),
        "0024B2": ("Netgear", .router),
        "0026F2": ("Netgear", .router),
        "04A151": ("Netgear (Nighthawk)", .router),
        "08028E": ("Netgear", .router),
        "0836C9": ("Netgear", .router),
        "100C6B": ("Netgear", .router),
        "10DA43": ("Netgear", .router),
        "204E7F": ("Netgear", .router),
        "2C3033": ("Netgear (Orbi)", .router),
        "30469A": ("Netgear", .router),
        "4494FC": ("Netgear", .router),
        "6C3B6B": ("Netgear", .router),
        "78D294": ("Netgear", .router),
        "841B5E": ("Netgear", .router),
        "9C3DCF": ("Netgear", .router),
        "A00460": ("Netgear", .router),
        "A42B8C": ("Netgear", .router),
        "C0FFD4": ("Netgear", .router),
        "C40415": ("Netgear", .router),
        "D86CE9": ("Netgear", .router),
        "E0469A": ("Netgear", .router),
        
        // =========================================================================
        // ASUSTek Computer / ROG (Routers, Motherboards, Laptops)
        // =========================================================================
        "00248C": ("ASUSTek Computer", .router),
        "04D4C4": ("ASUSTek Computer", .computer),
        "10BF48": ("ASUSTek Computer", .router),
        "000C6E": ("ASUSTek Computer", .computer),
        "000E08": ("ASUSTek Computer", .computer),
        "0011D8": ("ASUSTek Computer", .computer),
        "0013D4": ("ASUSTek Computer", .computer),
        "0015F2": ("ASUSTek Computer", .computer),
        "001731": ("ASUSTek Computer", .computer),
        "0018F3": ("ASUSTek Computer", .computer),
        "001A92": ("ASUSTek Computer", .computer),
        "001BFC": ("ASUSTek Computer", .router),
        "001D60": ("ASUSTek Computer", .router),
        "002215": ("ASUSTek Computer", .computer),
        "002354": ("ASUSTek Computer", .computer),
        "002618": ("ASUSTek Computer", .router),
        "08606E": ("ASUSTek Computer", .router),
        "086266": ("ASUSTek Computer", .router),
        "107B44": ("ASUSTek Computer", .router),
        "14DAE9": ("ASUSTek (ROG Router)", .router),
        "1831BF": ("ASUSTek Computer", .router),
        "20CF30": ("ASUSTek Computer", .router),
        "2C4D54": ("ASUSTek Computer", .router),
        "3085A9": ("ASUSTek Computer", .router),
        "382C4A": ("ASUSTek Computer", .router),
        "40167E": ("ASUSTek Computer", .router),
        "50465D": ("ASUSTek Computer", .router),
        "54A050": ("ASUSTek Computer", .router),
        "6045CB": ("ASUSTek Computer", .router),
        "704D7B": ("ASUSTek Computer", .router),
        "74D02B": ("ASUSTek Computer", .router),
        "88D7F6": ("ASUSTek Computer", .router),
        "90E6BA": ("ASUSTek Computer", .router),
        "AC220B": ("ASUSTek (ZenWiFi)", .router),
        "BC107B": ("ASUSTek Computer", .router),
        "C87F54": ("ASUSTek Computer", .router),
        "D850E6": ("ASUSTek Computer", .router),
        "E03F49": ("ASUSTek Computer", .router),
        "F07959": ("ASUSTek Computer", .router),
        
        // =========================================================================
        // Cisco Systems & Meraki
        // =========================================================================
        "00000C": ("Cisco Systems", .router),
        "000142": ("Cisco Systems", .router),
        "000143": ("Cisco Systems", .router),
        "000164": ("Cisco Systems", .router),
        "000196": ("Cisco Systems", .router),
        "000197": ("Cisco Systems", .router),
        "0001C7": ("Cisco Systems", .router),
        "0001C9": ("Cisco Systems", .router),
        "000216": ("Cisco Systems", .router),
        "000217": ("Cisco Systems", .router),
        "00044D": ("Cisco Systems", .router),
        "00055E": ("Cisco Systems", .router),
        "000784": ("Cisco Systems", .router),
        "0008A3": ("Cisco Systems", .router),
        "00180A": ("Cisco Meraki", .router),
        "0018BA": ("Cisco Systems", .router),
        "34BDFA": ("Cisco Meraki", .router),
        "E0553D": ("Cisco Meraki", .router),
        
        // =========================================================================
        // Ubiquiti Inc. (UniFi, AmpliFi, EdgeRouter, Protect)
        // =========================================================================
        "00156D": ("Ubiquiti Inc.", .router),
        "002722": ("Ubiquiti Inc.", .router),
        "0418D6": ("Ubiquiti (UniFi)", .router),
        "18E829": ("Ubiquiti (UniFi)", .router),
        "24A43C": ("Ubiquiti (UniFi AP)", .router),
        "44D9E7": ("Ubiquiti (UniFi)", .router),
        "68D79A": ("Ubiquiti (AmpliFi)", .router),
        "70A741": ("Ubiquiti (UniFi)", .router),
        "7483C2": ("Ubiquiti (UniFi AP)", .router),
        "802AA8": ("Ubiquiti (UniFi Switch)", .router),
        "AC8B03": ("Ubiquiti (UniFi)", .router),
        "B4FBE4": ("Ubiquiti (UniFi)", .router),
        "DC9FDB": ("Ubiquiti (UniFi Dream Machine)", .router),
        "E063DA": ("Ubiquiti (UniFi)", .router),
        "F09FC2": ("Ubiquiti (UniFi)", .router),
        
        // =========================================================================
        // Xiaomi / Redmi / Roborock (Smartphones, Smart Home, Robot Vacuums)
        // =========================================================================
        "009EE8": ("Xiaomi Communications", .phone),
        "04CF8C": ("Xiaomi Communications", .phone),
        "0C1DAF": ("Xiaomi Communications", .phone),
        "10A4BE": ("Xiaomi Communications", .phone),
        "14F65A": ("Xiaomi (Smart Home)", .smartHome),
        "185936": ("Xiaomi Communications", .phone),
        "286C07": ("Xiaomi Communications", .phone),
        "34CE00": ("Xiaomi Communications", .phone),
        "38A4ED": ("Xiaomi Communications", .phone),
        "3C9180": ("Xiaomi (Smart Camera)", .smartHome),
        "44237C": ("Xiaomi Communications", .phone),
        "508F4C": ("Roborock (Xiaomi Ecosystem)", .smartHome),
        "584498": ("Xiaomi Communications", .phone),
        "640980": ("Xiaomi Communications", .phone),
        "683E34": ("Xiaomi Communications", .phone),
        "742344": ("Xiaomi Communications", .phone),
        "7802F8": ("Xiaomi Communications", .phone),
        "7C49EB": ("Xiaomi (Smart Light)", .smartHome),
        "88366C": ("Xiaomi Communications", .phone),
        "8CBEBE": ("Xiaomi Communications", .phone),
        "98FA9B": ("Xiaomi Communications", .phone),
        "A475B9": ("Xiaomi Communications", .phone),
        "ACF7F3": ("Xiaomi Communications", .phone),
        "B0E235": ("Xiaomi Communications", .phone),
        "C46E7B": ("Xiaomi Communications", .phone),
        "D4970B": ("Xiaomi Communications", .phone),
        "DC3E44": ("Xiaomi Communications", .phone),
        "E4AAEC": ("Xiaomi Communications", .phone),
        "F4F524": ("Xiaomi Communications", .phone),
        
        // =========================================================================
        // Huawei Device / Honor
        // =========================================================================
        "001882": ("Huawei Technologies", .router),
        "001E10": ("Huawei Technologies", .phone),
        "002568": ("Huawei Technologies", .phone),
        "00259E": ("Huawei Technologies", .router),
        "00464B": ("Huawei Technologies", .phone),
        "04021F": ("Huawei Technologies", .phone),
        "04257B": ("Huawei Technologies", .phone),
        "044F4C": ("Huawei Technologies", .phone),
        "047970": ("Huawei Technologies", .phone),
        "0819A6": ("Huawei Technologies", .phone),
        "086361": ("Huawei Technologies", .phone),
        "087A4C": ("Huawei Technologies", .phone),
        "0C37DC": ("Huawei Technologies", .phone),
        "104780": ("Huawei Technologies", .phone),
        "14B968": ("Huawei Technologies", .phone),
        "18D276": ("Huawei Technologies", .phone),
        "246968": ("Huawei Technologies", .phone),
        "384C90": ("Huawei Technologies", .phone),
        "40CB60": ("Huawei Technologies", .phone),
        "4846FB": ("Huawei Technologies", .phone),
        "50016B": ("Huawei Technologies", .phone),
        "70723C": ("Huawei Technologies", .phone),
        "8853D4": ("Huawei Technologies", .phone),
        "A419C4": ("Huawei Technologies", .phone),
        "BC7670": ("Huawei Technologies", .phone),
        "DC094C": ("Huawei Technologies", .phone),
        
        // =========================================================================
        // OnePlus / Oppo / Vivo / Realme
        // =========================================================================
        "2C59E5": ("OnePlus / Oppo", .phone),
        "3438B7": ("OnePlus / Oppo", .phone),
        "3C8375": ("OnePlus / Oppo", .phone),
        "44334C": ("OnePlus / Oppo", .phone),
        "50A054": ("OnePlus / Oppo", .phone),
        "686C73": ("OnePlus / Oppo", .phone),
        "78886D": ("OnePlus / Oppo", .phone),
        "883726": ("OnePlus / Oppo", .phone),
        "987B14": ("Vivo Mobile", .phone),
        "A09347": ("Vivo Mobile", .phone),
        "C0A5DD": ("OnePlus / Oppo", .phone),
        "D81265": ("OnePlus / Oppo", .phone),
        "E4D33A": ("Vivo Mobile", .phone),
        "F4F5E8": ("OnePlus / Oppo", .phone),
        
        // =========================================================================
        // Dell Inc. (Laptops, XPS, Inspiron, Alienware, PowerEdge)
        // =========================================================================
        "00065B": ("Dell Inc.", .computer),
        "000874": ("Dell Inc.", .computer),
        "000BDB": ("Dell Inc.", .computer),
        "000D56": ("Dell Inc.", .computer),
        "000F1F": ("Dell Inc.", .computer),
        "001143": ("Dell Inc.", .computer),
        "00123F": ("Dell Inc.", .computer),
        "001372": ("Dell Inc.", .computer),
        "001422": ("Dell Inc.", .computer),
        "0015C5": ("Dell Inc.", .computer),
        "0016F0": ("Dell Inc.", .computer),
        "00188B": ("Dell Inc.", .computer),
        "0019B9": ("Dell Inc.", .computer),
        "001A64": ("Dell Inc.", .computer),
        "001C23": ("Dell Inc.", .computer),
        "001D09": ("Dell Inc.", .computer),
        "001E4F": ("Dell Inc.", .computer),
        "001E67": ("Dell Inc.", .computer),
        "002170": ("Dell Inc.", .computer),
        "00219B": ("Dell Inc.", .computer),
        "002219": ("Dell Inc.", .computer),
        "0023AE": ("Dell Inc.", .computer),
        "0024E8": ("Dell Inc.", .computer),
        "002564": ("Dell Inc.", .computer),
        "0026B9": ("Dell Inc.", .computer),
        "14FEB5": ("Dell Inc.", .computer),
        "180373": ("Dell Inc.", .computer),
        "1866DA": ("Dell Inc.", .computer),
        "24B6FD": ("Dell Inc.", .computer),
        "3417EB": ("Dell Inc.", .computer),
        "4C7625": ("Dell Inc.", .computer),
        "549F35": ("Dell Inc.", .computer),
        "74867A": ("Dell Inc.", .computer),
        "847BEB": ("Dell Inc.", .computer),
        "90B11C": ("Dell Inc.", .computer),
        "B8AC6F": ("Dell Inc.", .computer),
        "BC305B": ("Dell Inc.", .computer),
        "D4BED9": ("Dell Inc.", .computer),
        "ECF4BB": ("Dell Inc.", .computer),
        "F01FAF": ("Dell Inc.", .computer),
        "F8DB88": ("Dell Inc.", .computer),
        
        // =========================================================================
        // HP / Hewlett-Packard (Laptops, Desktops, LaserJet, OfficeJet Printers)
        // =========================================================================
        "0001E6": ("HP (Hewlett-Packard)", .computer),
        "000802": ("HP (Hewlett-Packard)", .computer),
        "000B46": ("HP (Hewlett-Packard)", .computer),
        "000E7F": ("HP (Hewlett-Packard)", .computer),
        "00110A": ("HP (Hewlett-Packard)", .printer),
        "001185": ("HP (Hewlett-Packard)", .printer),
        "001279": ("HP (Hewlett-Packard)", .computer),
        "001321": ("HP (Hewlett-Packard)", .computer),
        "001438": ("HP (Hewlett-Packard)", .printer),
        "0014C2": ("HP (Hewlett-Packard)", .computer),
        "001560": ("HP (Hewlett-Packard)", .computer),
        "001635": ("HP (Hewlett-Packard)", .computer),
        "001708": ("HP (Hewlett-Packard)", .printer),
        "0017A4": ("HP (Hewlett-Packard)", .computer),
        "001871": ("HP (Hewlett-Packard)", .printer),
        "0018FE": ("HP (Hewlett-Packard)", .computer),
        "0019BB": ("HP (Hewlett-Packard)", .computer),
        "001A4B": ("HP (Hewlett-Packard)", .printer),
        "001B78": ("HP (Hewlett-Packard)", .computer),
        "001CC4": ("HP (Hewlett-Packard)", .computer),
        "001E0B": ("HP (Hewlett-Packard)", .printer),
        "001F29": ("HP (Hewlett-Packard)", .computer),
        "00215A": ("HP (Hewlett-Packard)", .computer),
        "002264": ("HP (Hewlett-Packard)", .computer),
        "00237D": ("HP (Hewlett-Packard)", .computer),
        "002481": ("HP (Hewlett-Packard)", .computer),
        "0025B3": ("HP (Hewlett-Packard)", .computer),
        "002655": ("HP (Hewlett-Packard)", .computer),
        "040973": ("HP (Hewlett-Packard)", .computer),
        "101F74": ("HP (Hewlett-Packard)", .computer),
        "10604B": ("HP (Hewlett-Packard)", .printer),
        "186024": ("HP (Hewlett-Packard)", .printer),
        "2C27D7": ("HP (Hewlett-Packard)", .printer),
        "3CD92B": ("HP (OfficeJet / LaserJet)", .printer),
        "705A0F": ("HP (Color LaserJet)", .printer),
        "843497": ("HP (Hewlett-Packard)", .printer),
        "A0D3C1": ("HP (Hewlett-Packard)", .printer),
        "C8D3FF": ("HP (Hewlett-Packard)", .printer),
        
        // =========================================================================
        // Lenovo / Motorola (ThinkPad, Yoga, Legion, Moto Phones)
        // =========================================================================
        "0004BD": ("Motorola Mobility", .phone),
        "000A28": ("Motorola Mobility", .phone),
        "000E0C": ("Lenovo", .computer),
        "000E35": ("Motorola Mobility", .phone),
        "000EE8": ("Motorola Mobility", .phone),
        "00113B": ("Motorola Mobility", .phone),
        "0012EE": ("Motorola Mobility", .phone),
        "001404": ("Motorola Mobility", .phone),
        "001558": ("Lenovo", .computer),
        "0016B4": ("Motorola Mobility", .phone),
        "0017EE": ("Motorola Mobility", .phone),
        "0019C4": ("Lenovo", .computer),
        "001A1B": ("Motorola Mobility", .phone),
        "001B66": ("Motorola Mobility", .phone),
        "001C6A": ("Motorola Mobility", .phone),
        "001E46": ("Motorola Mobility", .phone),
        "001F77": ("Motorola Mobility", .phone),
        "00214C": ("Lenovo", .computer),
        "002368": ("Lenovo", .computer),
        "00247E": ("Motorola Mobility", .phone),
        "002622": ("Motorola Mobility", .phone),
        "044B80": ("Lenovo", .computer),
        "0452F3": ("Lenovo", .computer),
        "183451": ("Lenovo (ThinkPad)", .computer),
        "289A4B": ("Lenovo (Yoga)", .computer),
        "3052CB": ("Lenovo", .computer),
        "407496": ("Motorola (Moto G)", .phone),
        "54E1AD": ("Lenovo", .computer),
        "64BC0C": ("Lenovo", .computer),
        "707781": ("Lenovo", .computer),
        "80CE62": ("Lenovo (Legion)", .computer),
        "98FC11": ("Lenovo", .computer),
        "A4119B": ("Motorola (Moto Edge)", .phone),
        "B88AEC": ("Lenovo", .computer),
        "C8348E": ("Lenovo", .computer),
        "D46D6D": ("Lenovo", .computer),
        "E09D31": ("Lenovo", .computer),
        "F48C50": ("Lenovo", .computer),
        
        // =========================================================================
        // Intel Corporation (Wi-Fi 6/7, NUCs, Motherboards)
        // =========================================================================
        "0002B3": ("Intel Corporation", .computer),
        "000347": ("Intel Corporation", .computer),
        "000423": ("Intel Corporation", .computer),
        "0007E9": ("Intel Corporation", .computer),
        "000CF1": ("Intel Corporation", .computer),
        "001111": ("Intel Corporation", .computer),
        "0012F0": ("Intel Corporation", .computer),
        "001302": ("Intel Corporation", .computer),
        "001320": ("Intel Corporation", .computer),
        "0013E8": ("Intel Corporation", .computer),
        "001500": ("Intel Corporation", .computer),
        "001517": ("Intel Corporation", .computer),
        "00166F": ("Intel Corporation", .computer),
        "001676": ("Intel Corporation", .computer),
        "0018DE": ("Intel Corporation", .computer),
        "0019D1": ("Intel Corporation", .computer),
        "001B21": ("Intel Corporation", .computer),
        "001B77": ("Intel Corporation", .computer),
        "001C25": ("Intel Corporation", .computer),
        "001C26": ("Intel Corporation", .computer),
        "001D72": ("Intel Corporation", .computer),
        "001E64": ("Intel Corporation", .computer),
        "001E65": ("Intel Corporation", .computer),
        "001E67": ("Intel Corporation", .computer),
        "001F3B": ("Intel Corporation", .computer),
        "001F3C": ("Intel Corporation", .computer),
        "00215C": ("Intel Corporation", .computer),
        "00216A": ("Intel Corporation", .computer),
        "00216B": ("Intel Corporation", .computer),
        "00224D": ("Intel Corporation", .computer),
        "0022FB": ("Intel Corporation", .computer),
        "002314": ("Intel Corporation", .computer),
        "002315": ("Intel Corporation", .computer),
        "0024D6": ("Intel Corporation", .computer),
        "0024D7": ("Intel Corporation", .computer),
        "0026C6": ("Intel Corporation", .computer),
        "0026C7": ("Intel Corporation", .computer),
        "081196": ("Intel Corporation", .computer),
        "087190": ("Intel Corporation", .computer),
        "08D23E": ("Intel Corporation", .computer),
        "1002B5": ("Intel Corporation", .computer),
        "144F8A": ("Intel Corporation", .computer),
        "247703": ("Intel Corporation", .computer),
        "3413E8": ("Intel Corporation", .computer),
        "48A472": ("Intel Corporation", .computer),
        "589CFC": ("Intel Corporation", .computer),
        "6805CA": ("Intel Corporation", .computer),
        "7CF82B": ("Intel Corporation", .computer),
        "8086F2": ("Intel Corporation", .computer),
        "84A93E": ("Intel Corporation", .computer),
        "94E6F7": ("Intel Corporation", .computer),
        "A0AF69": ("Intel Corporation", .computer),
        "A44CC8": ("Intel Corporation", .computer),
        "B49691": ("Intel Corporation", .computer),
        "C85B76": ("Intel Corporation", .computer),
        "F42679": ("Intel Corporation", .computer),
        
        // =========================================================================
        // Espressif Systems (ESP8266 & ESP32 Smart IoT Modules, Microcontrollers)
        // =========================================================================
        "18FE34": ("Espressif (ESP8266 IoT)", .smartHome),
        "240AC4": ("Espressif (ESP32 IoT)", .smartHome),
        "246F28": ("Espressif (ESP32-S2)", .smartHome),
        "24B2DE": ("Espressif (ESP32 IoT)", .smartHome),
        "30AEA4": ("Espressif (ESP32 IoT)", .smartHome),
        "349454": ("Espressif (ESP32-C3)", .smartHome),
        "3C6105": ("Espressif (ESP32 IoT)", .smartHome),
        "3C71BF": ("Espressif (ESP8266 IoT)", .smartHome),
        "4827E2": ("Espressif (ESP32 IoT)", .smartHome),
        "4C7525": ("Espressif (ESP32 IoT)", .smartHome),
        "545A46": ("Espressif (ESP8266 IoT)", .smartHome),
        "58BF25": ("Espressif (ESP32 IoT)", .smartHome),
        "600194": ("Espressif (ESP8266 IoT)", .smartHome),
        "68C63A": ("Espressif (ESP32 IoT)", .smartHome),
        "840D8E": ("Espressif (ESP8266 IoT)", .smartHome),
        "84CCA8": ("Espressif (ESP32 IoT)", .smartHome),
        "84F3EB": ("Espressif (ESP8266 IoT)", .smartHome),
        "9097D5": ("Espressif (ESP32 IoT)", .smartHome),
        "A020A6": ("Espressif (ESP8266 IoT)", .smartHome),
        "A4CF12": ("Espressif (ESP8266 IoT)", .smartHome),
        "AC67B2": ("Espressif (ESP32 IoT)", .smartHome),
        "B4E62D": ("Espressif (ESP32 IoT)", .smartHome),
        "BCDD42": ("Espressif (ESP32 IoT)", .smartHome),
        "C44F33": ("Espressif (ESP8266 IoT)", .smartHome),
        "C82B96": ("Espressif (ESP32 IoT)", .smartHome),
        "CC50E3": ("Espressif (ESP32 IoT)", .smartHome),
        "D8A01D": ("Espressif (ESP32 IoT)", .smartHome),
        "DC4F22": ("Espressif (ESP8266 IoT)", .smartHome),
        "E09806": ("Espressif (ESP32 IoT)", .smartHome),
        "E8DB84": ("Espressif (ESP32 IoT)", .smartHome),
        
        // =========================================================================
        // Tuya Smart / Smart Life IoT Devices
        // =========================================================================
        "105A17": ("Tuya Smart", .smartHome),
        "1869D8": ("Tuya Smart", .smartHome),
        "1C5216": ("Tuya Smart", .smartHome),
        "20C9D0": ("Tuya Smart", .smartHome),
        "286DCD": ("Tuya Smart", .smartHome),
        "381F8D": ("Tuya Smart", .smartHome),
        "407B08": ("Tuya Smart", .smartHome),
        "443719": ("Tuya Smart", .smartHome),
        "508A06": ("Tuya Smart", .smartHome),
        "68572D": ("Tuya Smart", .smartHome),
        "708976": ("Tuya Smart", .smartHome),
        "841715": ("Tuya Smart", .smartHome),
        "8CAAB5": ("Tuya Smart", .smartHome),
        "94B40F": ("Tuya Smart", .smartHome),
        "A09208": ("Tuya Smart", .smartHome),
        "B0C554": ("Tuya Smart", .smartHome),
        "B43916": ("Tuya Smart", .smartHome),
        "C05D89": ("Tuya Smart", .smartHome),
        "D4D2D6": ("Tuya Smart", .smartHome),
        "DC421F": ("Tuya Smart", .smartHome),
        "E43A1B": ("Tuya Smart", .smartHome),
        "E8F791": ("Tuya Smart", .smartHome),
        "F8798C": ("Tuya Smart", .smartHome),
        
        // =========================================================================
        // Sonos (Smart Speakers, Soundbars, Subwoofers)
        // =========================================================================
        "000E58": ("Sonos Inc.", .smartHome),
        "347E5C": ("Sonos Inc.", .smartHome),
        "48A6B8": ("Sonos (Era / Arc)", .smartHome),
        "542A1B": ("Sonos (Beam)", .smartHome),
        "5C313E": ("Sonos Inc.", .smartHome),
        "7828CA": ("Sonos (Move / Roam)", .smartHome),
        "949F3E": ("Sonos (One)", .smartHome),
        "B8E937": ("Sonos (Sub)", .smartHome),
        "F0F6C1": ("Sonos Inc.", .smartHome),
        
        // =========================================================================
        // Roku (Streaming Stick, Roku TV, Streambar)
        // =========================================================================
        "000D4B": ("Roku Inc.", .tv),
        "080581": ("Roku Inc.", .tv),
        "20F543": ("Roku (Streaming Stick)", .tv),
        "2C1A31": ("Roku (Express)", .tv),
        "74A34A": ("Roku Inc.", .tv),
        "7831C1": ("Roku (Ultra)", .tv),
        "84EA99": ("Roku Inc.", .tv),
        "AC3A7A": ("Roku Inc.", .tv),
        "B0A737": ("Roku (Smart TV)", .tv),
        "C83A35": ("Roku Inc.", .tv),
        "D43A26": ("Roku Inc.", .tv),
        "DC3A5E": ("Roku (Streambar)", .tv),
        "E0678E": ("Roku Inc.", .tv),
        
        // =========================================================================
        // Network Attached Storage (Synology & QNAP)
        // =========================================================================
        "001132": ("Synology Inc. (DiskStation)", .computer),
        "00089B": ("QNAP Systems", .computer),
        "001558": ("QNAP Systems (TurboNAS)", .computer),
        "002165": ("Synology Inc.", .computer),
        "245EBE": ("QNAP Systems", .computer),
        
        // =========================================================================
        // Other Network Hardware & Printers
        // =========================================================================
        "000085": ("Canon", .printer),
        "001E8F": ("Canon (PIXMA)", .printer),
        "0021B7": ("Epson", .printer),
        "0026AB": ("Epson (EcoTank)", .printer),
        "008077": ("Brother Industries", .printer),
        "30055C": ("Brother Industries", .printer),
        "180C4E": ("Canon", .printer),
        "444390": ("Epson", .printer),
        "7467F7": ("Brother Industries", .printer),
        "B499BA": ("Canon", .printer),
        "000420": ("Slim Devices", .smartHome),
        "001B63": ("Apple AirPort", .router),
        "000C43": ("Ralink / MediaTek", .router)
    ]
    
    // MARK: - Local Bundle Database Loader
    
    /// Loads the complete IEEE 52,000+ entries database from the app bundle resource (oui.txt)
    public static func loadDatabaseIfNeeded() {
        lock.lock()
        if fullDatabase != nil || isDatabaseLoading {
            lock.unlock()
            return
        }
        isDatabaseLoading = true
        lock.unlock()
        
        DispatchQueue.global(qos: .userInitiated).async {
            var dict: [String: String] = [:]
            dict.reserveCapacity(53000)
            
            var content: String? = nil
            if let url = Bundle.main.url(forResource: "oui", withExtension: "txt") {
                content = try? String(contentsOf: url, encoding: .utf8)
            }
            
            if let text = content {
                text.enumerateLines { line, _ in
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return }
                    let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
                    guard parts.count == 2 else { return }
                    let p = String(parts[0]).uppercased()
                    let v = String(parts[1]).trimmingCharacters(in: .whitespaces)
                    dict[p] = v
                }
            }
            
            lock.lock()
            fullDatabase = dict
            isDatabaseLoading = false
            lock.unlock()
        }
    }
    
    // MARK: - Synchronous Fast Lookup
    
    public static func lookup(macAddress: String) -> (vendor: String, defaultType: DeviceType)? {
        let clean = macAddress.uppercased().replacingOccurrences(of: ":", with: "")
                                           .replacingOccurrences(of: "-", with: "")
                                           .replacingOccurrences(of: ".", with: "")
        guard clean.count >= 6 else { return nil }
        let prefix = String(clean.prefix(6))
        
        // 1. Check online cache first
        lock.lock()
        if let cached = onlineCache[prefix] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        
        // 2. Check built-in high-priority major brands
        if let match = vendorPrefixes[prefix] {
            return match
        }
        
        // 3. Check loaded full 52,000+ IEEE database
        loadDatabaseIfNeeded()
        lock.lock()
        let full = fullDatabase
        lock.unlock()
        
        if let vendor = full?[prefix] {
            let devType = inferDeviceType(hostname: "", vendor: vendor)
            return (vendor, devType)
        }
        
        return nil
    }
    
    // MARK: - Asynchronous Online Internet Lookup
    
    /// Searches online MAC vendor databases (api.maclookup.app & api.macvendors.com)
    /// to fetch real-time manufacturer information when local databases do not contain the prefix.
    public static func lookupOnline(macAddress: String) async -> (vendor: String, defaultType: DeviceType)? {
        let clean = macAddress.uppercased().replacingOccurrences(of: ":", with: "")
                                           .replacingOccurrences(of: "-", with: "")
                                           .replacingOccurrences(of: ".", with: "")
        guard clean.count >= 6 else { return nil }
        let prefix = String(clean.prefix(6))
        
        // Check cache
        lock.lock()
        if let cached = onlineCache[prefix] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        
        // 1. Primary Service: api.maclookup.app (Structured JSON, synced with IEEE)
        if let url = URL(string: "https://api.maclookup.app/v2/macs/\(prefix)") {
            var request = URLRequest(url: url)
            request.timeoutInterval = 4.0
            request.setValue("NetScan-iOS/1.0", forHTTPHeaderField: "User-Agent")
            
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                if let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200,
                   let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let found = json["found"] as? Bool, found,
                   let company = json["company"] as? String, !company.trimmingCharacters(in: .whitespaces).isEmpty {
                    let cleanedCompany = company.trimmingCharacters(in: .whitespacesAndNewlines)
                    let devType = inferDeviceType(hostname: "", vendor: cleanedCompany)
                    let result = (cleanedCompany, devType)
                    
                    lock.lock()
                    onlineCache[prefix] = result
                    lock.unlock()
                    return result
                }
            } catch {
                // Continue to secondary fallback
            }
        }
        
        // 2. Secondary Service: api.macvendors.com
        let formattedMac = String(format: "%@:%@:%@:%@:%@:%@",
                                  String(clean.prefix(2)),
                                  String(clean.dropFirst(2).prefix(2)),
                                  String(clean.dropFirst(4).prefix(2)),
                                  clean.count >= 8 ? String(clean.dropFirst(6).prefix(2)) : "00",
                                  clean.count >= 10 ? String(clean.dropFirst(8).prefix(2)) : "00",
                                  clean.count >= 12 ? String(clean.dropFirst(10).prefix(2)) : "00")
        
        if let url = URL(string: "https://api.macvendors.com/\(formattedMac)") {
            var request = URLRequest(url: url)
            request.timeoutInterval = 4.0
            request.setValue("NetScan-iOS/1.0", forHTTPHeaderField: "User-Agent")
            
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                if let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200,
                   let vendorStr = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !vendorStr.isEmpty && !vendorStr.contains("errors") && !vendorStr.contains("Not Found") {
                    let devType = inferDeviceType(hostname: "", vendor: vendorStr)
                    let result = (vendorStr, devType)
                    
                    lock.lock()
                    onlineCache[prefix] = result
                    lock.unlock()
                    return result
                }
            } catch {
                // Online search failed
            }
        }
        
        return nil
    }
    
    // MARK: - Device Classification & Heuristics
    
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
           lowerHost.contains("mesh") || lowerHost.contains("openwrt") || lowerHost.contains("unifi") {
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
           lowerHost.contains("tasmota") || lowerHost.contains("esp32") || lowerHost.contains("esp8266") ||
           lowerHost.contains("sonos") {
            return .smartHome
        }
        
        if lowerVendor.contains("apple") { return .phone }
        if lowerVendor.contains("samsung") { return .phone }
        if lowerVendor.contains("tp-link") || lowerVendor.contains("netgear") || lowerVendor.contains("asus") ||
           lowerVendor.contains("cisco") || lowerVendor.contains("ubiquiti") { return .router }
        if lowerVendor.contains("espressif") || lowerVendor.contains("tuya") || lowerVendor.contains("sonos") { return .smartHome }
        if lowerVendor.contains("hp") || lowerVendor.contains("canon") || lowerVendor.contains("epson") || lowerVendor.contains("brother") { return .printer }
        if lowerVendor.contains("amazon") { return .smartHome }
        if lowerVendor.contains("sony") { return .tv }
        if lowerVendor.contains("nintendo") || lowerVendor.contains("playstation") || lowerVendor.contains("xbox") { return .gaming }
        if lowerVendor.contains("dell") || lowerVendor.contains("lenovo") || lowerVendor.contains("intel") || lowerVendor.contains("synology") || lowerVendor.contains("qnap") { return .computer }
        
        return .unknown
    }
    
    // MARK: - Synchronous Identification
    
    public static func identifyDevice(macAddress: String?, hostname: String) -> (vendor: String, deviceType: DeviceType) {
        // 1. Direct MAC OUI lookup (built-in + bundle 52,000+ entries)
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
    
    // MARK: - Asynchronous Identification (With Online Internet Search Fallback)
    
    public static func identifyDeviceAsync(macAddress: String?, hostname: String) async -> (vendor: String, deviceType: DeviceType) {
        // Fast local lookup first
        let local = identifyDevice(macAddress: macAddress, hostname: hostname)
        if local.vendor != "Network Device" && local.vendor != "Unknown" && !local.vendor.isEmpty {
            return local
        }
        
        // Fallback: If local lookup failed, search from the Internet
        if let mac = macAddress, !mac.isEmpty, !mac.contains("Unknown") && !mac.contains("Restricted") {
            if let online = await lookupOnline(macAddress: mac) {
                let type = inferDeviceType(hostname: hostname, vendor: online.vendor)
                return (online.vendor, type == .unknown ? online.defaultType : type)
            }
        }
        
        return local
    }
}
