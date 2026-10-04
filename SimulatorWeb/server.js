//
//  server.js
//  NetScan - iOS App Simulator & Local Diagnostic Server
//  Zero-dependency Node.js HTTP server.
//

const http = require('http');
const fs = require('fs');
const path = require('path');
const os = require('os');
const net = require('net');
const dgram = require('dgram');

const PORT = 3840;
const PUBLIC_DIR = path.join(__dirname, 'public');

// --- Network Discovery Helpers ---
function getLocalNetworkInfo() {
    const interfaces = os.networkInterfaces();
    let localIP = '192.168.1.105';
    let netmask = '255.255.255.0';
    let interfaceName = 'en0';

    for (const [name, addrs] of Object.entries(interfaces)) {
        for (const addr of addrs) {
            if (addr.family === 'IPv4' && !addr.internal) {
                localIP = addr.address;
                netmask = addr.netmask;
                interfaceName = name;
                break;
            }
        }
        if (localIP !== '192.168.1.105') break;
    }

    const ipParts = localIP.split('.');
    const gatewayIP = ipParts.length === 4 ? `${ipParts[0]}.${ipParts[1]}.${ipParts[2]}.1` : '192.168.1.1';
    const broadcastIP = ipParts.length === 4 ? `${ipParts[0]}.${ipParts[1]}.${ipParts[2]}.255` : '192.168.1.255';

    return {
        interfaceName,
        ipAddress: localIP,
        subnetMask: netmask,
        cidrPrefix: 24,
        gatewayIP,
        broadcastIP,
        ssid: 'Home_WiFi_5G',
        bssid: '00:11:22:33:44:55',
        isConnected: true,
        interfaceType: 'Wi-Fi (802.11ax)'
    };
}

// Initial discovered device pool
let devices = [
    {
        id: 'dev-1',
        ipAddress: '192.168.1.1',
        macAddress: '00:14:D1:4A:2B:10',
        hostname: 'Gateway.router',
        vendor: 'TP-Link Technologies',
        deviceType: 'Router / Gateway',
        iconName: 'wifi.router',
        isOnline: true,
        uploadSpeedKbps: 114.5,
        downloadSpeedKbps: 420.8,
        totalBytesSent: 35000000,
        totalBytesReceived: 120000000,
        latencyMs: 1.8,
        openPorts: [53, 80, 443],
        services: ['DNS', 'HTTP Admin', 'HTTPS'],
        isGateway: true,
        isLocalDevice: false
    },
    {
        id: 'dev-2',
        ipAddress: '192.168.1.105',
        macAddress: 'F0:18:98:3C:A1:7E',
        hostname: 'iPhone-16-Pro',
        vendor: 'Apple Inc.',
        deviceType: 'Smartphone',
        iconName: 'iphone',
        isOnline: true,
        uploadSpeedKbps: 22.4,
        downloadSpeedKbps: 84.1,
        totalBytesSent: 6400000,
        totalBytesReceived: 21500000,
        latencyMs: 0.9,
        openPorts: [5353],
        services: ['mDNS Bonjour'],
        isGateway: false,
        isLocalDevice: true
    },
    {
        id: 'dev-3',
        ipAddress: '192.168.1.112',
        macAddress: 'AC:BC:32:8E:44:91',
        hostname: 'MacBook-Pro-M3.local',
        vendor: 'Apple Inc.',
        deviceType: 'Computer',
        iconName: 'laptopcomputer',
        isOnline: true,
        uploadSpeedKbps: 58.7,
        downloadSpeedKbps: 245.3,
        totalBytesSent: 28400000,
        totalBytesReceived: 88900000,
        latencyMs: 2.7,
        openPorts: [22, 445, 5000],
        services: ['SSH Remote', 'SMB File Sharing', 'AirPlay Receiver'],
        isGateway: false,
        isLocalDevice: false
    },
    {
        id: 'dev-4',
        ipAddress: '192.168.1.140',
        macAddress: '3C:E1:A1:2F:89:01',
        hostname: 'LivingRoom-Chromecast',
        vendor: 'Google LLC',
        deviceType: 'Smart TV / Streaming',
        iconName: 'tv',
        isOnline: true,
        uploadSpeedKbps: 6.2,
        downloadSpeedKbps: 680.0,
        totalBytesSent: 1800000,
        totalBytesReceived: 210000000,
        latencyMs: 6.4,
        openPorts: [8008, 8009],
        services: ['Google Cast HTTP', 'Google Cast Protobuf'],
        isGateway: false,
        isLocalDevice: false
    },
    {
        id: 'dev-5',
        ipAddress: '192.168.1.185',
        macAddress: '24:0A:C4:11:92:4B',
        hostname: 'ESP32-SmartPlug-LivingRoom',
        vendor: 'Espressif Systems',
        deviceType: 'Smart Home / IoT',
        iconName: 'homekit',
        isOnline: true,
        uploadSpeedKbps: 1.1,
        downloadSpeedKbps: 2.4,
        totalBytesSent: 420000,
        totalBytesReceived: 680000,
        latencyMs: 12.3,
        openPorts: [80],
        services: ['HTTP Web Dashboard'],
        isGateway: false,
        isLocalDevice: false
    },
    {
        id: 'dev-6',
        ipAddress: '192.168.1.200',
        macAddress: '70:5A:0F:D4:21:66',
        hostname: 'HP-ColorLaserJet-M254dw',
        vendor: 'HP (Hewlett-Packard)',
        deviceType: 'Printer',
        iconName: 'printer',
        isOnline: true,
        uploadSpeedKbps: 0.0,
        downloadSpeedKbps: 0.0,
        totalBytesSent: 150000,
        totalBytesReceived: 3400000,
        latencyMs: 14.8,
        openPorts: [80, 443, 631, 9100],
        services: ['HTTP Admin', 'HTTPS', 'IPP Print Service', 'RAW Port 9100'],
        isGateway: false,
        isLocalDevice: false
    },
    {
        id: 'dev-7',
        ipAddress: '192.168.1.220',
        macAddress: 'FC:0F:4B:99:38:12',
        hostname: 'PlayStation-5-Console',
        vendor: 'Sony Interactive Entertainment',
        deviceType: 'Gaming Console',
        iconName: 'gamecontroller',
        isOnline: true,
        uploadSpeedKbps: 18.2,
        downloadSpeedKbps: 340.8,
        totalBytesSent: 12400000,
        totalBytesReceived: 142000000,
        latencyMs: 4.9,
        openPorts: [9295, 9304],
        services: ['Remote Play Service', 'PSN Discovery'],
        isGateway: false,
        isLocalDevice: false
    },
    {
        id: 'dev-8',
        ipAddress: '192.168.1.160',
        macAddress: 'A0:82:1F:5D:82:10',
        hostname: 'Samsung-NeoQLED-4K',
        vendor: 'Samsung Electronics',
        deviceType: 'Smart TV / Streaming',
        iconName: 'tv',
        isOnline: true,
        uploadSpeedKbps: 4.5,
        downloadSpeedKbps: 512.0,
        totalBytesSent: 8200000,
        totalBytesReceived: 450000000,
        latencyMs: 5.2,
        openPorts: [8001, 8002],
        services: ['Samsung SmartView', 'Tizen Remote Protocol'],
        isGateway: false,
        isLocalDevice: false
    },
    {
        id: 'dev-9',
        ipAddress: '192.168.1.135',
        macAddress: 'DC:A6:32:8B:22:E1',
        hostname: 'Raspberry-Pi-4B',
        vendor: 'Raspberry Pi Foundation',
        deviceType: 'Computer / Single-Board Server',
        iconName: 'desktopcomputer',
        isOnline: true,
        uploadSpeedKbps: 8.4,
        downloadSpeedKbps: 34.2,
        totalBytesSent: 5400000,
        totalBytesReceived: 18200000,
        latencyMs: 3.1,
        openPorts: [22, 80],
        services: ['SSH Remote', 'HTTP Web Server / Pi-hole'],
        isGateway: false,
        isLocalDevice: false
    }
];

// Packet Sample Pool
const samplePackets = [
    {
        id: 'p-1',
        timestamp: new Date().toISOString(),
        protocolType: 'DNS',
        direction: 'Upload',
        sourceIP: '192.168.1.105',
        sourcePort: 54102,
        destinationIP: '1.1.1.1',
        destinationPort: 53,
        packetLength: 74,
        summary: 'Standard query 0x7a3c A api.apple.com',
        payloadHex: '7a 3c 01 00 00 01 00 00 00 00 00 00 03 61 70 69 05 61 70 70 6c 65 03 63 6f 6d 00 00 01 00 01',
        payloadAscii: 'z<...........api.apple.com.....'
    },
    {
        id: 'p-2',
        timestamp: new Date().toISOString(),
        protocolType: 'DNS',
        direction: 'Download',
        sourceIP: '1.1.1.1',
        sourcePort: 53,
        destinationIP: '192.168.1.105',
        destinationPort: 54102,
        packetLength: 90,
        summary: 'Standard query response 0x7a3c A 17.253.144.10',
        payloadHex: '7a 3c 81 80 00 01 00 01 00 00 00 00 03 61 70 69 05 61 70 70 6c 65 03 63 6f 6d 00 00 01 00 01 c0 0c 00 01 00 01 00 00 00 3c 00 04 11 fd 90 0a',
        payloadAscii: 'z<...........api.apple.com............<......'
    },
    {
        id: 'p-3',
        timestamp: new Date().toISOString(),
        protocolType: 'HTTPS / TLS',
        direction: 'Upload',
        sourceIP: '192.168.1.105',
        sourcePort: 49832,
        destinationIP: '17.253.144.10',
        destinationPort: 443,
        packetLength: 517,
        summary: 'TLSv1.3 Client Hello (SNI=api.apple.com)',
        payloadHex: '16 03 01 02 00 01 00 01 fc 03 03 f1 a2 8e 45 9b c3 20 89 4f fa 11 02 9c bd 8e 34 1a 80',
        payloadAscii: '..............E.. .O......4..'
    },
    {
        id: 'p-4',
        timestamp: new Date().toISOString(),
        protocolType: 'TCP',
        direction: 'Download',
        sourceIP: '17.253.144.10',
        sourcePort: 443,
        destinationIP: '192.168.1.105',
        destinationPort: 49832,
        packetLength: 66,
        summary: '443 → 49832 [ACK] Seq=1 Ack=518 Win=65535',
        payloadHex: '01 bb c2 a8 00 00 00 01 00 00 02 06 50 10 ff ff 7a 12 00 00',
        payloadAscii: '............P...z...'
    },
    {
        id: 'p-5',
        timestamp: new Date().toISOString(),
        protocolType: 'HTTP',
        direction: 'Upload',
        sourceIP: '192.168.1.105',
        sourcePort: 51234,
        destinationIP: '192.168.1.1',
        destinationPort: 80,
        packetLength: 168,
        summary: 'GET /status.json HTTP/1.1',
        payloadHex: '47 45 54 20 2f 73 74 61 74 75 73 2e 6a 73 6f 6e 20 48 54 54 50 2f 31 2e 31 0d 0a 48 6f 73 74 3a 20 31 39 32 2e 31 36 38 2e 31 2e 31',
        payloadAscii: 'GET /status.json HTTP/1.1..Host: 192.168.1.1'
    },
    {
        id: 'p-6',
        timestamp: new Date().toISOString(),
        protocolType: 'mDNS / Bonjour',
        direction: 'Upload',
        sourceIP: '192.168.1.105',
        sourcePort: 5353,
        destinationIP: '224.0.0.251',
        destinationPort: 5353,
        packetLength: 142,
        summary: 'mDNS query PTR _airplay._tcp.local',
        payloadHex: '00 00 00 00 00 01 00 00 00 00 00 00 08 5f 61 69 72 70 6c 61 79 04 5f 74 63 70 05 6c 6f 63 61 6c',
        payloadAscii: '............._airplay._tcp.local'
    },
    {
        id: 'p-7',
        timestamp: new Date().toISOString(),
        protocolType: 'ICMP',
        direction: 'Upload',
        sourceIP: '192.168.1.105',
        sourcePort: 0,
        destinationIP: '192.168.1.1',
        destinationPort: 0,
        packetLength: 84,
        summary: 'Echo (ping) request id=0x0042 seq=1 ttl=64',
        payloadHex: '08 00 4d 5b 00 42 00 01 64 61 74 61 2d 70 61 64 64 69 6e 67 2d 62 79 74 65 73',
        payloadAscii: '..M[.B..data-padding-bytes'
    }
];

let capturedPackets = [...samplePackets];

// Continuous Traffic Simulation (Updates upload/download KB/s every 1s)
setInterval(() => {
    let totalUp = 0;
    let totalDown = 0;

    devices = devices.map(dev => {
        if (!dev.isOnline) return dev;
        const delta = (Math.random() * 8) - 4;
        let up = Math.max(0, dev.uploadSpeedKbps + delta);
        let down = Math.max(0, dev.downloadSpeedKbps + (delta * 2));

        if (dev.isGateway) {
            up = Math.floor((Math.random() * 180 + 70) * 10) / 10;
            down = Math.floor((Math.random() * 600 + 200) * 10) / 10;
        } else if (Math.random() > 0.85) {
            up = Math.floor((Math.random() * 80 + 10) * 10) / 10;
            down = Math.floor((Math.random() * 350 + 40) * 10) / 10;
        }

        up = Math.round(up * 10) / 10;
        down = Math.round(down * 10) / 10;
        totalUp += up;
        totalDown += down;

        return {
            ...dev,
            uploadSpeedKbps: up,
            downloadSpeedKbps: down,
            totalBytesSent: dev.totalBytesSent + Math.floor(up * 1024),
            totalBytesReceived: dev.totalBytesReceived + Math.floor(down * 1024)
        };
    });

    // Add a live packet periodically
    if (Math.random() > 0.3) {
        const template = samplePackets[Math.floor(Math.random() * samplePackets.length)];
        const newPacket = {
            ...template,
            id: 'p-' + Date.now(),
            timestamp: new Date().toISOString()
        };
        capturedPackets.unshift(newPacket);
        if (capturedPackets.length > 300) capturedPackets.pop();
    }
}, 1000);

// --- HTTP Server ---
const server = http.createServer((req, res) => {
    const url = new URL(req.url, `http://${req.headers.host}`);
    const pathname = url.pathname;

    // CORS headers
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

    if (req.method === 'OPTIONS') {
        res.writeHead(204);
        res.end();
        return;
    }

    // API Routes
    if (pathname === '/api/network-info') {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify(getLocalNetworkInfo()));
        return;
    }

    if (pathname === '/api/devices') {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify(devices));
        return;
    }

    if (pathname === '/api/packets') {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify(capturedPackets));
        return;
    }

    if (pathname === '/api/scan' && req.method === 'POST') {
        // Return simulated scan progress / refresh devices
        setTimeout(() => {
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ status: 'completed', devices }));
        }, 1500);
        return;
    }

    if (pathname === '/api/ping' && req.method === 'POST') {
        let body = '';
        req.on('data', chunk => { body += chunk; });
        req.on('end', () => {
            const data = JSON.parse(body || '{}');
            const host = data.host || '192.168.1.1';
            const startTime = Date.now();

            const socket = new net.Socket();
            socket.setTimeout(800);

            socket.connect(80, host, () => {
                const rtt = Date.now() - startTime;
                socket.destroy();
                res.writeHead(200, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ host, rttMs: rtt, success: true }));
            });

            socket.on('error', () => {
                // Port closed still measures reachability
                const rtt = Date.now() - startTime;
                socket.destroy();
                res.writeHead(200, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ host, rttMs: Math.max(1.2, rtt), success: true }));
            });

            socket.on('timeout', () => {
                socket.destroy();
                res.writeHead(200, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ host, rttMs: 0, success: false }));
            });
        });
        return;
    }

    if (pathname === '/api/portscan' && req.method === 'POST') {
        let body = '';
        req.on('data', chunk => { body += chunk; });
        req.on('end', () => {
            const data = JSON.parse(body || '{}');
            const target = data.target || '192.168.1.1';
            const portsToCheck = [22, 53, 80, 443, 445, 8080];
            const results = [];

            let pending = portsToCheck.length;
            portsToCheck.forEach(port => {
                const s = new net.Socket();
                s.setTimeout(400);
                s.connect(port, target, () => {
                    results.push({ port, service: getPortService(port), isOpen: true });
                    s.destroy();
                    if (--pending === 0) finish();
                });
                s.on('error', () => {
                    s.destroy();
                    if (--pending === 0) finish();
                });
                s.on('timeout', () => {
                    s.destroy();
                    if (--pending === 0) finish();
                });
            });

            function finish() {
                if (results.length === 0) {
                    // Fallback to sample results
                    results.push({ port: 80, service: 'HTTP Web Server', isOpen: true });
                    results.push({ port: 443, service: 'HTTPS Secure Web', isOpen: true });
                }
                res.writeHead(200, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ target, results }));
            }
        });
        return;
    }

    if (pathname === '/api/wol' && req.method === 'POST') {
        let body = '';
        req.on('data', chunk => { body += chunk; });
        req.on('end', () => {
            const data = JSON.parse(body || '{}');
            const mac = (data.mac || '00:11:22:33:44:55').replace(/[:-]/g, '');
            if (mac.length !== 12) {
                res.writeHead(400, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ success: false, message: 'Invalid MAC address' }));
                return;
            }

            try {
                const magic = Buffer.alloc(102);
                magic.fill(0xff, 0, 6);
                const macBuf = Buffer.from(mac, 'hex');
                for (let i = 0; i < 16; i++) {
                    macBuf.copy(magic, 6 + i * 6);
                }

                const client = dgram.createSocket('udp4');
                client.send(magic, 0, magic.length, 9, '255.255.255.255', (err) => {
                    client.close();
                    if (err) {
                        res.writeHead(500, { 'Content-Type': 'application/json' });
                        res.end(JSON.stringify({ success: false, message: err.message }));
                    } else {
                        res.writeHead(200, { 'Content-Type': 'application/json' });
                        res.end(JSON.stringify({ success: true, message: `Magic packet sent to ${data.mac}` }));
                    }
                });
            } catch (err) {
                res.writeHead(500, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ success: false, message: err.message }));
            }
        });
        return;
    }

    // Static file handler
    let filePath = path.join(PUBLIC_DIR, pathname === '/' ? 'index.html' : pathname);
    fs.stat(filePath, (err, stats) => {
        if (err || !stats.isFile()) {
            filePath = path.join(PUBLIC_DIR, 'index.html');
        }

        const ext = path.extname(filePath).toLowerCase();
        const contentTypes = {
            '.html': 'text/html; charset=utf-8',
            '.js': 'application/javascript; charset=utf-8',
            '.css': 'text/css; charset=utf-8',
            '.json': 'application/json; charset=utf-8',
            '.png': 'image/png',
            '.svg': 'image/svg+xml'
        };

        const contentType = contentTypes[ext] || 'text/plain';
        fs.readFile(filePath, (readErr, content) => {
            if (readErr) {
                res.writeHead(404);
                res.end('File not found');
            } else {
                res.writeHead(200, { 'Content-Type': contentType });
                res.end(content);
            }
        });
    });
});

function getPortService(port) {
    const map = {
        21: 'FTP',
        22: 'SSH Remote Login',
        23: 'Telnet',
        53: 'DNS Service',
        80: 'HTTP Web Admin',
        443: 'HTTPS Secure Web',
        445: 'SMB Windows Sharing',
        631: 'IPP Printing',
        8080: 'HTTP Alt Web',
        9100: 'RAW JetDirect'
    };
    return map[port] || `TCP Port ${port}`;
}

server.listen(PORT, () => {
    console.log(`====================================================`);
    console.log(` NetScan iOS Simulator & Diagnostic Server Running `);
    console.log(` URL: http://localhost:${PORT}`);
    console.log(`====================================================`);
});
