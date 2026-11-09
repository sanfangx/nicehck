import SwiftUI

struct NoiseControlSectionView: View {
    @ObservedObject var linkDevice: LinkDevice
    @ObservedObject private var experimentStore = ExperimentNoiseCancelingDataStore.shared

    private var currentMode: NoiseMode {
        linkDevice.btDeviceInfo.noiseControl?.mode ?? .off
    }

    private var currentMainState: MainNoiseControlState {
        currentMode.mainState
    }

    private var availableMainStates: [MainNoiseControlState] {
        if linkDevice.btDeviceInfo.experimentWind == true {
            return [.off, .transparency, .windNoiseCanceling, .noiseCanceling]
        } else {
            return [.off, .transparency, .noiseCanceling]
        }
    }

    private var availableSubModes: [NoiseMode] {
        var modes: [NoiseMode] = [.on, .deepNoiseCanceling]
        if experimentStore.isEnabled(for: linkDevice.identify) ||
           currentMode == .experimental_noise_canceling {
            modes.append(.experimental_noise_canceling)
        }
        return modes
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(L10n.tr("noise_control"), systemImage: "waveform")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(L10n.tr(currentMode.localizedKey))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 8) {
                ForEach(availableMainStates, id: \.rawValue) { mainState in
                    let isSelected = (currentMainState == mainState)
                    Button {
                        let targetMode = SetNoiseControlLogic.resolveTargetMode(
                            for: mainState,
                            deviceIdentify: linkDevice.identify
                        )
                        linkDevice.setNoiseControl(mode: targetMode)
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: mainState.systemIconName)
                                .font(.system(size: 18, weight: .semibold))
                            Text(L10n.tr(mainState.localizedKey))
                                .font(.caption2.weight(.medium))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(isSelected ? Color.accentColor : Color(UIColor.tertiarySystemGroupedBackground))
                        )
                        .foregroundColor(isSelected ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }

            if currentMainState == .noiseCanceling {
                Divider()
                HStack(spacing: 8) {
                    ForEach(availableSubModes, id: \.rawValue) { subMode in
                        let isSubSelected = (currentMode == subMode)
                        Button {
                            linkDevice.setNoiseControl(mode: subMode)
                        } label: {
                            Text(L10n.tr(subMode.localizedKey))
                                .font(.caption.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(isSubSelected ? Color.accentColor.opacity(0.18) : Color(UIColor.tertiarySystemGroupedBackground))
                                )
                                .overlay(
                                    Capsule()
                                        .stroke(isSubSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
                                )
                                .foregroundColor(isSubSelected ? .accentColor : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .sectionCardStyle()
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: currentMode)
    }
}
