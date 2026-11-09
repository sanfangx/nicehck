import SwiftUI
import UIKit

struct DeviceListView: View {
    @EnvironmentObject var bluetoothManager: BluetoothManager
    @State private var showAddDeviceSheet = false
    @State private var showAboutSheet = false
    @State private var devicePendingDeletion: LinkDevice?
    @State private var selectedDeviceId: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color(UIColor.systemGroupedBackground)
                    .ignoresSafeArea()

                if bluetoothManager.isBluetoothPermissionDenied {
                    bluetoothPermissionDeniedView
                } else if bluetoothManager.linkDevices.isEmpty {
                    emptyDeviceListView
                } else {
                    ScrollView {
                        LazyVStack(spacing: 14) {
                            ForEach(bluetoothManager.linkDevices) { linkDevice in
                                NavigationLink(
                                    destination: DeviceDetailView(linkDevice: linkDevice)
                                ) {
                                    DeviceCardRow(
                                        linkDevice: linkDevice,
                                        onToggleConnection: {
                                            if linkDevice.connectionState == .connected {
                                                bluetoothManager.disconnect(linkDevice)
                                            } else if linkDevice.connectionState == .disconnected {
                                                bluetoothManager.connect(linkDevice)
                                            }
                                        },
                                        onDelete: {
                                            devicePendingDeletion = linkDevice
                                        }
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
            }
            .navigationTitle(L10n.tr("device_list"))
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showAboutSheet = true
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 18, weight: .medium))
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showAddDeviceSheet = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20, weight: .semibold))
                    }
                }
            }
            .sheet(isPresented: $showAddDeviceSheet) {
                AddDeviceSheetView()
                    .environmentObject(bluetoothManager)
            }
            .sheet(isPresented: $showAboutSheet) {
                AboutView()
            }
            .alert(
                L10n.tr("delete_device"),
                isPresented: Binding(
                    get: { devicePendingDeletion != nil },
                    set: { if !$0 { devicePendingDeletion = nil } }
                ),
                presenting: devicePendingDeletion
            ) { target in
                Button(L10n.tr("cancel"), role: .cancel) {
                    devicePendingDeletion = nil
                }
                Button(L10n.tr("delete_device"), role: .destructive) {
                    bluetoothManager.removeDevice(target)
                    devicePendingDeletion = nil
                }
            } message: { target in
                Text(L10n.format("delete_device_confirmation", target.device.displayName))
            }
            .onAppear {
                bluetoothManager.checkSystemConnectedGattDevices()
            }
        }
    }

    /// iOS 16.0 replacement for `ContentUnavailableView` when Bluetooth permission is denied
    private var bluetoothPermissionDeniedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 52))
                .foregroundColor(.secondary)

            Text(L10n.tr("bluetooth_permission_required"))
                .font(.headline)

            Text(L10n.tr("bluetooth_permission_description"))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text(L10n.tr("open_settings"))
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.accentColor))
                    .foregroundColor(.white)
            }
        }
        .padding(24)
    }

    /// iOS 16.0 replacement for `ContentUnavailableView` when no devices are saved
    private var emptyDeviceListView: some View {
        VStack(spacing: 18) {
            Image(systemName: "earbuds.case")
                .font(.system(size: 58))
                .foregroundColor(.secondary.opacity(0.75))

            Text(L10n.tr("no_devices_found"))
                .font(.title3.weight(.semibold))
                .foregroundColor(.primary)

            Button {
                showAddDeviceSheet = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                    Text(L10n.tr("connect_device"))
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Capsule().fill(Color.accentColor))
                .foregroundColor(.white)
            }
        }
        .padding(24)
    }
}

struct DeviceCardRow: View {
    @ObservedObject var linkDevice: LinkDevice
    let onToggleConnection: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(linkDevice.device.previewAssetName)
                .resizable()
                .scaledToFit()
                .frame(width: 68, height: 68)
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(UIColor.tertiarySystemGroupedBackground))
                )

            VStack(alignment: .leading, spacing: 6) {
                Text(linkDevice.device.displayName)
                    .font(.headline)
                    .foregroundColor(.primary)

                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    Text(L10n.tr(linkDevice.connectionState.localizedKey))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                if linkDevice.connectionState == .connected,
                   let battery = linkDevice.btDeviceInfo.batteryLevel {
                    HStack(spacing: 10) {
                        Label("\(battery.left)%", systemImage: "l.circle.fill")
                        Label("\(battery.right)%", systemImage: "r.circle.fill")
                        if battery.box > 0 {
                            Label("\(battery.box)%", systemImage: "shippingbox.fill")
                        }
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary)
                }
            }

            Spacer()

            Menu {
                Button {
                    onToggleConnection()
                } label: {
                    Label(
                        linkDevice.connectionState == .connected
                            ? L10n.tr("disconnect")
                            : L10n.tr("connect_device"),
                        systemImage: linkDevice.connectionState == .connected
                            ? "wifi.slash"
                            : "dot.radiowaves.left.and.right"
                    )
                }

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label(L10n.tr("delete_device"), systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 20))
                    .foregroundColor(.secondary)
                    .padding(6)
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
        }
        .sectionCardStyle()
    }

    private var statusColor: Color {
        switch linkDevice.connectionState {
        case .connected: return .green
        case .connecting, .disconnecting: return .orange
        case .disconnected: return .gray
        }
    }
}
