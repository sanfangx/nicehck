import SwiftUI

struct EQSelectionSectionView: View {
    @ObservedObject var linkDevice: LinkDevice

    private var availablePresets: [BtEqualizer] {
        DeviceManager.shared.availableEqualizers(
            for: linkDevice.device.id,
            firmwareVersion: linkDevice.btDeviceInfo.firmwareVersionInt
        )
    }

    private var selectedEqIndex: Int {
        linkDevice.btDeviceInfo.eqIndex ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(L10n.tr("eq_settings"), systemImage: "slider.vertical.3")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let current = availablePresets.first(where: { $0.eqIndex == selectedEqIndex }) {
                    Text(L10n.tr(current.name))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                spacing: 10
            ) {
                ForEach(availablePresets) { preset in
                    let isSelected = (preset.eqIndex == selectedEqIndex)
                    Button {
                        linkDevice.setEqIndex(preset.eqIndex)
                    } label: {
                        HStack {
                            Text(L10n.tr(preset.name))
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                            Spacer()
                            if isSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(isSelected ? Color.accentColor : Color(UIColor.tertiarySystemGroupedBackground))
                        )
                        .foregroundColor(isSelected ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .sectionCardStyle()
    }
}

struct ToneVolumeSectionView: View {
    @ObservedObject var linkDevice: LinkDevice
    @State private var sliderValue: Double = 50
    @State private var isEditing: Bool = false

    private var deviceVolume: Int {
        linkDevice.btDeviceInfo.toneVolume ?? 50
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(L10n.tr("prompt_tone_volume"), systemImage: "speaker.wave.2.fill")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(Int(sliderValue))%")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            }

            Slider(
                value: $sliderValue,
                in: 0...100,
                step: 1,
                onEditingChanged: { editing in
                    isEditing = editing
                    if !editing {
                        linkDevice.setToneVolume(Int(sliderValue))
                    }
                }
            )
        }
        .sectionCardStyle()
        .onAppear {
            sliderValue = Double(deviceVolume)
        }
        .onChange(of: linkDevice.btDeviceInfo.toneVolume) { newVolume in
            if !isEditing, let v = newVolume {
                sliderValue = Double(v)
            }
        }
    }
}

struct CodecSelectionSectionView: View {
    @ObservedObject var linkDevice: LinkDevice

    private var currentCodec: CodecEnum {
        linkDevice.btDeviceInfo.codec ?? .acc
    }

    var body: some View {
        HStack {
            Label("Codec", systemImage: "hifispeaker.fill")
                .font(.subheadline.weight(.semibold))
            Spacer()
            Text(currentCodec.displayName)
                .font(.caption.weight(.bold))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(Color.accentColor.opacity(0.15))
                )
                .foregroundColor(.accentColor)
        }
        .sectionCardStyle()
    }
}
