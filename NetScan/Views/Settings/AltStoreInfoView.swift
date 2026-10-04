//
//  AltStoreInfoView.swift
//  NetScan
//
//  Instructions and configuration for sideloading NetScan via AltStore.
//

import SwiftUI

public struct AltStoreInfoView: View {
    public init() {}
    
    public var body: some View {
        List {
            Section(header: Text("AltStore Installation Guide")) {
                stepRow(number: "1", title: "Install AltServer", desc: "Download and install AltServer on your Windows PC or Mac from altstore.io.")
                stepRow(number: "2", title: "Install AltStore on iPhone", desc: "Connect your iPhone via USB, open AltServer, and select 'Install AltStore' -> your iPhone.")
                stepRow(number: "3", title: "Trust Developer Certificate", desc: "On iPhone: Settings -> General -> VPN & Device Management -> Trust your Apple ID.")
                stepRow(number: "4", title: "Sideload NetScan.ipa", desc: "Transfer NetScan.ipa via AirDrop, iCloud Drive, or AltServer and tap '+' in AltStore to install.")
            }
            
            Section(header: Text("Required iOS Permissions")) {
                HStack {
                    Image(systemName: "network")
                        .foregroundColor(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Local Network Privacy")
                            .font(.headline)
                        Text("Required by iOS 14+ to discover devices on your local Wi-Fi.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
                
                HStack {
                    Image(systemName: "wifi")
                        .foregroundColor(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Wi-Fi SSID Info Access")
                            .font(.headline)
                        Text("Allows reading Wi-Fi network SSID and gateway details.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            
            Section(header: Text("AltStore Source Repository")) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("You can also add this project as a direct AltStore Source feed by pasting the source URL in AltStore -> Sources -> '+'.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("https://raw.githubusercontent.com/netscan/altstore/main/apps.json")
                        .font(.system(size: 11, design: .monospaced))
                        .padding(8)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(8)
                }
                .padding(.vertical, 4)
            }
        }
        .listStyle(InsetGroupedListStyle())
        .navigationTitle("AltStore Sideloading")
    }
    
    private func stepRow(number: String, title: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 24, height: 24)
                Text(number)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(desc)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
