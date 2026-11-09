import SwiftUI

struct GameModeSectionView: View {
    @ObservedObject var linkDevice: LinkDevice
    let isV2: Bool

    private var isEnabled: Binding<Bool> {
        Binding(
            get: { linkDevice.btDeviceInfo.gameMode ?? false },
            set: { newValue in
                if isV2 && newValue && (linkDevice.btDeviceInfo.dualConnection == true) {
                    linkDevice.setDualConnection(false)
                }
                linkDevice.setGameMode(newValue)
            }
        )
    }

    var body: some View {
        Toggle(isOn: isEnabled) {
            Label(L10n.tr("game_mode"), systemImage: "gamecontroller.fill")
                .font(.subheadline.weight(.semibold))
        }
        .sectionCardStyle()
    }
}

struct LatencyModeSectionView: View {
    @ObservedObject var linkDevice: LinkDevice
    let isV2: Bool

    private var isEnabled: Binding<Bool> {
        Binding(
            get: { linkDevice.btDeviceInfo.lowLatencyMode ?? false },
            set: { newValue in
                if isV2 && newValue && (linkDevice.btDeviceInfo.dualConnection == true) {
                    linkDevice.setDualConnection(false)
                }
                linkDevice.setLowLatencyMode(newValue)
            }
        )
    }

    var body: some View {
        Toggle(isOn: isEnabled) {
            Label(L10n.tr("low_latency_mode"), systemImage: "bolt.fill")
                .font(.subheadline.weight(.semibold))
        }
        .sectionCardStyle()
    }
}
