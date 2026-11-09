import SwiftUI

/// Settings & About page (excludes online feedback per user requirement)
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("theme_mode") private var themeModeRaw: String = ThemeMode.system.rawValue

    private var selectedTheme: Binding<ThemeMode> {
        Binding(
            get: { ThemeMode(rawValue: themeModeRaw) ?? .system },
            set: { themeModeRaw = $0.rawValue }
        )
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.2.7"
    }

    var body: some View {
        NavigationStack {
            List {
                Section(header: Text(L10n.tr("settings"))) {
                    Picker(L10n.tr("theme_mode"), selection: selectedTheme) {
                        ForEach(ThemeMode.allCases) { mode in
                            Text(L10n.tr(mode.localizedKey))
                                .tag(mode)
                        }
                    }
                }

                Section(header: Text(L10n.tr("app_info"))) {
                    HStack {
                        Text(L10n.tr("app_name"))
                        Spacer()
                        Text(L10n.tr("PRODUCT_NAME"))
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text(L10n.tr("app_version"))
                        Spacer()
                        Text("v\(appVersion)")
                            .foregroundColor(.secondary)
                    }
                }

                Section(header: Text(L10n.tr("legal_info"))) {
                    if let policyURL = URL(string: "https://nicehck.cn/privacy.html") {
                        Link(destination: policyURL) {
                            HStack {
                                Text(L10n.tr("privacy_policy"))
                                    .foregroundColor(.primary)
                                Spacer()
                                Image(systemName: "arrow.up.right.square")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle(L10n.tr("about"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(L10n.tr("done")) {
                        dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(selectedTheme.wrappedValue.colorScheme)
    }
}
