import SwiftUI

struct ContentView: View {
    @EnvironmentObject var bluetoothManager: BluetoothManager
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        DeviceListView()
            .onChange(of: scenePhase) { newPhase in
                if newPhase == .active {
                    bluetoothManager.checkSystemConnectedGattDevices()
                    bluetoothManager.reconnectDisconnectedSavedDevices()
                }
            }
    }
}
