import SwiftUI

struct DeviceDetailView: View {
    @EnvironmentObject var bluetoothManager: BluetoothManager
    @ObservedObject var linkDevice: LinkDevice
    @StateObject private var firmwareRepo = FirmwareRepository()
    @State private var showImportantUpdateAlert = false
    @State private var navigateToFirmwareUpdate = false
    @State private var hasCheckedFirmware = false

    private var firmwareVersionInt: Int {
        linkDevice.btDeviceInfo.firmwareVersionInt
    }

    private var featureGroups: [FeatureGroup] {
        DeviceManager.shared.featureGroups(
            for: linkDevice.device.id,
            firmwareVersion: firmwareVersionInt
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                headerProductSection
                connectionAndBatterySection

                if linkDevice.connectionState == .connected {
                    ForEach(featureGroups) { group in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(L10n.tr(group.option.name))
                                .font(.footnote.weight(.semibold))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 4)

                            VStack(spacing: 12) {
                                ForEach(group.features) { feature in
                                    featureView(for: feature)
                                }
                            }
                        }
                    }
                } else {
                    disconnectedNoticeCard
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(linkDevice.device.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $navigateToFirmwareUpdate) {
            FirmwareUpdateView(linkDevice: linkDevice, firmwareRepo: firmwareRepo)
        }
        .alert(
            L10n.tr("important_update"),
            isPresented: $showImportantUpdateAlert
        ) {
            Button(L10n.tr("remind_later"), role: .cancel) {}
            Button(L10n.tr("go_to_update")) {
                navigateToFirmwareUpdate = true
            }
        } message: {
            Text(L10n.tr("important_firmware_update_found"))
        }
        .onAppear {
            if linkDevice.connectionState == .connected {
                checkFirmwareIfNeeded()
            } else {
                bluetoothManager.connect(linkDevice)
            }
        }
        .onChange(of: linkDevice.btDeviceInfo.firmwareVersion) { _ in
            checkFirmwareIfNeeded()
        }
    }

    private func checkFirmwareIfNeeded() {
        guard !hasCheckedFirmware, firmwareVersionInt > 0 else { return }
        hasCheckedFirmware = true
        Task {
            await firmwareRepo.checkFirmwareUpdate(
                deviceId: linkDevice.device.id,
                currentVersion: firmwareVersionInt
            )
            if case .shouldUpdate = firmwareRepo.updateState {
                showImportantUpdateAlert = true
            }
        }
    }

    private var headerProductSection: some View {
        VStack(spacing: 8) {
            Image(linkDevice.device.detailAssetName)
                .resizable()
                .scaledToFit()
                .frame(height: 180)
                .padding(.vertical, 6)

            if let fw = linkDevice.btDeviceInfo.firmwareVersion {
                Text("\(L10n.tr("current_version")): \(fw)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .sectionCardStyle()
    }

    private var connectionAndBatterySection: some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.tr("status"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack(spacing: 6) {
                        Circle()
                            .fill(linkDevice.connectionState == .connected ? Color.green : Color.gray)
                            .frame(width: 8, height: 8)
                        Text(L10n.tr(linkDevice.connectionState.localizedKey))
                            .font(.subheadline.weight(.semibold))
                    }
                }
                Spacer()
                Button {
                    if linkDevice.connectionState == .connected {
                        bluetoothManager.disconnect(linkDevice)
                    } else {
                        bluetoothManager.connect(linkDevice)
                    }
                } label: {
                    Text(
                        linkDevice.connectionState == .connected
                            ? L10n.tr("disconnect")
                            : L10n.tr("connect_device")
                    )
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Capsule().fill(
                            linkDevice.connectionState == .connected
                                ? Color.secondary.opacity(0.16)
                                : Color.accentColor
                        )
                    )
                    .foregroundColor(
                        linkDevice.connectionState == .connected
                            ? .primary
                            : .white
                    )
                }
            }

            if linkDevice.connectionState == .connected,
               let battery = linkDevice.btDeviceInfo.batteryLevel {
                Divider()
                HStack(spacing: 12) {
                    batteryBadge(title: L10n.tr("left"), percent: battery.left, icon: "l.circle.fill")
                    batteryBadge(title: L10n.tr("right"), percent: battery.right, icon: "r.circle.fill")
                    batteryBadge(title: L10n.tr("tws_case"), percent: battery.box, icon: "shippingbox.fill")
                }
            }
        }
        .sectionCardStyle()
    }

    private func batteryBadge(title: String, percent: Int, icon: String) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .foregroundColor(.accentColor)
                Text(title)
                    .font(.caption.weight(.medium))
            }
            Text(percent > 0 ? "\(percent)%" : "--")
                .font(.subheadline.weight(.bold))
                .foregroundColor(percent > 0 && percent <= 20 ? .red : .primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(UIColor.tertiarySystemGroupedBackground))
        )
    }

    private var disconnectedNoticeCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "bolt.horizontal.circle")
                .font(.system(size: 34))
                .foregroundColor(.secondary)
            Text(L10n.tr("device_not_connected"))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .sectionCardStyle()
    }

    @ViewBuilder
    private func featureView(for feature: Feature) -> some View {
        switch feature.featureType {
        case .BtNoiseControl:
            NoiseControlSectionView(linkDevice: linkDevice)
        case .BtEqualizerSetting:
            EQSelectionSectionView(linkDevice: linkDevice)
        case .BtToneVolume:
            ToneVolumeSectionView(linkDevice: linkDevice)
        case .BtCodecControl:
            CodecSelectionSectionView(linkDevice: linkDevice)
        case .BtGameMode:
            GameModeSectionView(linkDevice: linkDevice, isV2: false)
        case .BtGameModeV2:
            GameModeSectionView(linkDevice: linkDevice, isV2: true)
        case .BtLatencyMode:
            LatencyModeSectionView(linkDevice: linkDevice, isV2: false)
        case .BtLatencyModeV2:
            LatencyModeSectionView(linkDevice: linkDevice, isV2: true)
        case .BtDualConnection:
            ConnectionSettingsSectionView(linkDevice: linkDevice)
        case .BtTouchControl:
            TouchControlSectionView(linkDevice: linkDevice, includeAncLoop: false)
        case .BtTouchControlWithAncControl:
            TouchControlSectionView(linkDevice: linkDevice, includeAncLoop: true)
        case .BtInEarDetection:
            InEarDetectionSectionView(linkDevice: linkDevice)
        case .BtOTA:
            OTASectionRowView(linkDevice: linkDevice, firmwareRepo: firmwareRepo)
        case .BtOriginExperiment:
            ExperimentFeatureRowView(linkDevice: linkDevice)
        case .BtFindEarbuds:
            FindEarbudsRowView(linkDevice: linkDevice)
        case .none:
            EmptyView()
        }
    }
}
