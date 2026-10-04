//
//  WakeOnLANView.swift
//  NetScan
//
//  Dedicated UI for dispatching Wake-on-LAN magic packets.
//

import SwiftUI

public struct WakeOnLANView: View {
    @ObservedObject var viewModel: NetworkToolsViewModel
    
    public init(viewModel: NetworkToolsViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("MAC Address")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                
                HStack {
                    Image(systemName: "cpu")
                        .foregroundColor(.secondary)
                    TextField("e.g. 00:11:22:33:44:55", text: $viewModel.wolMacAddress)
                        .autocapitalization(.allCharacters)
                        .disableAutocorrection(true)
                }
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
            }
            .padding(.horizontal)
            
            Button(action: {
                viewModel.sendWakeOnLAN()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "power")
                    Text("Broadcast Magic Packet")
                        .fontWeight(.bold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(14)
            }
            .padding(.horizontal)
            
            if !viewModel.wolStatusMessage.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: (viewModel.wolSuccess ?? false) ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor((viewModel.wolSuccess ?? false) ? .green : .red)
                    Text(viewModel.wolStatusMessage)
                        .font(.subheadline)
                        .foregroundColor((viewModel.wolSuccess ?? false) ? .green : .red)
                }
                .padding()
                .background(((viewModel.wolSuccess ?? false) ? Color.green : Color.red).opacity(0.12))
                .cornerRadius(12)
                .padding(.horizontal)
            }
            
            Spacer()
        }
        .padding(.top)
    }
}
