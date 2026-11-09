import SwiftUI

@main
struct nicehckApp: App {
    @StateObject private var bluetoothManager = BluetoothManager.shared
    @AppStorage("theme_mode") private var themeModeRaw: String = ThemeMode.system.rawValue

    private var currentTheme: ThemeMode {
        ThemeMode(rawValue: themeModeRaw) ?? .system
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(bluetoothManager)
                .preferredColorScheme(currentTheme.colorScheme)
        }
    }
}
