import Foundation

public enum CheckCoverage: String, Codable {
    case pending = "In progress"
    case completed = "Completed"
    case cancelled = "Incomplete: cancelled"
}

public struct DeviceObservation: Codable, Identifiable {
    public var id: UUID
    public var address: String
    public var hostname: String
    public var mac: String
    public var name: String
    public var category: DeviceType
    public var vendor: String
    public var match: SavedDeviceMatch
    public var openPorts: [Int]
    public var assessedPorts: [Int]
    public var serviceState: ServiceCheckState

    init(_ device: NetworkDevice) {
        id = device.inventoryID ?? device.id
        address = device.ipAddress
        hostname = device.hasResolvedHostname ? device.hostname : ""
        mac = device.hasKnownMACAddress ? device.macAddress : ""
        name = device.displayName
        category = device.deviceType
        vendor = device.vendor
        match = device.savedMatch
        openPorts = device.openPorts.sorted()
        assessedPorts = device.assessedPorts.sorted()
        serviceState = device.serviceCheckState
    }
}

public struct ScanChange: Identifiable {
    public var id: String
    public var title: String
    public var detail: String
}

public struct ScanSnapshot: Codable, Identifiable {
    public var id: UUID
    public var network: String
    public var date: Date
    public var identityCoverage: CheckCoverage
    public var serviceCoverage: CheckCoverage
    public var devices: [DeviceObservation]

    public func changes(since previous: ScanSnapshot?) -> [ScanChange] {
        guard let previous = previous else { return [] }
        var changes: [ScanChange] = []
        for device in devices {
            guard let old = previous.devices.first(where: { $0.id == device.id }) else {
                changes.append(ScanChange(id: "new-\(device.id)", title: "New observation", detail: device.name))
                continue
            }
            if old.address != device.address && device.match != .address {
                changes.append(ScanChange(id: "ip-\(device.id)", title: "Address changed", detail: "\(device.name): \(old.address) → \(device.address)"))
            }
            let comparable = Set(old.assessedPorts).intersection(device.assessedPorts)
            for port in comparable.sorted() where old.openPorts.contains(port) != device.openPorts.contains(port) {
                let title = device.openPorts.contains(port) ? "Port now reachable" : "Port no longer detected"
                changes.append(ScanChange(id: "port-\(device.id)-\(port)", title: title, detail: "\(device.name): TCP \(port)"))
            }
        }
        for device in previous.devices where !devices.contains(where: { $0.id == device.id }) {
            changes.append(ScanChange(id: "missing-\(device.id)", title: "Not seen this scan", detail: device.name))
        }
        return changes
    }
}

/// Owned by the list model on the main queue. Only immutable file snapshots cross the writer queue.
public final class DeviceInventory {
    private struct Record: Codable {
        var id: UUID
        var address: String
        var hostname: String
        var mac: String
        var annotation: DeviceAnnotation
    }
    private struct State: Codable {
        var version = 1
        var records: [String: [Record]] = [:]
        var scans: [ScanSnapshot] = []
    }
    private var state = State()
    private let file: URL?
    private let writer = DispatchQueue(label: "com.netscan.inventory-file")
    public private(set) var storageMessage: String?
    public var didFailToSave: (() -> Void)?
    private var pendingWrite: DispatchWorkItem?
    private var preserveUnreadableFile = false
    private var writeRevision = 0

    public init(file: URL? = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
        .appendingPathComponent("NetScan/inventory-v1.json")) {
        self.file = file
        guard let file = file, FileManager.default.fileExists(atPath: file.path) else { return }
        do {
            let loaded = try JSONDecoder().decode(State.self, from: Data(contentsOf: file))
            guard loaded.version == 1 else { preserveUnreadableFile = true; storageMessage = "Saved inventory uses an unsupported version. It has not been overwritten."; return }
            state = loaded
        } catch {
            preserveUnreadableFile = true
            storageMessage = "Saved inventory could not be read. It has not been overwritten."
        }
    }

    public func history(network: String) -> [ScanSnapshot] { state.scans.filter { $0.network == network } }
    public var allHistory: [ScanSnapshot] { state.scans }

    public static func networkScope(_ interface: NetworkInterfaceInfo) -> String {
        let parts = interface.ipAddress.split(separator: ".").compactMap { UInt32($0) }
        var network = interface.ipAddress
        if parts.count == 4 && parts.allSatisfy({ $0 < 256 }) && (0...32).contains(interface.cidrPrefix) {
            let value = parts.reduce(UInt32(0)) { ($0 << 8) | $1 }
            let mask: UInt32 = interface.cidrPrefix == 0 ? 0 : UInt32.max << (32 - interface.cidrPrefix)
            let base = value & mask
            network = [24, 16, 8, 0].map { String((base >> $0) & 255) }.joined(separator: ".")
        }
        let bssid = ["", "00:11:22:33:44:55", "02:00:00:00:00:00"].contains(interface.bssid.lowercased()) ? "" : interface.bssid.lowercased()
        return [interface.ssid, bssid, "\(network)/\(interface.cidrPrefix)", interface.gatewayIP].joined(separator: "|")
    }

    private static func host(_ device: NetworkDevice) -> String {
        device.hasResolvedHostname ? device.hostname.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ". ")) : ""
    }
    private static func mac(_ device: NetworkDevice) -> String {
        device.hasKnownMACAddress ? device.macAddress.lowercased().filter { $0.isHexDigit } : ""
    }

    public func associate(_ device: NetworkDevice, network: String, certainNetwork: Bool,
                          duplicateHostnames: Set<String> = [], duplicateMACs: Set<String> = []) -> NetworkDevice {
        var device = device
        var records = state.records[network] ?? []
        let mac = Self.mac(device), host = Self.host(device)
        let compatible: (Record) -> Bool = { mac.isEmpty || $0.mac.isEmpty || mac == $0.mac }
        var index: Int?
        var match: SavedDeviceMatch = .none
        if !mac.isEmpty && !duplicateMACs.contains(mac) {
            let matches = records.indices.filter { records[$0].mac == mac }
            if matches.count == 1 { index = matches[0]; match = .mac }
        }
        if index == nil && !host.isEmpty && !duplicateHostnames.contains(host) && !duplicateMACs.contains(mac) {
            let candidates = records.indices.filter { records[$0].hostname == host && compatible(records[$0]) }
            if candidates.count == 1 { index = candidates[0]; match = .hostname }
        }
        if index == nil {
            index = records.firstIndex { record in
                record.address == device.ipAddress && compatible(record) &&
                (host.isEmpty || record.hostname.isEmpty || record.hostname == host)
            }
            if index != nil { match = .address }
        }
        // Keep a current user edit attached while its automatic identity becomes more complete.
        if let currentID = device.inventoryID, device.savedMatch == .current,
           let current = records.firstIndex(where: { $0.id == currentID && compatible($0) }) {
            index = current
            match = .current
        }
        if let index = index {
            device.inventoryID = records[index].id
            device.annotation = records[index].annotation
            device.savedMatch = certainNetwork || match == .current ? match : .address
            if device.savedMatch == .address || device.savedMatch == .hostname { device.annotation.recognized = false }
            records[index].address = device.ipAddress
            if !host.isEmpty { records[index].hostname = host }
            if !mac.isEmpty { records[index].mac = mac }
        } else {
            let record = Record(id: UUID(), address: device.ipAddress, hostname: host, mac: mac, annotation: DeviceAnnotation())
            records.append(record)
            device.inventoryID = record.id
        }
        state.records[network] = records
        return device
    }

    public func saveAnnotation(_ annotation: DeviceAnnotation, device: NetworkDevice, network: String) {
        guard let id = device.inventoryID, let index = state.records[network]?.firstIndex(where: { $0.id == id }) else { return }
        state.records[network]?[index].annotation = annotation
        persist()
    }

    public func recordScan(id: UUID, network: String, devices: [NetworkDevice], date: Date = Date()) {
        state.scans.insert(ScanSnapshot(id: id, network: network, date: date, identityCoverage: .pending,
                                       serviceCoverage: .pending, devices: devices.map(DeviceObservation.init)), at: 0)
        state.scans = Array(state.scans.prefix(20))
        persist()
    }

    public func updateScan(id: UUID, devices: [NetworkDevice], identity: CheckCoverage, services: CheckCoverage) {
        guard let index = state.scans.firstIndex(where: { $0.id == id }) else { return }
        state.scans[index].devices = devices.map(DeviceObservation.init)
        state.scans[index].identityCoverage = identity
        state.scans[index].serviceCoverage = services
        persist()
    }

    private func persist() {
        guard !preserveUnreadableFile, let file = file else { return }
        pendingWrite?.cancel()
        writeRevision += 1
        let revision = writeRevision
        let snapshot = state
        let work = DispatchWorkItem { [weak self] in
            do {
                try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try JSONEncoder().encode(snapshot).write(to: file, options: .atomic)
                self?.reportWriteResult(success: true, revision: revision)
            } catch {
                self?.reportWriteResult(success: false, revision: revision)
            }
        }
        pendingWrite = work
        writer.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    private func reportWriteResult(success: Bool, revision: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.writeRevision == revision else { return }
            self.storageMessage = success ? nil : "Changes could not be saved on this iPhone. The last saved inventory has been preserved."
            self.didFailToSave?()
        }
    }

    /// Used before leaving the foreground and by persistence regressions.
    @discardableResult public func flush() -> Bool {
        pendingWrite?.cancel()
        writeRevision += 1
        guard !preserveUnreadableFile else { return false }
        guard let file = file else { return true }
        let snapshot = state
        let success = writer.sync { () -> Bool in
            do {
                try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try JSONEncoder().encode(snapshot).write(to: file, options: .atomic)
                return true
            } catch { return false }
        }
        storageMessage = success ? nil : "Changes could not be saved on this iPhone. The last saved inventory has been preserved."
        didFailToSave?()
        return success
    }
}
