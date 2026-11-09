import SwiftUI

struct TouchControlSectionView: View {
    @ObservedObject var linkDevice: LinkDevice
    let includeAncLoop: Bool

    var body: some View {
        NavigationLink {
            TouchControlDetailPage(linkDevice: linkDevice, includeAncLoop: includeAncLoop)
        } label: {
            HStack {
                Label(L10n.tr("touch_control"), systemImage: "hand.tap.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                Spacer()
                Text(L10n.tr("configure_touch_controls"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
            }
            .sectionCardStyle()
        }
        .buttonStyle(.plain)
    }
}

struct TouchControlDetailPage: View {
    @ObservedObject var linkDevice: LinkDevice
    let includeAncLoop: Bool
    @State private var selectedSide: TouchControlSide = .left

    private var sideItems: [TouchControlItem] {
        if let tc = linkDevice.btDeviceInfo.touchControl {
            let existing = tc.items(for: selectedSide)
            if !existing.isEmpty {
                return existing
            }
        }
        return TouchControlOperation.allCases.map { op in
            TouchControlItem(side: selectedSide, keyType: .noType, operation: op, function: .none)
        }
    }

    private var ancLoopItems: [AncTouchControlItem] {
        if let anc = linkDevice.btDeviceInfo.ancTouchControl, !anc.ancTouchControlItems.isEmpty {
            return anc.ancTouchControlItems
        }
        return NoiseFunc.allCases.map { AncTouchControlItem(function: $0, isCheck: true) }
    }

    var body: some View {
        List {
            Section {
                Picker(L10n.tr("earbud_control"), selection: $selectedSide) {
                    ForEach(TouchControlSide.allCases) { side in
                        Text(L10n.tr(side.localizedKey)).tag(side)
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            }

            Section(header: Text(L10n.tr(selectedSide.localizedKey))) {
                ForEach(sideItems) { item in
                    Picker(
                        L10n.tr(item.operation.localizedKey),
                        selection: Binding(
                            get: { item.function },
                            set: { newFunc in
                                item.function = newFunc
                                linkDevice.setTouchControl(
                                    side: selectedSide,
                                    operation: item.operation,
                                    function: newFunc
                                )
                            }
                        )
                    ) {
                        ForEach(TouchControlFunc.allCases) { fn in
                            Text(L10n.tr(fn.localizedKey)).tag(fn)
                        }
                    }
                }
            }

            if includeAncLoop {
                Section(header: Text(L10n.tr("noise_control_loop"))) {
                    ForEach(ancLoopItems) { ancItem in
                        Button {
                            toggleAncLoopItem(ancItem)
                        } label: {
                            HStack {
                                Text(L10n.tr(ancItem.function.localizedKey))
                                    .foregroundColor(.primary)
                                Spacer()
                                Image(systemName: ancItem.isCheck ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(ancItem.isCheck ? .accentColor : .secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(L10n.tr("touch_control"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func toggleAncLoopItem(_ target: AncTouchControlItem) {
        var current = ancLoopItems.map {
            AncTouchControlItem(function: $0.function, isCheck: $0.isCheck)
        }
        guard let idx = current.firstIndex(where: { $0.function == target.function }) else { return }
        let checkedCount = current.filter(\.isCheck).count
        // Require at least 2 active modes in the ANC cycle
        if current[idx].isCheck && checkedCount <= 2 {
            return
        }
        current[idx].isCheck.toggle()
        linkDevice.btDeviceInfo.ancTouchControl = AncTouchControl(ancTouchControlItems: current)
        linkDevice.setAncTouchControl(items: current)
    }
}

struct InEarDetectionSectionView: View {
    @ObservedObject var linkDevice: LinkDevice

    private var isEnabled: Binding<Bool> {
        Binding(
            get: { linkDevice.btDeviceInfo.inEarDetection ?? false },
            set: { newValue in
                linkDevice.setInEarDetection(newValue)
            }
        )
    }

    var body: some View {
        Toggle(isOn: isEnabled) {
            Label(L10n.tr("in_ear_detection"), systemImage: "ear.badge.checkmark")
                .font(.subheadline.weight(.semibold))
        }
        .sectionCardStyle()
    }
}
