# NetScan: iOS Local Network Diagnostics

A native iOS network audit and diagnostic application designed for iPhone and sideloadable via **AltStore**, **Sideloadly**, or **Xcode**.

NetScan discovers reachable IPv4 devices on a local network and provides TCP port scans, TCP response-time checks, and Wake-on-LAN. It measures this device's interface traffic in **KB/second**. Other devices' traffic and MAC addresses are unavailable through the current iOS implementation. The packet inspector displays clearly labeled generated examples, not captured traffic.

**Build status:** source changes do not update the checked-in `NetScan.ipa`. Rebuild with Xcode or download a newly built GitHub Actions artifact before testing these fixes. The tracked `build/` directory is also an old artifact. The Python packager requires an existing compiled iPhoneOS `.app`; it cannot compile an iOS app on Windows. The AltStore feed and source URL are templates and must be configured for your own repository before use.

---

## 📱 Features

1. **Subnet Device Discovery & Identification**
   - Probes local subnet addresses on TCP ports 80, 443, and 22 in parallel within one host timeout. Explicit connection refusals also establish reachability; devices that filter all probes may still be missed.
   - Respects the subnet mask. Large networks are limited to a 4096-address window containing this device.
   - Combines hostname and HTTP identity lookup, an embedded IEEE OUI database when a MAC is supplied, and bounded Bonjour service resolution. Advertisements are recorded as self-reported evidence, not as proof that a service is reachable.
   - Categorizes devices automatically (Smartphones, Computers, Routers, Smart Home/IoT, Printers, Gaming consoles, Smart TVs).
   - Automatically resolves unidentified devices after discovery, with one retry after 15 seconds. Hostnames remain visible when iOS hides the MAC address. Rescanning, changing networks, or entering the background cancels pending updates.
   - HTTP identification first requests headers with HEAD, then reads at most 2,048 bytes with GET if needed. Each request has a 1.5-second timeout; an unsuccessful two-stage probe can take up to roughly three seconds.
   - Distinguishes the default gateway router and the local iPhone.

2. **Local Device Traffic Monitor (KB/second)**
   - Reads upload/download counters for this device's active interface.
   - Displays remote device traffic as unavailable.
   - Tracks local session totals and resets rate baselines after network changes or counter resets.

3. **Sample Packet Inspector**
   - Generated demonstration stream showing example inbound/outbound packets.
   - Examples cover **TCP**, **UDP**, **DNS**, **HTTP**, **HTTPS / TLS**, **ICMP**, **mDNS / Bonjour**, and **ARP**.
   - Displays endpoints (Source IP:Port → Destination IP:Port), packet length, and protocol summaries.
   - Full packet detail inspector with **16-byte aligned Hex Dump** and **printable ASCII representation**.
   - Filter by protocol, search by keyword or IP, and view JSON for copying. JSON records include `isSample` to identify generated packets.

4. **Network Diagnostic Toolbox**
   - **Device and Service Risk Checks**: After discovery, checks TCP ports 21, 23, 139, 445, and 3389 with at most two devices checked concurrently. Flags reachable FTP/Telnet and file-sharing/remote-desktop services for review, and shows unresolved identity as information. These observations do not prove malicious activity or unauthorized presence; packet examples are never used as evidence. The detail view distinguishes unchecked, checking, and checked services.
   - **Continuous TCP Probe**: Measures TCP port 80 response time (including explicit refusals), min/avg/max latency, and failed-probe percentage over the last 50 results. This is not ICMP ping.
   - **Multi-Threaded Port Scanner**: Audits open TCP ports (HTTP 80, HTTPS 443, SSH 22, DNS 53, SMB 445, RTSP 554, IPP 631, etc.) with service identification.
   - **Wake-on-LAN (WOL)**: Sends a UDP magic packet on the selected LAN interface. On iOS, broadcast delivery requires Local Network access and a signing profile with Apple's managed Multicast Networking entitlement; ordinary free AltStore signing does not provide it. Sending a packet does not confirm that a device woke up.

5. **Saved Device Labels, History, and Reports**
   - Edit a device to save a name, location, notes, and your recognition of it. Labels remain separate from manufacturer estimates and do not suppress service risks.
   - Stores a versioned inventory file locally in Application Support and the latest 20 completed discovery snapshots. Cancelled discovery does not become a completed scan; cancelled identity/service work leaves explicit incomplete coverage on a completed discovery.
   - Matches supplied MAC addresses first, then unique hostnames, then addresses within a network profile. MAC conflicts create separate records. Hostname/address associations are clearly marked for verification and do not inherit recognition. An unavailable network name also makes the association tentative. iOS privacy limits mean networks with identical visible addressing can be indistinguishable; these associations are not proof of identity.
   - History shows new observations, devices not seen, matching-device address changes, and port changes only where both scans received definite responses. Unanswered probes are inconclusive, not evidence that a service closed.
   - Identification evidence shows source and observation time, distinguishes inferred classifications and self-reported names/headers, and warns that an OUI can identify a module rather than an appliance.
   - Devices → History and reports provides scan history and a dated plain-text report with Share and Save File. Redaction defaults on and structurally omits aliases, notes, locations, IP/MAC addresses, hostnames, network identifiers, and raw evidence. Disabling it includes personal notes: review the preview before sharing.
   - Suggested risk actions are advisory. No default-password attempts, automatic device blocking, router integration, or actual remote-traffic capture are performed.

6. **AltStore & Sideloading Ready**
   - Pre-configured `Info.plist` with required iOS network privacy keys (`NSLocalNetworkUsageDescription` and `NSBonjourServices`).
   - Builds using Xcode (`build_ipa.sh`) and packages a compiled `.app` (`package_ipa.py`).
   - AltStore source template (`AltStore/altstore-source.json`).

---

## 🏗️ Architecture & Project Structure

The project strictly follows Apple Human Interface Guidelines (HIG) and the **MVVM (Model-View-ViewModel)** architectural pattern with Combine reactive data binding:

```
network-scan/
├── NetScan/                                # Native iOS Xcode App Project
│   ├── App/
│   │   ├── NetScanApp.swift                # App entry point (@main)
│   │   └── AppDelegate.swift               # Application lifecycle & background tasks
│   ├── Models/
│   │   ├── NetworkDevice.swift             # Discovered LAN host & live KB/s traffic model
│   │   ├── NetworkPacket.swift             # Inspected packet model & protocol enum
│   │   ├── NetworkInterface.swift          # Wi-Fi IP, subnet mask, gateway, broadcast
│   │   ├── PortScanResult.swift            # Port audit result & KnownPorts database
│   │   ├── TrafficMetric.swift             # Bandwidth metrics & data points
│   │   └── OUIVendorDatabase.swift         # IEEE MAC OUI vendor resolution database
│   ├── Services/
│   │   ├── NetworkInterfaceService.swift   # Reads local IP, subnet, gateway, broadcast
│   │   ├── SubnetScannerService.swift      # Asynchronous LAN subnet scanner
│   │   ├── BonjourDiscoveryService.swift   # NWBrowser mDNS service discovery
│   │   ├── TrafficMonitorService.swift     # Real-time upload/download KB/s throughput tracker
│   │   ├── PacketInspectorService.swift    # Network packet inspector & protocol parser
│   │   ├── PortScannerService.swift        # TCP port scanner for diagnostic audit
│   │   ├── PingDiagnosticService.swift     # ICMP/TCP ping latency measurement
│   │   └── WakeOnLANService.swift          # WOL magic packet utility
│   ├── ViewModels/
│   ├── Views/
│   └── Resources/
│       ├── Info.plist                      # Local Network permissions & Bonjour services
├── AltStore/
│   ├── altstore-source.json                # AltStore repository source feed
│   └── exportOptions.plist                 # IPA export options
├── Scripts/
│   ├── build_ipa.sh                        # Bash script to package NetScan.ipa
│   └── package_ipa.py                      # Cross-platform packager for compiled iPhoneOS .app
└── NetScan.ipa                             # Existing binary; rebuild after source changes
```

---

## 🚀 Installation & Sideloading via AltStore

### Step 1: Install AltServer
1. Download **AltServer** on your Windows PC or Mac from [altstore.io](https://altstore.io).
2. On Windows, ensure iTunes and iCloud (non-Microsoft Store versions) are installed.

### Step 2: Install AltStore on your iPhone
1. Connect your iPhone to your computer via USB.
2. In the system tray or menu bar, click **AltServer** -> **Install AltStore** -> select your iPhone.
3. Enter your Apple ID and password (used by Apple to sign the sideloaded certificate).

### Step 3: Trust the Developer Certificate
1. On your iPhone, open **Settings** -> **General** -> **VPN & Device Management**.
2. Tap your Apple ID profile and select **Trust**.

### Step 4: Install NetScan.ipa
1. Transfer `NetScan.ipa` (found in the root of this project) to your iPhone via iCloud Drive, AirDrop, or local file sharing.
2. Open **AltStore** on your iPhone.
3. Go to the **My Apps** tab and tap the **"+"** icon in the top-left corner.
4. Select `NetScan.ipa`. AltStore will sign and install the app onto your home screen!

---

## 🛠️ Building with Xcode (macOS)

1. Open `NetScan/NetScan.xcodeproj` in Xcode 15 or 16.
2. Select your connected iPhone or an iOS Simulator target.
3. In the project settings under **Signing & Capabilities**, select your Apple Developer Team.
4. Press `Cmd + R` to build and run directly.

To build and package without signing for AltStore, run `bash Scripts/build_ipa.sh` on macOS with Xcode. To package a previously compiled app on any platform:

```sh
python3 Scripts/package_ipa.py /path/to/NetScan.app --output /path/to/NetScan.ipa
```

## Verification

Portable checks: `python3 Scripts/test_project.py`. On macOS, run `swift test`, `swift test -c release`, and `swift test --sanitize=thread --scratch-path .build/tsan` for networking/model regressions. Run `bash Scripts/run_ui_tests.sh` to test the real device-detail navigation and vendor lookup in an installed iOS simulator. The UI fixture is enabled only in Debug builds with the `NETSCAN_UI_TESTING=1` launch environment; CI also checks that it is absent from the Release executable. The GitHub Actions workflow runs these checks before archiving and packaging.

Wake-on-LAN uses the BSD UDP socket API with `SO_BROADCAST` and binds to the selected interface. Apple documents why broadcast requires this API and the managed entitlement in [TN3151](https://developer.apple.com/documentation/technotes/tn3151-choosing-the-right-networking-api) and [TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy). After Apple approves the capability for your App ID, configure `com.apple.developer.networking.multicast` in the app's signing entitlements and provisioning profile. The repository does not enable this managed entitlement by default, so normal builds remain usable for unicast diagnostics with ordinary signing.

Device smoke test after installing a fresh build:

1. Allow Local Network access; scan and open several device details, including an unknown device and this iPhone.
2. Use **Find Online**, return while it runs, and reopen the device. Try unavailable hosts as well as a known HTTP device.
3. Start a port scan and a TCP probe; navigate away and use the tools screen. Check that screens keep independent results and remain responsive.
4. Stop/restart discovery, change Wi-Fi networks, and switch to cellular/background during a scan. Old results must not reappear.
5. Verify `/25` and `/23` networks, local traffic during a download, remote traffic marked unavailable, sample packet labels/JSON, and Wake-on-LAN success/failure feedback.

The Windows development environment cannot compile Apple frameworks or run an iOS simulator. Passing portable checks alone does not confirm an iOS build or device behavior.
