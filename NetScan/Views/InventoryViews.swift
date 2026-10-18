import SwiftUI
import UniformTypeIdentifiers

struct DeviceInventoryEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var annotation: DeviceAnnotation
    let save: (DeviceAnnotation) -> Void

    init(device: NetworkDevice, save: @escaping (DeviceAnnotation) -> Void) {
        var value = device.annotation
        if device.savedMatch == .address || device.savedMatch == .hostname { value.recognized = false }
        _annotation = State(initialValue: value)
        self.save = save
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Your device label") {
                    TextField("Name, e.g. GoodWe Inverter", text: $annotation.name)
                        .accessibilityIdentifier("device-name")
                    TextField("Location", text: $annotation.location)
                        .accessibilityIdentifier("device-location")
                    TextField("Notes", text: $annotation.notes, axis: .vertical)
                        .lineLimit(3...6)
                        .accessibilityIdentifier("device-notes")
                    Toggle("I recognize this device", isOn: $annotation.recognized)
                }
                Section {
                    Text("Labels are stored on this iPhone. Recognition records your own identification; service risks still apply. A hostname or address match on a later scan needs verification, especially if the network name is unavailable.")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            .navigationTitle("Edit Device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        annotation.name = String(annotation.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
                        annotation.location = String(annotation.location.prefix(120))
                        annotation.notes = String(annotation.notes.prefix(2000))
                        save(annotation)
                        dismiss()
                    }.accessibilityIdentifier("save-device")
                }
            }
        }
    }
}

struct SavedDeviceSection: View {
    let device: NetworkDevice
    var body: some View {
        Section("Your saved identity") {
            if device.annotation.isEmpty {
                Text("Use Edit to add a name, location, and notes.").foregroundColor(.secondary)
            } else {
                Text(verbatim: device.savedMatch.rawValue)
                    .font(.caption).foregroundColor(device.savedMatch == .current || device.savedMatch == .mac ? .secondary : .orange)
                if !device.annotation.location.isEmpty { Label { Text(verbatim: device.annotation.location) } icon: { Image(systemName: "mappin") } }
                if !device.annotation.notes.isEmpty { Text(verbatim: device.annotation.notes) }
                if device.annotation.recognized {
                    Text(device.savedMatch == .current ? "Recognized by you this scan" : "Previously recognized by you; check the saved association above")
                        .font(.caption)
                }
            }
        }
    }
}

struct IdentityEvidenceSection: View {
    let device: NetworkDevice
    var body: some View {
        Section(header: Text("Identification evidence"), footer: Text("Names and web headers are self-reported. Manufacturer allocations can identify a component rather than the appliance. Inferred classifications and saved labels are not proof of identity.")) {
            if device.hasResolvedHostname {
                LabeledContent("Observed hostname") { Text(verbatim: device.hostname) }
            }
            if device.hasKnownMACAddress {
                LabeledContent("Supplied MAC") { Text(verbatim: device.macAddress) }
            }
            if device.evidence.isEmpty { Text("No additional identification evidence yet.").foregroundColor(.secondary) }
            ForEach(device.evidence) { evidence in
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: evidence.source).font(.subheadline.weight(.semibold))
                    Text(verbatim: evidence.observation).font(.caption)
                    Text(evidence.date, style: .time).font(.caption2).foregroundColor(.secondary)
                }
            }
        }
    }
}

struct ScanHistoryView: View {
    @ObservedObject var model: DeviceListViewModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("The latest 20 completed discoveries are stored on this iPhone. Not seen does not mean offline. Changes compare only matching network profiles and ports with definite responses in both scans. Hidden network names and reused addresses make matching uncertain.")
                        .font(.caption).foregroundColor(.secondary)
                }
                if model.history.isEmpty { Text("No completed scans yet.") }
                ForEach(Array(model.history.enumerated()), id: \.element.id) { index, scan in
                    let previous = model.history.dropFirst(index + 1).first { $0.network == scan.network }
                    let changes = scan.changes(since: previous)
                    Section {
                        Text(scan.date, style: .date).font(.headline)
                        Text(scan.date, style: .time)
                        Text("\(scan.devices.count) devices observed")
                        Text("Names: \(scan.identityCoverage.rawValue) · Services: \(scan.serviceCoverage.rawValue)")
                            .font(.caption).foregroundColor(.secondary)
                        if previous == nil { Text("Baseline: first saved scan for this network profile.").font(.caption) }
                        else if changes.isEmpty { Text("No comparable changes detected.").font(.caption) }
                        ForEach(changes) { change in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(verbatim: change.title).font(.subheadline.weight(.semibold))
                                Text(verbatim: change.detail).font(.caption)
                            }
                        }
                    } header: { Text(verbatim: scan.network.components(separatedBy: "|").first ?? "Network profile") }
                }
            }
            .navigationTitle("Scan History")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

private struct NetworkReportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws { text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self) }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: Data(text.utf8)) }
}

struct NetworkReportView: View {
    let devices: [NetworkDevice]
    let history: [ScanSnapshot]
    @Environment(\.dismiss) private var dismiss
    @State private var redacted = true
    @State private var exporting = false
    @State private var exportError: String?
    private let date = Date()
    private var report: String { NetworkReport.text(devices: devices, history: history, redacted: redacted, date: date) }
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Hide identifying details", isOn: $redacted).accessibilityIdentifier("redact-report")
                Text(redacted ? "Names, notes, locations, addresses, hostnames, network identifiers, and raw evidence are omitted." : "This report includes identifying details and personal notes. Review it before sharing.")
                    .font(.caption).foregroundColor(redacted ? .secondary : .orange)
                HStack {
                    ShareLink(item: report) { Label("Share", systemImage: "square.and.arrow.up") }
                    Spacer()
                    Button("Save File") { exporting = true }
                }
                ScrollView {
                    Text(verbatim: report).font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("report-preview")
                }
            }
            .padding()
            .navigationTitle("Network Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .fileExporter(isPresented: $exporting, document: NetworkReportDocument(text: report), contentType: .plainText,
                          defaultFilename: "NetScan-\(date.formatted(.iso8601.year().month().day().dateSeparator(.dash)))") { result in
                if case .failure(let error) = result { exportError = error.localizedDescription }
            }
            .alert("Could not save report", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
                Button("OK") { exportError = nil }
            } message: { Text(exportError ?? "") }
        }
    }
}
