import SwiftUI

struct ConnectionSettingsSectionView: View {
    @ObservedObject var linkDevice: LinkDevice

    private var isDualConnected: Binding<Bool> {
        Binding(
            get: { linkDevice.btDeviceInfo.dualConnection ?? false },
            set: { newValue in
                linkDevice.setDualConnection(newValue)
            }
        )
    }

    var body: some View {
        Toggle(isOn: isDualConnected) {
            Label(L10n.tr("dual_connection"), systemImage: "point.3.connected.trianglepath.dotted")
                .font(.subheadline.weight(.semibold))
        }
        .sectionCardStyle()
    }
}
