import SwiftUI

@main
struct KISSApp: App {
    @StateObject var ble = BLEManager.shared
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(ble)
                .onAppear { if shot == nil { ble.start() } }
                .preferredColorScheme(.light)
        }
    }
}

// Farben und Schriften wie die gedruckte Broschuere: helles Papier, dunkle Schrift
enum K {
    static let cover = Color(hex: 0xF9C4D6)   // Aussenseite, rosa bedruckt
    static let rose = Color(hex: 0xFFE6EF)
    static let mint = Color(hex: 0xE0F5EC)
    static let peach = Color(hex: 0xFFE9DA)
    static let lilac = Color(hex: 0xEEE7F8)
    static let ink = Color(hex: 0x2B1622)
    static let muted = Color(hex: 0x6B4E5E)
    static let pink = Color(hex: 0xD23C76)
    static let mintDeep = Color(hex: 0x1E9A75)
    static let screen = Color(hex: 0x14101A)  // Display am Geraet
    static let screenPink = Color(hex: 0xFF6A9C)
    static let screenMint = Color(hex: 0x4FD6AE)
    static let card = Color.white.opacity(0.6)
}

enum F {
    static func display(_ s: CGFloat) -> Font { .custom("Bungee-Regular", size: s) }
    static func body(_ s: CGFloat = 17) -> Font { .custom("AtkinsonHyperlegible-Regular", size: s) }
    static func bold(_ s: CGFloat = 17) -> Font { .custom("AtkinsonHyperlegible-Bold", size: s) }
    static func pixel(_ s: CGFloat) -> Font { .custom("PressStart2P-Regular", size: s) }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

/// Fuer Screenshots im Simulator: Startargument `-shot welcome|code|connect|guide1..guide4|home|waiting|settings`
/// zeigt den Bildschirm mit Beispielzahlen, ohne Geraet und ohne Server.
let shot = UserDefaults.standard.string(forKey: "shot")

struct RootView: View {
    @AppStorage("setupDone") var setupDone = false

    var body: some View {
        Group {
            if let s = shot {
                if ["welcome", "code", "connect"].contains(s) {
                    SetupView(step: ["welcome", "code", "connect"].firstIndex(of: s)!)
                } else if s.hasPrefix("guide") {
                    GuideView(page: (Int(s.dropFirst(5)) ?? 1) - 1) {}
                } else if s == "settings" {
                    SettingsView()
                } else {
                    HomeView()
                }
            } else if setupDone {
                HomeView()
            } else {
                SetupView()
            }
        }
        .foregroundColor(K.ink)
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
            ZStack {
                [K.cover, K.rose, K.mint][step].ignoresSafeArea()
                if step == 0 { HeartPattern().ignoresSafeArea() }
                VStack(spacing: 0) {
                    if step > 0 { Dots(count: 2, current: step - 1).padding(.top, 24) }
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
            }
            .animation(.easeInOut(duration: 0.25), value: step)
        }
    }

    var welcome: some View {
        VStack(spacing: 18) {
            DeviceScreen(sent: 94, recv: 97, size: 190)
            Text("K.I.S.S.").font(F.display(44)).foregroundColor(K.pink)
            Text("Ein Knopf. Ein Kuss.").font(F.body(19))
            Text("Wir richten das jetzt zusammen ein.\nDauert eine Minute.")
                .font(F.body(16)).foregroundColor(K.muted).multilineTextAlignment(.center)
            // Jana hat immer Geraet A; B stellt Steven bei Bedarf im Zahnrad um.
            Big("Los geht's") { dev = "a"; step = 1 }.padding(.top, 10)
        }
    }

    var codeEntry: some View {
        VStack(alignment: .leading, spacing: 20) {
            Title(n: 1, "Code\neingeben.")
            Text("Den Code bekommst du von mir. Groß- und Kleinschreibung zählt.")
                .font(F.body()).foregroundColor(K.muted)
            TextField("Code", text: $code)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .font(F.pixel(16))
                .multilineTextAlignment(.center)
                .padding(.vertical, 18)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.white))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(K.ink.opacity(0.12)))
            if let e = error {
                Text(e).font(F.bold(15)).foregroundColor(K.pink)
            }
            Big(checking ? "Prüfe …" : "Prüfen", disabled: code.isEmpty || checking) { verify() }
            Back { step = 0 }
        }
    }

    var connect: some View {
        VStack(alignment: .leading, spacing: 20) {
            Title(n: 2, "Gerät\nverbinden.")
            HStack {
                Spacer()
                ZStack {
                    Circle().fill(ble.connected ? K.mintDeep : Color.white).frame(width: 150, height: 150)
                    if ble.connected {
                        Image(systemName: "checkmark").font(.system(size: 60, weight: .bold)).foregroundColor(.white)
                    } else {
                        Heart(size: 64)
                    }
                }
                Spacer()
            }
            .padding(.vertical, 8)
            Text(ble.connected ? "Verbunden. Ab jetzt bringt dein Handy die Küsse rüber." : "Drück einmal auf das Herz am Gerät. Das iPhone findet es dann von selbst.")
                .font(F.body()).foregroundColor(K.muted)
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

// MARK: Startseite -- zeigt dasselbe wie das Display am Geraet

struct HomeView: View {
    @EnvironmentObject var ble: BLEManager
    @State var showSettings = false
    @State var showGuide = false

    var demo: Bool { shot != nil }
    var sent: Int { demo ? 94 : ble.sent }
    var recv: Int { demo ? 97 : ble.recv }
    var waiting: Int { shot == "waiting" ? 2 : (demo ? 0 : ble.wartend) }
    var connected: Bool { demo ? false : ble.connected }

    var body: some View {
        ZStack {
            K.rose.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    Chip(connected: connected)
                    Spacer()
                    IconButton(symbol: "questionmark") { showGuide = true }
                    IconButton(symbol: "gearshape.fill") { showSettings = true }
                }
                .padding(.top, 12)

                Spacer()
                Text("K.I.S.S.").font(F.display(30)).foregroundColor(K.pink)
                DeviceScreen(sent: sent, recv: recv, size: 250).padding(.top, 18)
                HStack(spacing: 18) {
                    Legend(mark: "▲", color: K.pink, text: "von dir verschickt")
                    Legend(mark: "▼", color: K.mintDeep, text: "bei dir angekommen")
                }
                .padding(.top, 18)
                Spacer()

                if waiting > 0 {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(waiting == 1 ? "1 Kuss wartet." : "\(waiting) Küsse warten.").font(F.display(22))
                        Text(waiting == 1 ? "Halt am Gerät das Herz gedrückt, bis der Ring voll ist." : "Halt am Gerät das Herz gedrückt, bis der Ring voll ist. Dann sind alle abgeholt.")
                            .font(F.body(15))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background(RoundedRectangle(cornerRadius: 18).fill(K.pink))
                    .foregroundColor(.white)
                    .padding(.bottom, 24)
                } else {
                    Text("Ein Knopf zwischen uns.").font(F.body(15)).foregroundColor(K.muted).padding(.bottom, 28)
                }
            }
            .padding(.horizontal, 24)
        }
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

    var bg: Color { [K.rose, K.mint, K.peach, K.lilac][page] }

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

                Dots(count: 4, current: page).padding(.bottom, 18)
                Big(page < 3 ? "Weiter" : "Fertig") {
                    if page < 3 { withAnimation { page += 1 } } else { done() }
                }
                .padding(.horizontal, 28).padding(.bottom, 24)
            }
        }
        .foregroundColor(K.ink)
    }

    func head(_ eyebrow: String, _ title: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(eyebrow)
            Text(title).font(F.display(30)).lineSpacing(2)
        }
    }

    func para(_ t: String, size: CGFloat = 17) -> some View {
        Text(t).font(F.body(size)).foregroundColor(K.muted).fixedSize(horizontal: false, vertical: true)
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
            para("Kurz = antippen. Halten = gedrückt lassen, bis der Ring voll ist.", size: 14)
        }
    }

    var pageIncoming: some View {
        sheet {
            head("Von mir", "Wenn ein\nKuss kommt.")
            para("Auf dem Display erscheint ein Kussgesicht. Die Zahl im Herz zeigt, wie viele auf dich warten. Herz gedrückt halten, bis der Ring voll ist, dann sind sie abgeholt.")
            VStack(alignment: .leading, spacing: 12) {
                Legend(mark: "▲", color: K.pink, text: "von dir verschickt", size: 17)
                Legend(mark: "▼", color: K.mintDeep, text: "bei dir angekommen", size: 17)
                HStack(spacing: 10) {
                    Circle().stroke(K.mintDeep, lineWidth: 3).frame(width: 16, height: 16)
                    Text("Ring außen = Akku").font(F.bold(17))
                }
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
            Text(n).font(F.bold(15)).foregroundColor(.white)
                .frame(width: 28, height: 28).background(Circle().fill(K.pink))
            Text(t).font(F.bold(19))
        }
    }

    func op(_ action: String, _ state: String, _ result: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(action).font(F.bold(16))
                Spacer()
                Text(state).font(F.bold(12)).foregroundColor(K.muted)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(K.ink.opacity(0.07)))
            }
            Text(result).font(F.body(15)).foregroundColor(K.muted)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(K.card))
    }

    func tip(_ sym: String, _ title: String, _ t: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: sym).font(.title3).foregroundColor(K.pink).frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(F.bold(18))
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

    var demo: Bool { shot != nil }
    var logLines: [String] { demo ? ["09:41:02 Status 94 / 97", "09:41:00 verbunden"] : ble.log }

    var body: some View {
        ZStack {
            K.lilac.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 8) {
                            Eyebrow("Einstellungen")
                            Text("Unter der\nHaube.").font(F.display(30))
                        }
                        Spacer()
                        Button("Fertig") { dismiss() }.font(F.bold(17)).foregroundColor(K.pink)
                    }

                    Panel("Gerät") {
                        HStack(spacing: 0) {
                            ForEach(["a", "b"], id: \.self) { d in
                                Button { dev = d } label: {
                                    Text("Gerät \(d.uppercased())").font(F.bold(15))
                                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                                        .background(RoundedRectangle(cornerRadius: 10).fill(dev == d ? K.pink : Color.clear))
                                        .foregroundColor(dev == d ? .white : K.ink)
                                }
                            }
                        }
                        .padding(4)
                        .background(RoundedRectangle(cornerRadius: 13).fill(K.ink.opacity(0.06)))
                        CodeField(label: "Code A", text: $tokenA)
                        CodeField(label: "Code B", text: $tokenB)
                    }

                    Panel("Status") {
                        HStack {
                            Text("Gerät").font(F.body())
                            Spacer()
                            Chip(connected: demo ? false : ble.connected)
                        }
                        HStack {
                            Legend(mark: "▲", color: K.pink, text: "\(demo ? 94 : ble.sent) verschickt", size: 16)
                            Spacer()
                            Legend(mark: "▼", color: K.mintDeep, text: "\(demo ? 97 : ble.recv) angekommen", size: 16)
                        }
                        // Seit Protokoll v2 ist das Geraet die meiste Zeit bewusst
                        // getrennt, damit sein Funkchip schlafen kann.
                        Text(demo ? "Wartet auf das Gerät" : ble.status).font(F.body(14)).foregroundColor(K.muted)
                    }

                    Panel("Aktionen") {
                        ActionRow("Anleitung", symbol: "book.fill") { showGuide = true }
                        ActionRow("Neu verbinden", symbol: "antenna.radiowaves.left.and.right") { ble.start() }
                        ActionRow("Status abrufen", symbol: "arrow.clockwise") { ble.pollState() }
                        ActionRow("Einrichtung neu starten", symbol: "arrow.uturn.backward") { setupDone = false; dismiss() }
                    }

                    Panel("Log") {
                        ForEach(logLines, id: \.self) { line in
                            Text(line).font(.system(size: 12, design: .monospaced)).foregroundColor(K.muted)
                        }
                    }
                }
                .padding(.horizontal, 24).padding(.vertical, 28)
            }
        }
        .foregroundColor(K.ink)
        .sheet(isPresented: $showGuide) { GuideView { showGuide = false } }
    }
}

// MARK: Bausteine

/// Das runde Display wie am Geraet: Akku-Ring, ▲ gesendet, ▼ bekommen in Pixelschrift
struct DeviceScreen: View {
    let sent: Int, recv: Int, size: CGFloat
    var body: some View {
        ZStack {
            Circle().fill(K.screen)
            Circle().trim(from: 0.04, to: 0.80)
                .stroke(K.screenMint, style: StrokeStyle(lineWidth: size * 0.045, lineCap: .round))
                .rotationEffect(.degrees(-90)).padding(size * 0.07)
            VStack(spacing: size * 0.08) {
                HStack(spacing: size * 0.04) {
                    Text("▲").font(.system(size: size * 0.09)); Text("\(sent)").font(F.pixel(size * 0.15))
                }.foregroundColor(K.screenPink)
                HStack(spacing: size * 0.04) {
                    Text("▼").font(.system(size: size * 0.09)); Text("\(recv)").font(F.pixel(size * 0.15))
                }.foregroundColor(K.screenMint)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: K.pink.opacity(0.25), radius: size / 10, y: size / 25)
    }
}

/// Herzmuster wie auf der bedruckten Aussenseite
struct HeartPattern: View {
    var body: some View {
        GeometryReader { g in
            let step: CGFloat = 64
            ForEach(0..<Int(g.size.height / step) + 2, id: \.self) { r in
                ForEach(0..<Int(g.size.width / step) + 2, id: \.self) { c in
                    Image(systemName: "heart.fill")
                        .font(.system(size: (r + c) % 2 == 0 ? 18 : 10))
                        .foregroundColor(K.pink.opacity(0.10))
                        .position(x: CGFloat(c) * step + (r % 2 == 0 ? 16 : 48), y: CGFloat(r) * step + 20)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

struct Heart: View {
    let size: CGFloat
    var body: some View {
        Image(systemName: "heart.fill").font(.system(size: size)).foregroundColor(K.pink)
    }
}

struct Eyebrow: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased()).font(F.bold(12)).tracking(2).foregroundColor(K.pink)
    }
}

struct Legend: View {
    let mark: String, color: Color, text: String
    var size: CGFloat = 14
    var body: some View {
        HStack(spacing: 6) {
            Text(mark).font(.system(size: size * 0.8, weight: .bold)).foregroundColor(color)
            Text(text).font(F.bold(size)).foregroundColor(K.ink)
        }
    }
}

struct Chip: View {
    let connected: Bool
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(connected ? K.mintDeep : K.muted.opacity(0.5)).frame(width: 8, height: 8)
            Text(connected ? "verbunden" : "Gerät schläft").font(F.bold(14))
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Capsule().fill(K.card))
    }
}

struct IconButton: View {
    let symbol: String, action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 16, weight: .bold)).foregroundColor(K.ink)
                .frame(width: 38, height: 38).background(Circle().fill(K.card))
        }
    }
}

struct Panel<C: View>: View {
    let title: String, content: C
    init(_ title: String, @ViewBuilder _ content: () -> C) { self.title = title; self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(title)
            VStack(alignment: .leading, spacing: 12) { content }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 16).fill(K.card))
        }
    }
}

struct CodeField: View {
    let label: String
    @Binding var text: String
    var body: some View {
        HStack {
            Text(label).font(F.body(15)).foregroundColor(K.muted)
            SecureField("nicht gesetzt", text: $text).font(F.pixel(12)).multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 4)
    }
}

struct ActionRow: View {
    let title: String, symbol: String, action: () -> Void
    init(_ title: String, symbol: String, action: @escaping () -> Void) {
        self.title = title; self.symbol = symbol; self.action = action
    }
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundColor(K.pink).frame(width: 22)
                Text(title).font(F.bold(16)).foregroundColor(K.ink)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundColor(K.muted.opacity(0.6))
            }
            .padding(.vertical, 4)
        }
    }
}

struct Dots: View {
    let count: Int, current: Int
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { i in
                Capsule().fill(i == current ? K.pink : K.ink.opacity(0.15))
                    .frame(width: i == current ? 22 : 8, height: 8)
            }
        }
    }
}

struct Title: View {
    let n: Int, text: String
    init(n: Int, _ text: String) { self.n = n; self.text = text }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow("Schritt \(n) von 2")
            Text(text).font(F.display(32)).lineSpacing(2)
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
            Text(title).font(F.bold(18)).frame(maxWidth: .infinity).padding(.vertical, 16)
                .background(RoundedRectangle(cornerRadius: 14).fill(disabled ? K.ink.opacity(0.08) : K.pink))
                .foregroundColor(disabled ? K.muted : .white)
        }
        .disabled(disabled)
    }
}

struct Back: View {
    let action: () -> Void
    var body: some View {
        HStack {
            Spacer()
            Button("Zurück", action: action).font(F.bold(15)).foregroundColor(K.muted)
            Spacer()
        }
    }
}
