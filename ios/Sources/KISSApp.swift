import SwiftUI

@main
struct KISSApp: App {
    @StateObject var ble = BLEManager.shared
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(ble)
                .onAppear { ble.start() }
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var ble: BLEManager
    @AppStorage("dev") var dev = "a"
    @AppStorage("token_a") var tokenA = ""
    @AppStorage("token_b") var tokenB = ""

    var body: some View {
        NavigationView {
            Form {
                Section("Gerät") {
                    Picker("Ich bin", selection: $dev) {
                        Text("A").tag("a")
                        Text("B").tag("b")
                    }.pickerStyle(.segmented)
                    SecureField("Token A", text: $tokenA)
                    SecureField("Token B", text: $tokenB)
                }
                Section("Status") {
                    HStack { Text("Stick"); Spacer()
                        Text(ble.connected ? "verbunden" : "getrennt")
                            .foregroundColor(ble.connected ? .green : .secondary) }
                    HStack { Text("Kuss offen"); Spacer(); Text(ble.pending ? "JA" : "nein") }
                    HStack { Text("gesendet \(ble.sent)"); Spacer(); Text("empfangen \(ble.recv)") }
                    Text(ble.status).font(.footnote).foregroundColor(.secondary)
                }
                Section("Aktionen") {
                    Button("Neu verbinden") { ble.start() }
                    Button("Status abrufen") { ble.pollState() }
                }
                Section("Log") {
                    ForEach(ble.log, id: \.self) { line in
                        Text(line).font(.system(.caption, design: .monospaced))
                    }
                }
            }
            .navigationTitle("K · I · S · S")
        }
        .navigationViewStyle(.stack)
    }
}
