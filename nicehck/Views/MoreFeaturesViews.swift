import SwiftUI

struct ExperimentFeatureRowView: View {
    @ObservedObject var linkDevice: LinkDevice

    var body: some View {
        NavigationLink {
            ExperimentFeatureView(linkDevice: linkDevice)
        } label: {
            HStack {
                Label(L10n.tr("experimental_features"), systemImage: "flask.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
            }
            .sectionCardStyle()
        }
        .buttonStyle(.plain)
    }
}

struct ExperimentFeatureView: View {
    @ObservedObject var linkDevice: LinkDevice
    @ObservedObject private var experimentStore = ExperimentNoiseCancelingDataStore.shared

    private var isExpNoiseEnabled: Binding<Bool> {
        Binding(
            get: {
                experimentStore.isEnabled(for: linkDevice.identify) ||
                linkDevice.btDeviceInfo.noiseControl?.mode == .experimental_noise_canceling
            },
            set: { newValue in
                linkDevice.setExperimentalNoiseCanceling(newValue)
            }
        )
    }

    private var isExpWindEnabled: Binding<Bool> {
        Binding(
            get: { linkDevice.btDeviceInfo.experimentWind ?? false },
            set: { newValue in
                linkDevice.setExperimentWind(newValue)
            }
        )
    }

    var body: some View {
        List {
            Section(
                footer: Text(L10n.tr("these_features_are_still_in_testing_and_may_be_unstable"))
            ) {
                Toggle(L10n.tr("experimental_noise_canceling"), isOn: isExpNoiseEnabled)
            }

            Section(
                footer: Text(L10n.tr("experimental_wind_noise_tip"))
            ) {
                Toggle(L10n.tr("experimental_wind_noise_mode"), isOn: isExpWindEnabled)
            }
        }
        .navigationTitle(L10n.tr("experimental_features"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct FindEarbudsRowView: View {
    @ObservedObject var linkDevice: LinkDevice

    var body: some View {
        NavigationLink {
            FindEarbudsView(linkDevice: linkDevice)
        } label: {
            HStack {
                Label(L10n.tr("find_earbuds"), systemImage: "wave.3.right.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
            }
            .sectionCardStyle()
        }
        .buttonStyle(.plain)
    }
}

struct FindEarbudsView: View {
    @ObservedObject var linkDevice: LinkDevice
    @State private var isPlayingAlert = false
    @State private var pulseScale: CGFloat = 1.0

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            ZStack {
                if isPlayingAlert {
                    Circle()
                        .stroke(Color.accentColor.opacity(0.35), lineWidth: 3)
                        .frame(width: 140, height: 140)
                        .scaleEffect(pulseScale)
                        .opacity(2.0 - Double(pulseScale))
                }

                Circle()
                    .fill(isPlayingAlert ? Color.accentColor.opacity(0.18) : Color(UIColor.secondarySystemGroupedBackground))
                    .frame(width: 120, height: 120)

                Image(systemName: isPlayingAlert ? "speaker.wave.3.fill" : "earbuds")
                    .font(.system(size: 44))
                    .foregroundColor(isPlayingAlert ? .accentColor : .secondary)
            }

            VStack(spacing: 10) {
                Text(L10n.tr(isPlayingAlert ? "playing_alert_sound" : "find_my_earbuds"))
                    .font(.title3.weight(.bold))

                Text(L10n.tr(isPlayingAlert ? "alert_sound_description" : "find_earbuds_description"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Button {
                toggleAlertSound()
            } label: {
                Text(L10n.tr(isPlayingAlert ? "stop_alert" : "start_find"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        Capsule().fill(isPlayingAlert ? Color.red : Color.accentColor)
                    )
                    .foregroundColor(.white)
                    .padding(.horizontal, 32)
            }

            Spacer()
        }
        .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(L10n.tr("find_earbuds"))
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            if isPlayingAlert {
                linkDevice.setFindEarbuds(playing: false)
                isPlayingAlert = false
            }
        }
    }

    private func toggleAlertSound() {
        let nextState = !isPlayingAlert
        isPlayingAlert = nextState
        linkDevice.setFindEarbuds(playing: nextState)

        if nextState {
            pulseScale = 1.0
            withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) {
                pulseScale = 1.65
            }
        } else {
            pulseScale = 1.0
        }
    }
}
