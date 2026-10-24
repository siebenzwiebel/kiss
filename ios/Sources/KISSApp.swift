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

/// Fuer Screenshots im Simulator: Startargument `-shot welcome|code|connect|guide1..guide4|home|settings`
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
                } else if s.hasPrefix("guide") {
                    GuideView(page: (Int(s.dropFirst(5)) ?? 1) - 1) {}
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
        if step == 3 {
            // Anleitung statt gedruckter Broschuere, danach ist die Einrichtung durch
            GuideView { setupDone = true }
        } else {
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
            Big("Weiter") { step = 3 }
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
    @State var showGuide = false

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
                Button { showGuide = true } label: {
                    Image(systemName: "questionmark.circle.fill").font(.title3).foregroundColor(K.muted)
                }
                .padding(.trailing, 8)
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
        .sheet(isPresented: $showGuide) { GuideView { showGuide = false } }
        .onAppear { if !demo { ble.pollState() } }
    }
}

// MARK: Anleitung -- die vier Innenseiten der Broschuere

struct GuideView: View {
    @State var page: Int
    let done: () -> Void

    init(page: Int = 0, done: @escaping () -> Void) {
        _page = State(initialValue: page); self.done = done
    }

    // Papierfarben der Broschuere, Schrift dunkel wie gedruckt
    static let rose = Color(red: 1, green: 0xDD/255, blue: 0xE8/255)
    static let mint = Color(red: 0xD9/255, green: 0xF5/255, blue: 0xEA/255)
    static let peach = Color(red: 1, green: 0xE9/255, blue: 0xDA/255)
    static let lilac = Color(red: 0xEE/255, green: 0xE7/255, blue: 0xF8/255)
    static let ink = Color(red: 0x2B/255, green: 0x16/255, blue: 0x22/255)
    static let inkSoft = Color(red: 0x6B/255, green: 0x4E/255, blue: 0x5E/255)
    static let pinkDeep = Color(red: 0xD2/255, green: 0x3C/255, blue: 0x76/255)
    static let mintDeep = Color(red: 0x1E/255, green: 0x9A/255, blue: 0x75/255)

    var bg: Color { [Self.rose, Self.mint, Self.peach, Self.lilac][page] }

    var body: some View {
        ZStack {
            bg.ignoresSafeArea().animation(.easeInOut(duration: 0.3), value: page)
            VStack(spacing: 0) {
                TabView(selection: $page) {
                    pageHow.tag(0)
                    pageButton.tag(1)
                    pageIncoming.tag(2)
                    pageEveryday.tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                HStack(spacing: 8) {
                    ForEach(0..<4, id: \.self) { i in
                        Capsule().fill(i == page ? Self.pinkDeep : Self.ink.opacity(0.15))
                            .frame(width: i == page ? 22 : 8, height: 8)
                    }
                }
                .padding(.bottom, 18)

                Button {
                    if page < 3 { withAnimation { page += 1 } } else { done() }
                } label: {
                    Text(page < 3 ? "Weiter" : "Fertig").font(.headline)
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(RoundedRectangle(cornerRadius: 16).fill(Self.pinkDeep))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 28).padding(.bottom, 24)
            }
        }
        .foregroundColor(Self.ink)
        .preferredColorScheme(.light)
    }

    func head(_ eyebrow: String, _ title: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(eyebrow.uppercased()).font(.caption.weight(.bold)).tracking(1.2).foregroundColor(Self.pinkDeep)
            Text(title).font(.system(size: 30, weight: .heavy, design: .rounded))
        }
    }

    func para(_ t: String) -> some View {
        Text(t).font(.body).foregroundColor(Self.inkSoft).fixedSize(horizontal: false, vertical: true)
    }

    func sheet<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) { c() }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 28).padding(.top, 40).padding(.bottom, 12)
        }
    }

    var pageHow: some View {
        sheet {
            head("So geht's", "Ein Druck.\nEin Kuss.")
            VStack(alignment: .leading, spacing: 14) {
                row("1", "Du drückst aufs Herz.")
                row("2", "Bei dir zählt ▲ eins hoch.")
                row("3", "Bei mir kommt er an, mein ▼ zählt mit.")
            }
            para("Dein Handy bringt den Kuss zu mir. Bluetooth an lassen und die K.I.S.S.-App nicht löschen.")
        }
    }

    var pageButton: some View {
        sheet {
            head("Bedienung", "Alles läuft\nübers Herz.")
            VStack(spacing: 10) {
                op("Drücken", "Display aus", "Weckt das Display. Es geht noch nichts raus.")
                op("Kurz drücken", "Display an", "Kuss abschicken.")
                op("Halten", "Kuss wartet", "Ring läuft voll: Kuss abgeholt.")
                op("Halten", "kein Kuss da", "Ring läuft voll, dann rot: Gerät geht aus.")
                op("Drücken", "Gerät aus", "Gerät geht an.")
            }
            para("Kurz = antippen. Halten = gedrückt lassen, bis der Ring voll ist.").font(.footnote)
        }
    }

    var pageIncoming: some View {
        sheet {
            head("Von mir", "Wenn ein\nKuss kommt.")
            para("Auf dem Display erscheint ein Kussgesicht. Die Zahl im Herz zeigt, wie viele auf dich warten. Herz gedrückt halten, bis der Ring voll ist, dann sind sie abgeholt.")
            VStack(alignment: .leading, spacing: 10) {
                legend(Text("▲").foregroundColor(Self.pinkDeep), "von dir verschickt")
                legend(Text("▼").foregroundColor(Self.mintDeep), "bei dir angekommen")
                legend(Circle().stroke(Self.mintDeep, lineWidth: 3).frame(width: 16, height: 16), "Ring außen = Akku")
            }
        }
    }

    var pageEveryday: some View {
        sheet {
            head("Alltag", "Laden &\nmitnehmen.")
            tip("bolt.fill", "Laden", "USB-C-Kabel seitlich einstecken. Beim Laden füllt sich der Ring.")
            tip("heart.slash.fill", "Graues Herz mit Riss?", "Das Handy war zu lange außer Reichweite. Handy in die Nähe legen, Bluetooth an, dann finden sich beide wieder.")
            tip("key.fill", "Unterwegs", "Durch die Öse oben passt ein Schlüsselring.")
        }
    }

    func row(_ n: String, _ t: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(n).font(.system(size: 15, weight: .heavy, design: .rounded)).foregroundColor(.white)
                .frame(width: 28, height: 28).background(Circle().fill(Self.pinkDeep))
            Text(t).font(.system(size: 19, weight: .semibold, design: .rounded))
        }
    }

    func op(_ action: String, _ state: String, _ result: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(action).font(.subheadline.weight(.heavy))
                Spacer()
                Text(state).font(.caption.weight(.semibold)).foregroundColor(Self.inkSoft)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Self.ink.opacity(0.07)))
            }
            Text(result).font(.subheadline).foregroundColor(Self.inkSoft)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.55)))
    }

    func legend<I: View>(_ icon: I, _ t: String) -> some View {
        HStack(spacing: 12) { icon.font(.title3.weight(.bold)).frame(width: 24); Text(t).font(.body.weight(.semibold)) }
    }

    func tip(_ sym: String, _ title: String, _ t: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: sym).font(.title3).foregroundColor(Self.pinkDeep).frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                para(t)
            }
        }
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
    @State var showGuide = false

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
                    Button("Anleitung") { showGuide = true }
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
        .sheet(isPresented: $showGuide) { GuideView { showGuide = false } }
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
