//
//  app.js
//  Client logic for NetScan iOS Simulator
//

let currentDevices = [];
let currentPackets = [];
let isCapturing = true;
let activeProtoFilter = 'all';
let activeCategoryFilter = 'all';
let isScanning = false;
let pingInterval = null;
let pingSeq = 0;
let pingHistory = [];

document.addEventListener('DOMContentLoaded', () => {
  initClock();
  initNavigation();
  initTools();
  initModals();
  fetchNetworkInfo();
  startDataPolling();
});

// Update status bar time
function initClock() {
  const timeEl = document.getElementById('statusTime');
  function updateTime() {
    const d = new Date();
    const h = String(d.getHours()).padStart(2, '0');
    const m = String(d.getMinutes()).padStart(2, '0');
    timeEl.textContent = `${h}:${m}`;
  }
  updateTime();
  setInterval(updateTime, 10000);
}

// Bottom Tab Navigation
function initNavigation() {
  const tabs = document.querySelectorAll('.tab-btn');
  tabs.forEach(btn => {
    btn.addEventListener('click', () => {
      tabs.forEach(t => t.classList.remove('active'));
      document.querySelectorAll('.tab-content').forEach(c => c.classList.remove('active'));

      btn.classList.add('active');
      const targetId = btn.getAttribute('data-tab');
      const targetContent = document.getElementById(targetId);
      if (targetContent) targetContent.classList.add('active');
    });
  });

  // Category filter chips
  document.querySelectorAll('.chips-scroll .chip[data-filter]').forEach(chip => {
    chip.addEventListener('click', (e) => {
      document.querySelectorAll('.chips-scroll .chip[data-filter]').forEach(c => c.classList.remove('active'));
      chip.classList.add('active');
      activeCategoryFilter = chip.getAttribute('data-filter');
      renderDevices();
    });
  });

  // Protocol filter chips
  document.querySelectorAll('.chips-scroll .chip[data-proto]').forEach(chip => {
    chip.addEventListener('click', (e) => {
      document.querySelectorAll('.chips-scroll .chip[data-proto]').forEach(c => c.classList.remove('active'));
      chip.classList.add('active');
      activeProtoFilter = chip.getAttribute('data-proto');
      renderPackets();
    });
  });

  // Search listeners
  document.getElementById('deviceSearchInput')?.addEventListener('input', renderDevices);
  document.getElementById('packetSearchInput')?.addEventListener('input', renderPackets);

  // Scan buttons
  document.getElementById('btnScanSubnet')?.addEventListener('click', triggerSubnetScan);
  document.getElementById('btnDashScan')?.addEventListener('click', () => {
    // Switch to devices tab and start scan
    document.querySelector('.tab-btn[data-tab="tab-devices"]').click();
    triggerSubnetScan();
  });

  // Capture controls
  document.getElementById('btnToggleCapture')?.addEventListener('click', () => {
    isCapturing = !isCapturing;
    const dot = document.getElementById('captureDot');
    const text = document.getElementById('captureStatusText');
    const icon = document.querySelector('#btnToggleCapture i');
    if (isCapturing) {
      dot.className = 'pulse-dot green';
      text.textContent = 'LIVE CAPTURE ACTIVE';
      icon.className = 'fa-solid fa-pause';
    } else {
      dot.className = 'pulse-dot orange';
      text.textContent = 'CAPTURE PAUSED';
      icon.className = 'fa-solid fa-play';
    }
  });

  document.getElementById('btnClearPackets')?.addEventListener('click', () => {
    currentPackets = [];
    renderPackets();
  });
}

// Fetch network interface configuration
async function fetchNetworkInfo() {
  try {
    const res = await fetch('/api/network-info');
    const info = await res.json();
    document.getElementById('dashSSID').textContent = info.ssid;
    document.getElementById('dashType').textContent = info.interfaceType;
    document.getElementById('dashIP').textContent = info.ipAddress;
    document.getElementById('dashMask').textContent = info.subnetMask;
    document.getElementById('dashGateway').textContent = info.gatewayIP;
    document.getElementById('dashBroadcast').textContent = info.broadcastIP;
  } catch (e) {
    console.error('Failed to load network info', e);
  }
}

// Polling for live throughput and devices
function startDataPolling() {
  async function poll() {
    try {
      // 1. Fetch devices & calculate throughput
      const devRes = await fetch('/api/devices');
      currentDevices = await devRes.json();

      let totalUp = 0;
      let totalDown = 0;
      currentDevices.forEach(d => {
        totalUp += d.uploadSpeedKbps;
        totalDown += d.downloadSpeedKbps;
      });

      // Update dashboard gauges
      document.getElementById('dashDownloadSpeed').textContent = totalDown.toFixed(1);
      document.getElementById('dashUploadSpeed').textContent = totalUp.toFixed(1);
      document.getElementById('dashDownloadBar').style.width = Math.min(100, (totalDown / 2000) * 100) + '%';
      document.getElementById('dashUploadBar').style.width = Math.min(100, (totalUp / 1000) * 100) + '%';
      document.getElementById('dashDeviceCount').textContent = `${currentDevices.length} devices active on subnet`;

      renderDashboardPreview();
      renderDevices();

      // 2. Fetch packets if capturing
      if (isCapturing) {
        const pktRes = await fetch('/api/packets');
        currentPackets = await pktRes.json();
        renderPackets();
      }
    } catch (e) {
      console.error('Polling error', e);
    }
  }

  poll();
  setInterval(poll, 1000);
}

// Render Dashboard Preview
function renderDashboardPreview() {
  const container = document.getElementById('dashDeviceListPreview');
  if (!container) return;

  const top3 = currentDevices.slice(0, 3);
  container.innerHTML = top3.map(dev => `
    <div class="device-row" onclick="document.querySelector('.tab-btn[data-tab=\'tab-devices\']').click()" style="padding: 8px 0; border-bottom: 1px solid var(--border-color); cursor: pointer;">
      <div class="device-avatar ${getAvatarColor(dev)}" style="width: 34px; height: 34px; font-size: 15px;">
        <i class="fa-solid ${getDeviceIcon(dev.deviceType)}"></i>
      </div>
      <div class="device-info">
        <div class="device-name" style="font-size: 13px; font-weight: 700;">${dev.hostname || dev.ipAddress}</div>
        <div class="device-sub" style="font-size: 11px;">IP: ${dev.ipAddress} • ${dev.vendor}</div>
      </div>
      <div class="device-traffic-col">
        <div class="traffic-down" style="font-size: 11px;">↓ ${dev.downloadSpeedKbps.toFixed(1)} KB/s</div>
        <div class="traffic-up" style="font-size: 10px;">↑ ${dev.uploadSpeedKbps.toFixed(1)} KB/s</div>
      </div>
    </div>
  `).join('');
}

// Render Devices Tab
function renderDevices() {
  const container = document.getElementById('devicesContainer');
  if (!container) return;

  const search = (document.getElementById('deviceSearchInput')?.value || '').toLowerCase();
  
  const filtered = currentDevices.filter(d => {
    // Category match
    if (activeCategoryFilter !== 'all') {
      const type = d.deviceType.toLowerCase();
      if (activeCategoryFilter === 'phone' && !type.includes('smart') && !type.includes('phone')) return false;
      if (activeCategoryFilter === 'computer' && !type.includes('comp')) return false;
      if (activeCategoryFilter === 'router' && !type.includes('rout') && !type.includes('gate')) return false;
      if (activeCategoryFilter === 'smartHome' && !type.includes('home') && !type.includes('iot')) return false;
      if (activeCategoryFilter === 'printer' && !type.includes('print')) return false;
      if (activeCategoryFilter === 'gaming' && !type.includes('game') && !type.includes('play')) return false;
    }
    // Search match
    if (search) {
      const matchName = (d.hostname || '').toLowerCase().includes(search);
      const matchIP = d.ipAddress.includes(search);
      const matchVendor = (d.vendor || '').toLowerCase().includes(search);
      if (!matchName && !matchIP && !matchVendor) return false;
    }
    return true;
  });

  document.getElementById('devicesListHeader').textContent = `${filtered.length} DEVICES ON 192.168.1.0/24`;

  container.innerHTML = filtered.map(dev => `
    <div class="device-row" onclick="openDeviceDetail('${dev.id}')" style="align-items: flex-start; padding: 12px 14px;">
      <div class="device-avatar ${getAvatarColor(dev)}" style="margin-top: 2px;">
        <i class="fa-solid ${getDeviceIcon(dev.deviceType)}"></i>
      </div>
      <div class="device-info" style="display: flex; flex-direction: column; gap: 4px; width: 100%;">
        <!-- ROW 1: Full Device Name & Badges -->
        <div class="device-name-row" style="flex-wrap: wrap; gap: 6px;">
          <span class="device-name" style="white-space: normal; word-break: break-word; font-size: 15px; font-weight: 700; line-height: 1.3;">${dev.hostname || dev.ipAddress}</span>
          ${dev.isGateway ? '<span class="tag-badge orange">GATEWAY</span>' : ''}
          ${dev.isLocalDevice ? '<span class="tag-badge blue">THIS IPHONE</span>' : ''}
        </div>
        ${dev.vendor && !((dev.hostname || '').toLowerCase().includes(dev.vendor.toLowerCase())) ? `<div style="font-size: 11px; color: var(--text-secondary);">${dev.vendor}</div>` : ''}

        <!-- ROW 2: Network Address on the next row -->
        <div class="device-address-row" style="display: flex; align-items: center; gap: 8px; font-size: 12px; margin-top: 2px;">
          <span><b style="color: var(--text-secondary); font-size: 10px;">IP:</b> <span style="font-family: monospace; font-weight: 600; color: #fff;">${dev.ipAddress}</span></span>
          <span style="color: var(--text-secondary);">•</span>
          <span><b style="color: var(--text-secondary); font-size: 10px;">MAC:</b> <span style="font-family: monospace; color: var(--text-secondary); font-size: 11px;">${dev.macAddress}</span></span>
        </div>

        <!-- ROW 3: Network Traffic on the next next row -->
        <div class="device-traffic-row" style="display: flex; align-items: center; gap: 10px; margin-top: 4px;">
          <span style="background: rgba(48, 209, 88, 0.15); color: var(--accent-green); padding: 3px 8px; border-radius: 6px; font-size: 12px; font-weight: 700; font-family: monospace;">
            <i class="fa-solid fa-arrow-down" style="font-size: 9px;"></i> ${dev.downloadSpeedKbps.toFixed(1)} KB/s
          </span>
          <span style="background: rgba(10, 132, 255, 0.15); color: var(--accent-blue); padding: 3px 8px; border-radius: 6px; font-size: 12px; font-weight: 700; font-family: monospace;">
            <i class="fa-solid fa-arrow-up" style="font-size: 9px;"></i> ${dev.uploadSpeedKbps.toFixed(1)} KB/s
          </span>
          <span style="font-size: 11px; color: var(--text-secondary); margin-left: auto; font-family: monospace;">
            <span style="color: var(--accent-green);">●</span> ${dev.latencyMs.toFixed(1)} ms
          </span>
        </div>
      </div>
    </div>
  `).join('');
}

// Render Packets Tab
function renderPackets() {
  const container = document.getElementById('packetsContainer');
  if (!container) return;

  const search = (document.getElementById('packetSearchInput')?.value || '').toLowerCase();
  
  const filtered = currentPackets.filter(p => {
    if (activeProtoFilter !== 'all' && p.protocolType !== activeProtoFilter) return false;
    if (search) {
      const matchSum = (p.summary || '').toLowerCase().includes(search);
      const matchEnd = (p.sourceIP + ' ' + p.destinationIP).includes(search);
      const matchHex = (p.payloadHex || '').toLowerCase().includes(search);
      if (!matchSum && !matchEnd && !matchHex) return false;
    }
    return true;
  });

  document.getElementById('packetCountBadge').textContent = `${filtered.length} packets`;

  container.innerHTML = filtered.map(p => `
    <div class="packet-item" onclick="openPacketDetail('${p.id}')">
      <div class="packet-top-row">
        <i class="fa-solid ${p.direction === 'Download' ? 'fa-arrow-down' : 'fa-arrow-up'}" 
           style="color: ${p.direction === 'Download' ? 'var(--accent-green)' : 'var(--accent-blue)'}; font-size: 11px;"></i>
        <span class="proto-badge ${getProtoClass(p.protocolType)}">${p.protocolType}</span>
        <span class="packet-endpoints">${p.sourceIP}:${p.sourcePort || ''} → ${p.destinationIP}:${p.destinationPort || ''}</span>
        <span class="packet-len">${p.packetLength} B</span>
      </div>
      <div class="packet-summary">${p.summary}</div>
    </div>
  `).join('');
}

// Trigger subnet scan animation
async function triggerSubnetScan() {
  if (isScanning) return;
  isScanning = true;

  const progressWrap = document.getElementById('scanProgressContainer');
  const progressFill = document.getElementById('scanProgressFill');
  const percentText = document.getElementById('scanPercentText');

  progressWrap.style.display = 'block';
  progressFill.style.width = '0%';
  percentText.textContent = '0%';

  let pct = 0;
  const interval = setInterval(() => {
    pct += 5;
    progressFill.style.width = pct + '%';
    percentText.textContent = pct + '%';
    if (pct >= 100) {
      clearInterval(interval);
      setTimeout(() => {
        progressWrap.style.display = 'none';
        isScanning = false;
      }, 500);
    }
  }, 75);

  try {
    await fetch('/api/scan', { method: 'POST' });
  } catch (e) {
    console.error(e);
  }
}

// Helper icons & classes
function getDeviceIcon(type) {
  const t = (type || '').toLowerCase();
  if (t.includes('rout') || t.includes('gate')) return 'fa-wifi';
  if (t.includes('smart') || t.includes('phone')) return 'fa-mobile-screen-button';
  if (t.includes('comp') || t.includes('laptop')) return 'fa-laptop';
  if (t.includes('tv')) return 'fa-tv';
  if (t.includes('print')) return 'fa-print';
  if (t.includes('game')) return 'fa-gamepad';
  if (t.includes('home') || t.includes('iot')) return 'fa-plug';
  return 'fa-network-wired';
}

function getAvatarColor(dev) {
  if (dev.isGateway) return 'orange';
  if (dev.isLocalDevice) return '';
  const t = (dev.deviceType || '').toLowerCase();
  if (t.includes('print')) return 'green';
  if (t.includes('comp')) return 'purple';
  return '';
}

function getProtoClass(proto) {
  const p = (proto || '').toLowerCase();
  if (p.includes('tcp')) return 'tcp';
  if (p.includes('udp')) return 'udp';
  if (p.includes('dns')) return 'dns';
  if (p.includes('https') || p.includes('tls')) return 'https';
  if (p.includes('http')) return 'http';
  if (p.includes('icmp')) return 'icmp';
  return 'tcp';
}

// --- Tools Implementation ---
function initTools() {
  // Segmented control
  document.querySelectorAll('.seg-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      document.querySelectorAll('.seg-btn').forEach(b => b.classList.remove('active'));
      document.querySelectorAll('.tool-panel').forEach(p => p.classList.remove('active'));

      btn.classList.add('active');
      const toolId = 'tool-' + btn.getAttribute('data-tool');
      document.getElementById(toolId)?.classList.add('active');
    });
  });

  // Ping Tool
  const btnPing = document.getElementById('btnStartPing');
  btnPing.addEventListener('click', () => {
    if (pingInterval) {
      clearInterval(pingInterval);
      pingInterval = null;
      btnPing.textContent = 'Ping';
      btnPing.className = 'pill-btn primary';
    } else {
      btnPing.textContent = 'Stop';
      btnPing.className = 'pill-btn' ;
      btnPing.style.background = '#ff453a';
      pingSeq = 0;
      pingHistory = [];
      document.getElementById('pingLogContainer').innerHTML = '';
      sendPing();
      pingInterval = setInterval(sendPing, 1000);
    }
  });

  async function sendPing() {
    pingSeq++;
    const host = document.getElementById('pingHostInput').value.trim() || '192.168.1.1';
    try {
      const res = await fetch('/api/ping', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ host })
      });
      const data = await res.json();
      pingHistory.push(data.rttMs);

      // Update stats
      const valid = pingHistory.filter(r => r > 0);
      const min = Math.min(...valid);
      const max = Math.max(...valid);
      const avg = valid.reduce((a, b) => a + b, 0) / valid.length;

      document.getElementById('pingAvg').textContent = avg.toFixed(1) + ' ms';
      document.getElementById('pingMin').textContent = min.toFixed(1) + ' ms';
      document.getElementById('pingMax').textContent = max.toFixed(1) + ' ms';

      const log = document.getElementById('pingLogContainer');
      const row = document.createElement('div');
      row.className = 'ping-log-row';
      row.innerHTML = `
        <span style="color: var(--text-secondary);">Seq ${pingSeq} to ${host}</span>
        <span style="color: var(--accent-green); font-weight: 600;">${data.rttMs.toFixed(1)} ms</span>
      `;
      log.prepend(row);
    } catch (e) {
      console.error(e);
    }
  }

  // Port Scanner Tool
  const btnPort = document.getElementById('btnStartPortScan');
  btnPort.addEventListener('click', async () => {
    btnPort.textContent = 'Scanning...';
    btnPort.disabled = true;
    const target = document.getElementById('portTargetInput').value.trim() || '192.168.1.1';

    try {
      const res = await fetch('/api/portscan', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ target })
      });
      const data = await res.json();
      const container = document.getElementById('portScanResults');
      container.innerHTML = data.results.map(r => `
        <div style="display: flex; align-items: center; justify-content: space-between; padding: 10px 0; border-bottom: 1px solid var(--border-color);">
          <div style="display: flex; gap: 10px; align-items: center;">
            <span style="background: rgba(10,132,255,0.2); color: var(--accent-blue); padding: 2px 8px; border-radius: 6px; font-weight: 700; font-family: monospace;">${r.port}</span>
            <div>
              <div style="font-weight: 600; font-size: 13px;">${r.service}</div>
              <div style="font-size: 11px; color: var(--accent-green);">TCP • Open</div>
            </div>
          </div>
          <i class="fa-solid fa-lock-open" style="color: var(--accent-green);"></i>
        </div>
      `).join('');
    } catch (e) {
      console.error(e);
    } finally {
      btnPort.textContent = 'Scan';
      btnPort.disabled = false;
    }
  });

  // Wake on LAN
  const btnWol = document.getElementById('btnSendWOL');
  btnWol.addEventListener('click', async () => {
    const mac = document.getElementById('wolMacInput').value.trim();
    const fb = document.getElementById('wolFeedback');
    fb.style.display = 'block';
    fb.textContent = 'Broadcasting magic packet...';
    fb.style.background = 'rgba(10, 132, 255, 0.15)';
    fb.style.color = 'var(--accent-blue)';

    try {
      const res = await fetch('/api/wol', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ mac })
      });
      const data = await res.json();
      if (data.success) {
        fb.textContent = '✓ ' + data.message;
        fb.style.background = 'rgba(48, 209, 88, 0.15)';
        fb.style.color = 'var(--accent-green)';
      } else {
        fb.textContent = '✗ ' + data.message;
        fb.style.background = 'rgba(255, 69, 58, 0.15)';
        fb.style.color = 'var(--accent-red)';
      }
    } catch (e) {
      fb.textContent = '✗ Failed to send magic packet';
      fb.style.color = 'var(--accent-red)';
    }
  });
}

// Modals
function initModals() {
  document.getElementById('btnCloseDeviceModal').addEventListener('click', () => {
    document.getElementById('deviceModal').style.display = 'none';
  });
  document.getElementById('btnClosePacketModal').addEventListener('click', () => {
    document.getElementById('packetModal').style.display = 'none';
  });
}

window.openDeviceDetail = function(id) {
  const dev = currentDevices.find(d => d.id === id);
  if (!dev) return;

  document.getElementById('modDeviceName').textContent = dev.hostname || dev.ipAddress;
  const content = document.getElementById('deviceModalContent');
  content.innerHTML = `
    <div style="text-align: center; margin-bottom: 16px;">
      <div class="device-avatar ${getAvatarColor(dev)}" style="width: 56px; height: 56px; margin: 0 auto 8px auto; font-size: 24px;">
        <i class="fa-solid ${getDeviceIcon(dev.deviceType)}"></i>
      </div>
      <div style="font-size: 17px; font-weight: 700;">${dev.hostname || dev.ipAddress}</div>
      <div style="font-size: 13px; color: var(--text-secondary);">${dev.vendor}</div>
      <span class="badge green" style="margin-top: 6px; display: inline-block;">Online</span>
    </div>

    <div class="ios-card" style="margin-bottom: 12px;">
      <div style="font-size: 11px; font-weight: 700; color: var(--text-secondary); margin-bottom: 8px;">LIVE TRAFFIC THROUGHPUT</div>
      <div style="display: flex; justify-content: space-between;">
        <div>
          <div style="font-size: 11px; color: var(--text-secondary);">DOWNLOAD</div>
          <div style="font-size: 18px; font-weight: 700; color: var(--accent-green); font-family: monospace;">↓ ${dev.downloadSpeedKbps.toFixed(1)} KB/s</div>
        </div>
        <div style="text-align: right;">
          <div style="font-size: 11px; color: var(--text-secondary);">UPLOAD</div>
          <div style="font-size: 18px; font-weight: 700; color: var(--accent-blue); font-family: monospace;">↑ ${dev.uploadSpeedKbps.toFixed(1)} KB/s</div>
        </div>
      </div>
    </div>

    <div class="ios-card">
      <div style="font-size: 11px; font-weight: 700; color: var(--text-secondary); margin-bottom: 8px;">NETWORK IDENTITY</div>
      <div class="settings-row" style="background: none; padding: 6px 0;">
        <span>IP Address</span>
        <span class="mono-sub">${dev.ipAddress}</span>
      </div>
      <div class="settings-row" style="background: none; padding: 6px 0;">
        <span>MAC Address</span>
        <span class="mono-sub">${dev.macAddress}</span>
      </div>
      <div class="settings-row" style="background: none; padding: 6px 0;">
        <span>Category</span>
        <span>${dev.deviceType}</span>
      </div>
      <div class="settings-row" style="background: none; padding: 6px 0;">
        <span>Round-Trip Latency</span>
        <span>${dev.latencyMs.toFixed(1)} ms</span>
      </div>
    </div>

    <div class="ios-card">
      <div style="font-size: 11px; font-weight: 700; color: var(--text-secondary); margin-bottom: 8px;">DETECTED SERVICES</div>
      <div>${(dev.services || []).map(s => `<span class="badge" style="background: rgba(255,255,255,0.1); margin: 2px;">${s}</span>`).join('') || '<span style="color: var(--text-secondary);">None</span>'}</div>
    </div>
  `;
  document.getElementById('deviceModal').style.display = 'flex';
};

window.openPacketDetail = function(id) {
  const p = currentPackets.find(item => item.id === id);
  if (!p) return;

  document.getElementById('modPacketProto').textContent = `${p.protocolType} Packet Detail`;
  const content = document.getElementById('packetModalContent');
  
  // Format hex dump with line offsets
  const hexTokens = (p.payloadHex || '').split(' ');
  let formattedHex = '';
  for (let i = 0; i < hexTokens.length; i += 16) {
    const chunk = hexTokens.slice(i, i + 16);
    const offset = i.toString(16).padStart(4, '0').toUpperCase();
    formattedHex += `${offset}   ${chunk.join(' ')}\n`;
  }

  content.innerHTML = `
    <div class="ios-card" style="margin-bottom: 12px;">
      <div style="font-size: 11px; font-weight: 700; color: var(--text-secondary); margin-bottom: 8px;">LAYER OVERVIEW</div>
      <div class="settings-row" style="background: none; padding: 4px 0;">
        <span>Protocol</span>
        <span class="proto-badge ${getProtoClass(p.protocolType)}">${p.protocolType}</span>
      </div>
      <div class="settings-row" style="background: none; padding: 4px 0;">
        <span>Direction</span>
        <span>${p.direction}</span>
      </div>
      <div class="settings-row" style="background: none; padding: 4px 0;">
        <span>Source</span>
        <span class="mono-sub">${p.sourceIP}:${p.sourcePort || '0'}</span>
      </div>
      <div class="settings-row" style="background: none; padding: 4px 0;">
        <span>Destination</span>
        <span class="mono-sub">${p.destinationIP}:${p.destinationPort || '0'}</span>
      </div>
      <div class="settings-row" style="background: none; padding: 4px 0;">
        <span>Length</span>
        <span>${p.packetLength} Bytes</span>
      </div>
      <div class="settings-row" style="background: none; padding: 4px 0;">
        <span>Summary</span>
        <span style="font-size: 12px; color: var(--text-secondary);">${p.summary}</span>
      </div>
    </div>

    <div class="ios-card">
      <div style="font-size: 11px; font-weight: 700; color: var(--text-secondary);">16-BYTE ALIGNED HEX DUMP</div>
      <div class="hex-dump-box">${formattedHex || 'No raw payload'}</div>

      <div style="font-size: 11px; font-weight: 700; color: var(--text-secondary); margin-top: 12px;">PRINTABLE ASCII</div>
      <div class="hex-dump-box" style="color: #64d2ff;">${p.payloadAscii || 'None'}</div>
    </div>
  `;
  document.getElementById('packetModal').style.display = 'flex';
};
