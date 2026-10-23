import SwiftUI

@main
struct KISSApp: App {
    @StateObject var ble = BLEManager.shared
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(ble)
                .onAppear { if shot == nil { ble.start() } }
                .preferredColorScheme(.dark)
        }
    }
}

// Farben wie Android-App und Icon (KissPink #FF4D77, Grund #14101A)
enum K {
    static let bg = Color(red: 0x14/255, green: 0x10/255, blue: 0x1A/255)
    static let card = Color(red: 0x2C/255, green: 0x24/255, blue: 0x2D/255)
    static let pink = Color(red: 1, green: 0x4D/255, blue: 0x77/255)
    static let pinkSoft = Color(red: 1, green: 0xB1/255, blue: 0xC3/255)
    static let text = Color(red: 0xEC/255, green: 0xE0/255, blue: 0xE3/255)
    static let muted = Color(red: 0xD5/255, green: 0xC2/255, blue: 0xC6/255)
    static let mint = Color(red: 0x4F/255, green: 0xD6/255, blue: 0xAE/255)
}

/// Fuer Screenshots im Simulator: Startargument `-shot welcome|code|connect|home|settings`
/// zeigt den Bildschirm mit Beispielzahlen, ohne Geraet und ohne Server.
let shot = UserDefaults.standard.string(forKey: "shot")

struct RootView: View {
    @AppStorage("setupDone") var setupDone = false

    var body: some View {
        ZStack {
            K.bg.ignoresSafeArea()
            if let s = shot {
                if ["welcome", "code", "connect"].contains(s) {
                    SetupView(step: ["welcome", "code", "connect"].firstIndex(of: s)!)
                } else {
                    HomeView(showSettings: s == "settings")
                }
            } else if setupDone {
                HomeView()
            } else {
                SetupView()
            }
        }
        .foregroundColor(K.text)
    }
}

// MARK: Einrichtung -- gefuehrt, zum gemeinsamen Durchgehen

struct SetupView: View {
    @EnvironmentObject var ble: BLEManager
    @AppStorage("setupDone") var setupDone = false
    @AppStorage("dev") var dev = "a"
    @State var step = 0
    @State var code = ""
    @State var checking = false
    @State var error: String?

    init(step: Int = 0) { _step = State(initialValue: step) }

    var body: some View {
        VStack(spacing: 0) {
            Dots(count: 3, current: step).padding(.top, 24)
            Spacer()
            Group {
                switch step {
                case 0: welcome
                case 1: codeEntry
                default: connect
                }
            }
            .padding(.horizontal, 28)
            Spacer()
        }
        .animation(.easeInOut(duration: 0.25), value: step)
    }

    var welcome: some View {
        VStack(spacing: 22) {
            Heart(size: 120)
            Text("K · I · S · S").font(.system(size: 34, weight: .heavy, design: .rounded))
            Text("Ein Druck aufs Herz, und drüben zählt es eins hoch.\nWir richten das jetzt zusammen ein. Dauert eine Minute.")
                .multilineTextAlignment(.center).foregroundColor(K.muted)
            // Jana hat immer Geraet A; B stellt Steven bei Bedarf im Zahnrad um.
            Big("Los geht's") { dev = "a"; step = 1 }.padding(.top, 12)
        }
    }

    var codeEntry: some View {
        VStack(spacing: 22) {
            Title(n: 1, "Code eingeben")
            Text("Den Code bekommst du von Steven.")
                .multilineTextAlignment(.center).foregroundColor(K.muted)
            TextField("Code", text: $code)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .font(.system(size: 22, weight: .semibold, design: .monospaced))
                .multilineTextAlignment(.center)
                .padding(.vertical, 16)
                .background(RoundedRectangle(cornerRadius: 16).fill(K.card))
            if let e = error {
                Text(e).font(.footnote).foregroundColor(K.pinkSoft).multilineTextAlignment(.center)
            }
            Big(checking ? "Prüfe …" : "Prüfen", disabled: code.isEmpty || checking) { verify() }
            Back { step = 0 }
        }
    }

    var connect: some View {
        VStack(spacing: 22) {
            Title(n: 2, "Gerät verbinden")
            ZStack {
                Circle().fill(ble.connected ? K.mint.opacity(0.2) : K.card).frame(width: 150, height: 150)
                if ble.connected {
                    Image(systemName: "checkmark").font(.system(size: 60, weight: .bold)).foregroundColor(K.mint)
                } else {
                    Heart(size: 70)
                }
            }
            Text(ble.connected ? "Verbunden." : "Drück einmal auf das Herz am Gerät.\nDas iPhone findet es dann von selbst.")
                .multilineTextAlignment(.center).foregroundColor(K.muted)
            Big("Fertig") { setupDone = true }
            Back { step = 1 }
        }
    }

    /// Code einmal gegen den Server pruefen, bevor er gespeichert wird.
    func verify() {
        let c = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: ble.base + "/state") else { return }
        var r = URLRequest(url: url)
        r.setValue("Bearer \(c)", forHTTPHeaderField: "Authorization")
        checking = true; error = nil
        URLSession.shared.dataTask(with: r) { _, resp, _ in
            let st = (resp as? HTTPURLResponse)?.statusCode ?? 0
            DispatchQueue.main.async {
                checking = false
                switch st {
                case 200:
                    UserDefaults.standard.set(c, forKey: "token_\(dev)")
                    ble.pollState()
                    step = 2
                case 401, 403: error = "Der Code passt nicht. Groß- und Kleinschreibung beachten."
                default: error = "Keine Verbindung zum Server. Internet an?"
                }
            }
        }.resume()
    }
}

// MARK: Startseite

struct HomeView: View {
    @EnvironmentObject var ble: BLEManager
    @AppStorage("dev") var dev = "a"
    @State var showSettings: Bool

    init(showSettings: Bool = false) { _showSettings = State(initialValue: showSettings) }

    var demo: Bool { shot != nil }
    var sent: Int { demo ? 94 : ble.sent }
    var recv: Int { demo ? 97 : ble.recv }
    var waiting: Int { demo ? 2 : ble.wartend }
    var connected: Bool { demo ? false : ble.connected }

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Chip(connected: connected)
                Spacer()
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape.fill").font(.title3).foregroundColor(K.muted)
                }
            }
            .padding(.top, 12)

            Spacer()
            Heart(size: 150)
            Text("Gerät \(dev.uppercased())").font(.footnote).foregroundColor(K.muted)
            Spacer()

            if waiting > 0 {
                VStack(spacing: 6) {
                    Text(waiting == 1 ? "1 Kuss wartet" : "\(waiting) Küsse warten")
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                    Text(waiting == 1 ? "Halt am Gerät das Herz gedrückt, um ihn abzuholen." : "Halt am Gerät das Herz gedrückt, um sie abzuholen.").font(.footnote)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 18)
                .background(RoundedRectangle(cornerRadius: 22).fill(K.pink))
                .foregroundColor(.white)
            }

            HStack(spacing: 14) {
                Counter(value: sent, label: "▲ gesendet", color: K.pink)
                Counter(value: recv, label: "▼ empfangen", color: K.mint)
            }
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 24)
        .sheet(isPresented: $showSettings) { SettingsView().environmentObject(ble) }
        .onAppear { if !demo { ble.pollState() } }
    }
}

// MARK: Einstellungen (Technik bleibt hier, nicht auf der Startseite)

struct SettingsView: View {
    @EnvironmentObject var ble: BLEManager
    @Environment(\.dismiss) var dismiss
    @AppStorage("setupDone") var setupDone = false
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
                    SecureField("Code A", text: $tokenA)
                    SecureField("Code B", text: $tokenB)
                }
                Section("Status") {
                    // Seit Protokoll v2 ist das Geraet die meiste Zeit bewusst
                    // getrennt, damit sein Funkchip schlafen kann.
                    HStack { Text("Gerät"); Spacer()
                        Text(ble.connected ? "verbunden" : "schläft")
                            .foregroundColor(ble.connected ? .green : .secondary) }
                    HStack { Text("gesendet \(ble.sent)"); Spacer(); Text("empfangen \(ble.recv)") }
                    Text(ble.status).font(.footnote).foregroundColor(.secondary)
                }
                Section("Aktionen") {
                    Button("Neu verbinden") { ble.start() }
                    Button("Status abrufen") { ble.pollState() }
                    Button("Einrichtung neu starten") { setupDone = false; dismiss() }
                }
                Section("Log") {
                    ForEach(ble.log, id: \.self) { line in
                        Text(line).font(.system(.caption, design: .monospaced))
                    }
                }
            }
            .navigationTitle("Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: Bausteine

struct Heart: View {
    let size: CGFloat
    var body: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: size))
            .foregroundColor(K.pink)
            .shadow(color: K.pink.opacity(0.45), radius: size / 5)
    }
}

struct Counter: View {
    let value: Int, label: String, color: Color
    var body: some View {
        VStack(spacing: 4) {
            Text("\(value)").font(.system(size: 44, weight: .heavy, design: .rounded)).foregroundColor(color)
            Text(label).font(.footnote).foregroundColor(K.muted)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 20)
        .background(RoundedRectangle(cornerRadius: 22).fill(K.card))
    }
}

struct Chip: View {
    let connected: Bool
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(connected ? K.mint : K.muted.opacity(0.6)).frame(width: 8, height: 8)
            Text(connected ? "Gerät verbunden" : "Gerät schläft").font(.footnote)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Capsule().fill(K.card))
    }
}

struct Dots: View {
    let count: Int, current: Int
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { i in
                Capsule().fill(i == current ? K.pink : K.card)
                    .frame(width: i == current ? 22 : 8, height: 8)
            }
        }
    }
}

struct Title: View {
    let n: Int, text: String
    init(n: Int, _ text: String) { self.n = n; self.text = text }
    var body: some View {
        VStack(spacing: 6) {
            Text("SCHRITT \(n) VON 2").font(.caption.weight(.bold)).foregroundColor(K.pinkSoft)
            Text(text).font(.system(size: 28, weight: .heavy, design: .rounded)).multilineTextAlignment(.center)
        }
    }
}

struct Big: View {
    let title: String
    var disabled = false
    let action: () -> Void
    init(_ title: String, disabled: Bool = false, action: @escaping () -> Void) {
        self.title = title; self.disabled = disabled; self.action = action
    }
    var body: some View {
        Button(action: action) {
            Text(title).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 16)
                .background(RoundedRectangle(cornerRadius: 16).fill(disabled ? K.card : K.pink))
                .foregroundColor(disabled ? K.muted : .white)
        }
        .disabled(disabled)
    }
}

struct Back: View {
    let action: () -> Void
    var body: some View {
        Button("Zurück", action: action).font(.subheadline).foregroundColor(K.muted)
    }
}
