import SwiftUI
import UIKit

struct OTASectionRowView: View {
    @ObservedObject var linkDevice: LinkDevice
    @ObservedObject var firmwareRepo: FirmwareRepository

    private var hasNewVersion: Bool {
        if case .shouldUpdate = firmwareRepo.updateState {
            return true
        }
        return false
    }

    var body: some View {
        NavigationLink {
            FirmwareUpdateView(linkDevice: linkDevice, firmwareRepo: firmwareRepo)
        } label: {
            HStack {
                Label(L10n.tr("firmware_update"), systemImage: "arrow.triangle.2.circlepath.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                Spacer()
                if hasNewVersion {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                }
                if let fw = linkDevice.btDeviceInfo.firmwareVersion {
                    Text(fw)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
            }
            .sectionCardStyle()
        }
        .buttonStyle(.plain)
    }
}

struct FirmwareUpdateView: View {
    @ObservedObject var linkDevice: LinkDevice
    @ObservedObject var firmwareRepo: FirmwareRepository
    @StateObject private var otaManager: OTAManager
    @Environment(\.dismiss) private var dismiss
    @State private var hasCopiedDiagnostics = false

    init(linkDevice: LinkDevice, firmwareRepo: FirmwareRepository) {
        self.linkDevice = linkDevice
        self.firmwareRepo = firmwareRepo
        _otaManager = StateObject(wrappedValue: OTAManager(linkDevice: linkDevice))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                currentVersionCard
                importantNoticesCard
                updateStatusContent
                diagnosticsCard
                liveLogCard
            }
            .padding(16)
        }
        .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(L10n.tr("firmware_update"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            Task {
                await firmwareRepo.checkFirmwareUpdate(
                    deviceId: linkDevice.device.id,
                    currentVersion: linkDevice.btDeviceInfo.firmwareVersionInt
                )
            }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onChange(of: linkDevice.btDeviceInfo.firmwareVersion) { _ in
            guard !otaManager.isUpgrading else { return }
            Task {
                await firmwareRepo.checkFirmwareUpdate(
                    deviceId: linkDevice.device.id,
                    currentVersion: linkDevice.btDeviceInfo.firmwareVersionInt
                )
            }
        }
    }

    private func refreshDiagnosticsAndFirmware() {
        linkDevice.queryAllState()
        Task {
            await firmwareRepo.checkFirmwareUpdate(
                deviceId: linkDevice.device.id,
                currentVersion: linkDevice.btDeviceInfo.firmwareVersionInt
            )
        }
    }

    private func fullDiagnosticReport() -> String {
        var lines: [String] = [
            "Device: \(linkDevice.device.displayName) (deviceId=\(linkDevice.device.id))",
            "Connection: \(linkDevice.connectionState.rawValue), isOTAReady=\(linkDevice.isOTAReady)",
            "Parsed Version: \(linkDevice.btDeviceInfo.firmwareVersion ?? "nil") (int=\(linkDevice.btDeviceInfo.firmwareVersionInt))",
            "Parsed BT Device ID: \(linkDevice.btDeviceInfo.btDeviceId ?? "nil")",
            "0x0003 Raw Hex: \(linkDevice.btDeviceInfo.rawFirmwareVersionHex ?? "nil")",
            "0x0001 Raw Hex: \(linkDevice.btDeviceInfo.rawDeviceIdHex ?? "nil")",
            "ATT Max Write: \(linkDevice.maxOTAWriteLength) B (\(linkDevice.otaWriteTypeName))",
            "Server Summary: \(firmwareRepo.lastHttpSummary ?? "nil")",
            "Server URL: \(firmwareRepo.lastFirmwareInfo?.downloadUrl ?? "nil")"
        ]
        if !otaManager.currentStepDetail.isEmpty {
            lines.append("OTA Step: \(otaManager.currentStepDetail)")
        }
        if let err = otaManager.state.error {
            lines.append("OTA Error: \(err)")
        }
        lines.append("--- OTA Log (\(otaManager.diagnosticLogs.count) lines) ---")
        if otaManager.diagnosticLogs.isEmpty {
            lines.append("(empty)")
        } else {
            lines.append(otaManager.formattedDiagnosticLog)
        }
        return lines.joined(separator: "\n")
    }

    private var currentVersionCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.tr("device_name"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(linkDevice.device.displayName)
                    .font(.headline)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Text(L10n.tr("current_version"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(linkDevice.btDeviceInfo.firmwareVersion ?? L10n.tr("unknown"))
                    .font(.headline.monospacedDigit())
            }
        }
        .sectionCardStyle()
    }

    private var importantNoticesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L10n.tr("important_notice"), systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.orange)

            noticeRow(L10n.tr("ensure_battery_level"))
            noticeRow(L10n.tr("put_in_case"))
            noticeRow(L10n.tr("do_not_disconnect_bluetooth"))
            noticeRow(L10n.tr("do_not_exit_app"))
            noticeRow(L10n.tr("keep_screen_on"))
            noticeRow(L10n.tr("if_ota_error"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sectionCardStyle()
    }

    private func noticeRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .foregroundColor(.secondary)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private var updateStatusContent: some View {
        switch otaManager.state.step {
        case .started, .progress:
            otaInProgressCard
        case .completed:
            otaCompletedCard
        case .error:
            otaErrorCard
        case .unstart:
            repositoryStateCard
        }
    }

    @ViewBuilder
    private var repositoryStateCard: some View {
        switch firmwareRepo.updateState {
        case .checking:
            HStack(spacing: 12) {
                ProgressView()
                Text(L10n.tr("checking"))
                    .font(.subheadline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .sectionCardStyle()

        case .noUpdate(let info):
            VStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 38))
                    .foregroundColor(.green)
                Text(L10n.tr("already_up_to_date"))
                    .font(.headline)
                if let info = info {
                    Text("\(L10n.tr("ota_latest_version")) \(info.firmwareName)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .sectionCardStyle()

        case .shouldUpdate(let info):
            firmwareReleaseCard(info: info, downloadedData: nil)

        case .downloading(let info):
            VStack(spacing: 12) {
                ProgressView()
                Text(L10n.tr("downloading_firmware"))
                    .font(.subheadline)
                Text(info.firmwareName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .sectionCardStyle()

        case .downloadComplete(let info, let data):
            firmwareReleaseCard(info: info, downloadedData: data)

        case .networkFailed:
            VStack(spacing: 14) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 36))
                    .foregroundColor(.orange)
                Text(L10n.tr("no_network_error"))
                    .font(.headline)
                Text(L10n.tr("firmware_update_requires_network"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                Button(L10n.tr("retry")) {
                    Task {
                        await firmwareRepo.checkFirmwareUpdate(
                            deviceId: linkDevice.device.id,
                            currentVersion: linkDevice.btDeviceInfo.firmwareVersionInt
                        )
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .sectionCardStyle()

        case .failed(let message):
            VStack(spacing: 14) {
                Image(systemName: "xmark.octagon.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.red)
                Text(L10n.tr("error"))
                    .font(.headline)
                Text(message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                Button(L10n.tr("retry")) {
                    Task {
                        await firmwareRepo.checkFirmwareUpdate(
                            deviceId: linkDevice.device.id,
                            currentVersion: linkDevice.btDeviceInfo.firmwareVersionInt
                        )
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .sectionCardStyle()
        }
    }

    private func firmwareReleaseCard(info: FirmwareInfo, downloadedData: Data?) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(L10n.tr("nwer_version"))
                    .font(.headline)
                Spacer()
                Text(info.firmwareName)
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(.accentColor)
            }

            Divider()

            Text(L10n.tr("description"))
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)

            Text(info.firmwareDesc)
                .font(.subheadline)
                .foregroundColor(.primary)

            Button {
                Task {
                    if let data = downloadedData {
                        await otaManager.startOTA(imageData: data)
                    } else {
                        await firmwareRepo.downloadFirmware(info: info)
                        if case .downloadComplete(_, let fwData) = firmwareRepo.updateState {
                            await otaManager.startOTA(imageData: fwData)
                        }
                    }
                }
            } label: {
                Text(
                    downloadedData != nil
                        ? L10n.tr("start_update")
                        : L10n.tr("download_and_install")
                )
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Capsule().fill(Color.accentColor))
                .foregroundColor(.white)
            }
        }
        .sectionCardStyle()
    }

    private var otaInProgressCard: some View {
        VStack(spacing: 14) {
            HStack {
                Text(L10n.tr("update_progress"))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(Int(otaManager.state.progress * 100))%")
                    .font(.subheadline.monospacedDigit().weight(.bold))
                    .foregroundColor(.accentColor)
            }

            ProgressView(value: Double(otaManager.state.progress), total: 1.0)
                .progressViewStyle(.linear)

            Text(L10n.tr(otaManager.state.statusTextKey))
                .font(.caption)
                .foregroundColor(.secondary)

            if !otaManager.currentStepDetail.isEmpty {
                Text(otaManager.currentStepDetail)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
        .sectionCardStyle()
    }

    private var otaCompletedCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundColor(.green)
            Text(L10n.tr("update_completed"))
                .font(.headline)
            Button(L10n.tr("done")) {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .sectionCardStyle()
    }

    private var otaErrorCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.octagon.fill")
                .font(.system(size: 42))
                .foregroundColor(.red)
            Text(L10n.tr("update_failed"))
                .font(.headline)
            if let err = otaManager.state.error {
                Text(err)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button(L10n.tr("retry")) {
                otaManager.reset()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .sectionCardStyle()
    }

    private var diagnosticsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(L10n.tr("ota_diagnostics_title"), systemImage: "stethoscope")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    refreshDiagnosticsAndFirmware()
                } label: {
                    Label(L10n.tr("ota_refresh_action"), systemImage: "arrow.clockwise")
                        .font(.caption.weight(.medium))
                }
                .disabled(otaManager.isUpgrading)
            }

            Divider()

            diagnosticRow(
                L10n.tr("ota_diag_raw_version"),
                "\(linkDevice.btDeviceInfo.rawFirmwareVersionHex ?? "nil") -> \(linkDevice.btDeviceInfo.firmwareVersion ?? "nil") (\(linkDevice.btDeviceInfo.firmwareVersionInt))"
            )
            diagnosticRow(
                L10n.tr("ota_diag_raw_device_id"),
                "\(linkDevice.btDeviceInfo.rawDeviceIdHex ?? "nil") -> \(linkDevice.btDeviceInfo.btDeviceId ?? "nil")"
            )
            diagnosticRow(
                L10n.tr("ota_diag_ota_ready"),
                linkDevice.isOTAReady ? "true" : "false"
            )
            diagnosticRow(
                L10n.tr("ota_diag_max_write"),
                "\(linkDevice.maxOTAWriteLength) B (\(linkDevice.otaWriteTypeName))"
            )
            diagnosticRow(
                L10n.tr("ota_diag_server_result"),
                firmwareRepo.lastHttpSummary ?? "-"
            )
            if let url = firmwareRepo.lastFirmwareInfo?.downloadUrl {
                diagnosticRow(L10n.tr("ota_diag_server_url"), url)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sectionCardStyle()
    }

    private func diagnosticRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.primary)
                .textSelection(.enabled)
        }
    }

    private var liveLogCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(L10n.tr("ota_logs_title"), systemImage: "terminal")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    UIPasteboard.general.string = fullDiagnosticReport()
                    hasCopiedDiagnostics = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        hasCopiedDiagnostics = false
                    }
                } label: {
                    Text(hasCopiedDiagnostics ? L10n.tr("ota_logs_copied") : L10n.tr("ota_copy_logs"))
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if otaManager.diagnosticLogs.isEmpty {
                Text(L10n.tr("ota_logs_empty"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 6)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 3) {
                            ForEach(Array(otaManager.diagnosticLogs.enumerated()), id: \.offset) { item in
                                Text(item.element)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundColor(.primary)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            Color.clear
                                .frame(height: 1)
                                .id("otaLogBottom")
                        }
                    }
                    .frame(maxHeight: 220)
                    .onChange(of: otaManager.diagnosticLogs.count) { _ in
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo("otaLogBottom", anchor: .bottom)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sectionCardStyle()
    }
}
