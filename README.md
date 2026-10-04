# NetScan: iOS Local Network Scanner & Packet Traffic Inspector

A native iOS network audit and diagnostic application designed for iPhone and sideloadable via **AltStore**, **Sideloadly**, or **Xcode**.

NetScan scans all active devices connected to the same Wi-Fi network, measures live upload and download throughput in **KB/second** for each device, inspects network packets in real time with protocol decoding and hex dumps, and provides a suite of network diagnostics.

---

## 📱 Features

1. **Subnet Device Discovery & Identification**
   - Discovers all active devices connected to the local Wi-Fi subnet.
   - Identifies friendly device hostnames, mDNS / Bonjour advertised names, and hardware vendors (via embedded IEEE OUI database).
   - Categorizes devices automatically (Smartphones, Computers, Routers, Smart Home/IoT, Printers, Gaming consoles, Smart TVs).
   - Distinguishes the default gateway router and the local iPhone.

2. **Live Device Traffic Monitor (KB/second)**
   - Displays real-time **Upload Speed** (↑ KB/s) and **Download Speed** (↓ KB/s) per device.
   - Tracks network-wide aggregate throughput with visual gauge meters.
   - Calculates total session data transferred (KB, MB, GB).

3. **Packet Inspector & Protocol Analyzer**
   - Real-time packet stream showing inbound (download) and outbound (upload) traffic.
   - Decodes protocol layers: **TCP**, **UDP**, **DNS**, **HTTP**, **HTTPS / TLS**, **ICMP**, **mDNS / Bonjour**, and **ARP**.
   - Displays endpoints (Source IP:Port → Destination IP:Port), packet length, and protocol summaries.
   - Full packet detail inspector with **16-byte aligned Hex Dump** and **printable ASCII representation**.
   - Filter by protocol, search by keyword or IP, and export packets to JSON.

4. **Network Diagnostic Toolbox**
   - **Continuous Ping Monitor**: Measures round-trip time (RTT in ms), jitter, min/avg/max latency, and packet loss.
   - **Multi-Threaded Port Scanner**: Audits open TCP ports (HTTP 80, HTTPS 443, SSH 22, DNS 53, SMB 445, RTSP 554, IPP 631, etc.) with service identification.
   - **Wake-on-LAN (WOL)**: Broadcasts UDP magic packets across the subnet to wake sleeping computers.

5. **AltStore & Sideloading Ready**
   - Pre-configured `Info.plist` with required iOS network privacy keys (`NSLocalNetworkUsageDescription` and `NSBonjourServices`).
   - Sideloadable `.ipa` bundle generator script (`package_ipa.py` / `build_ipa.sh`).
   - AltStore Community Source repository JSON (`AltStore/altstore-source.json`).

---

## 🏗️ Architecture & Project Structure

The project strictly follows Apple Human Interface Guidelines (HIG) and the **MVVM (Model-View-ViewModel)** architectural pattern with Combine reactive data binding:

```
/mnt/d/projects/test/network-scan/
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
│       └── NetScan.entitlements            # NetworkExtension & Wi-Fi entitlements
├── AltStore/
│   ├── altstore-source.json                # AltStore repository source feed
│   └── exportOptions.plist                 # IPA export options
├── Scripts/
│   ├── build_ipa.sh                        # Bash script to package NetScan.ipa
│   └── package_ipa.py                      # Cross-platform Python script to create ready .ipa
├── SimulatorWeb/                           # Interactive Web Preview / Test Bench
└── NetScan.ipa                             # Packaged AltStore-ready iOS IPA archive
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

## 🌐 Instant Testing: Interactive Web Simulator

A complete zero-dependency iOS simulator is included in `SimulatorWeb/`, allowing you to test and interact with the app immediately from your browser:

```bash
# Start the simulator server (runs on port 3840)
node SimulatorWeb/server.js
```

Open `http://localhost:3840` in any web browser to:
- Test the pixel-perfect iPhone 16 Pro interface.
- Scan for connected devices and watch their live upload and download throughput tick in **KB/s**.
- Watch real-time packet streams, filter by protocol (TCP, UDP, DNS, HTTP, HTTPS, ICMP), and view 16-byte hex dumps.
- Run continuous ping latency tests and port scans.

---

## 🛠️ Building with Xcode (macOS)

1. Open `NetScan/NetScan.xcodeproj` in Xcode 15 or 16.
2. Select your connected iPhone or an iOS Simulator target.
3. In the project settings under **Signing & Capabilities**, select your Apple Developer Team.
4. Press `Cmd + R` to build and run directly.
