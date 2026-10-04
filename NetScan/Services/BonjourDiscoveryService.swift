//
//  BonjourDiscoveryService.swift
//  NetScan
//
//  Discovers mDNS / Bonjour services to identify device names and capabilities.
//

import Foundation
import Network

public class BonjourDiscoveryService {
    public static let shared = BonjourDiscoveryService()
    
    private var browsers: [NWBrowser] = []
    private var discoveredNames: [String: String] = [:] // IP or Host -> Friendly Bonjour Name
    
    public let serviceTypes = [
        "_http._tcp",
        "_airplay._tcp",
        "_googlecast._tcp",
        "_smb._tcp",
        "_companion-link._tcp",
        "_raop._tcp",
        "_printer._tcp",
        "_ipp._tcp",
        "_ssh._tcp",
        "_workstation._tcp",
        "_device-info._tcp"
    ]
    
    public init() {}
    
    public func startBrowsing(onServiceFound: @escaping (String, String) -> Void) {
        stopBrowsing()
        
        for type in serviceTypes {
            let descriptor = NWBrowser.Descriptor.bonjour(type: type, domain: "local.")
            let parameters = NWParameters()
            parameters.prohibitedInterfaceTypes = [.cellular]
            
            let browser = NWBrowser(for: descriptor, using: parameters)
            browser.browseResultsChangedHandler = { results, changes in
                for result in results {
                    if case let .service(name, _, _, _) = result.endpoint {
                        onServiceFound(name, type)
                    }
                }
            }
            
            browser.start(queue: .global())
            browsers.append(browser)
        }
    }
    
    public func stopBrowsing() {
        for browser in browsers {
            browser.cancel()
        }
        browsers.removeAll()
    }
}
