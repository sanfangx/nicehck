import SwiftUI

struct AddDeviceSheetView: View {
    @EnvironmentObject var bluetoothManager: BluetoothManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color(UIColor.systemGroupedBackground)
                    .ignoresSafeArea()

                VStack(spacing: 16) {
                    if bluetoothManager.isScanning {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text(L10n.tr("loading"))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 12)
                    }

                    if bluetoothManager.discoveredDevices.isEmpty {
                        Spacer()
                        VStack(spacing: 14) {
                            Image(systemName: "dot.radiowaves.left.and.right")
                                .font(.system(size: 48))
                                .foregroundColor(.accentColor)
                            Text(L10n.tr("no_devices_found"))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(bluetoothManager.discoveredDevices) { candidate in
                                    Button {
                                        bluetoothManager.stopScanning()
                                        bluetoothManager.connect(candidate)
                                        dismiss()
                                    } label: {
                                        HStack(spacing: 14) {
                                            Image(candidate.device.previewAssetName)
                                                .resizable()
                                                .scaledToFit()
                                                .frame(width: 54, height: 54)

                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(candidate.device.displayName)
                                                    .font(.headline)
                                                    .foregroundColor(.primary)
                                                Text(candidate.device.tag ?? candidate.device.name)
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                            Spacer()
                                            Text(L10n.tr("connect_device"))
                                                .font(.caption.weight(.semibold))
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 6)
                                                .background(Capsule().fill(Color.accentColor))
                                                .foregroundColor(.white)
                                        }
                                        .sectionCardStyle()
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(16)
                        }
                    }
                }
            }
            .navigationTitle(L10n.tr("connect_device"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(L10n.tr("close")) {
                        bluetoothManager.stopScanning()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        bluetoothManager.startScanning()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .onAppear {
                bluetoothManager.startScanning()
            }
            .onDisappear {
                bluetoothManager.stopScanning()
            }
        }
    }
}
