import Foundation
import CoreBluetooth

let SVC    = CBUUID(string: "4b495353-0001-1000-8000-00805f9b34fb")
let C_KISS = CBUUID(string: "4b495353-0002-1000-8000-00805f9b34fb")
let C_IN   = CBUUID(string: "4b495353-0003-1000-8000-00805f9b34fb")
let C_HB   = CBUUID(string: "4b495353-0004-1000-8000-00805f9b34fb")
let C_ACK  = CBUUID(string: "4b495353-0005-1000-8000-00805f9b34fb")
let C_RST  = CBUUID(string: "4b495353-0006-1000-8000-00805f9b34fb")
let SUBSCRIBE = [C_KISS, C_ACK, C_RST, C_HB]

/// Protokoll v2 (09/2026): Das Geraet ist die meiste Zeit NICHT verbunden.
/// Es wirbt alle 60 s kurz und sofort bei Knopfdruck, und trennt ~3 s nach dem
/// letzten char_in-Schreibzugriff wieder. Damit kann der Funkchip schlafen.
///
/// Fuer diese App heisst das:
///  - Eine Trennung ist der NORMALFALL, kein Fehler. Sofort wieder verbinden,
///    ohne Backoff. Ein ausstehendes connect() hat kein Timeout und wird von
///    iOS auch im Hintergrund eingeloest, sobald das Geraet wirbt.
///  - Nach dem Verbinden gilt eine feste Reihenfolge, siehe completeHandshake().
///  - Entprellt wird nach Sequenzwert, nicht nach Zeit: das Geraet schickt
///    aufgelaufene Kuesse im Abstand von 150 ms, eine Zeitsperre verschluckt sie.
final class BLEManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    static let shared = BLEManager()

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var inChar: CBCharacteristic?

    /// Letzter Sequenzwert je Charakteristik. Wird bei JEDER neuen Verbindung
    /// geleert: das Geraet beginnt seine Zaehlung womoeglich von vorn, und ein
    /// faelschlich verschluckter Kuss waere schlimmer als ein doppelter.
    private var lastSeq: [CBUUID: UInt8] = [:]

    /// Zaehlt die noch ausstehenden CCCD-Bestaetigungen. Erst wenn alle da sind,
    /// ist das Geraet bereit, aufgelaufene Befehle zu schicken.
    private var pendingSubscriptions = 0
    private var handshakeDone = false
    private var handshakeGuard: DispatchWorkItem?

    /// Mehrere Befehle kurz hintereinander sollen EINEN Abgleich ausloesen,
    /// nicht drei.
    private var pollDebounce: DispatchWorkItem?

    @Published var connected = false
    @Published var status = "Start…"
    @Published var sent = 0
    @Published var recv = 0
    @Published var pending = false
    /// Anzahl wartender Kuesse. Der Relay liefert sie seit 09/2026 als
    /// kuss_wartend; frueher gab es nur das Ja/Nein in kuss_pending.
    @Published var wartend = 0
    @Published var log: [String] = []

    let base = "https://kuss.drewers.dev"
    var device: String { UserDefaults.standard.string(forKey: "dev") ?? "a" }
    var token: String { UserDefaults.standard.string(forKey: "token_\(device)") ?? "" }

    private let knownPeripheralKey = "knownPeripheral"

    func start() {
        if central == nil {
            central = CBCentralManager(delegate: self, queue: nil,
                options: [CBCentralManagerOptionRestoreIdentifierKey: "kiss-central"])
        } else {
            connectOrScan()
        }
    }

    private func addLog(_ s: String) {
        DispatchQueue.main.async {
            self.log.insert(s, at: 0)
            if self.log.count > 60 { self.log.removeLast() }
        }
    }
    private func setStatus(_ s: String) { DispatchQueue.main.async { self.status = s } }

    // MARK: Central

    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        if c.state == .poweredOn { connectOrScan() } else { setStatus("Bluetooth aus?") }
    }

    func centralManager(_ c: CBCentralManager, willRestoreState dict: [String: Any]) {
        if let ps = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral], let p = ps.first {
            adopt(p)
            addLog("wiederhergestellt")
        }
    }

    /// Ist das Geraet bekannt, wird NICHT gescannt, sondern ein ausstehendes
    /// connect() gestellt. Das kostet nichts, hat kein Timeout und funktioniert
    /// im Hintergrund — anders als ein Scan, den iOS dort stark drosselt.
    private func connectOrScan() {
        guard central?.state == .poweredOn else { return }

        if peripheral == nil,
           let s = UserDefaults.standard.string(forKey: knownPeripheralKey),
           let uuid = UUID(uuidString: s),
           let p = central.retrievePeripherals(withIdentifiers: [uuid]).first {
            adopt(p)
        }

        if let p = peripheral {
            if p.state == .connected { return }
            setStatus("wartet auf Gerät")
            central.connect(p, options: nil)
            return
        }

        setStatus("suche…")
        central.scanForPeripherals(withServices: [SVC], options: nil)
    }

    private func adopt(_ p: CBPeripheral) {
        peripheral = p
        p.delegate = self
        UserDefaults.standard.set(p.identifier.uuidString, forKey: knownPeripheralKey)
        if p.state != .connected { central.connect(p, options: nil) }
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        central.stopScan()
        addLog("gefunden: \(p.name ?? "KISS")")
        adopt(p)
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        DispatchQueue.main.async { self.connected = true }
        setStatus("verbunden")
        addLog("verbunden")

        lastSeq.removeAll()
        inChar = nil
        handshakeDone = false
        pendingSubscriptions = 0

        // Notnagel: bleibt eine CCCD-Bestaetigung aus, wuerde char_in nie
        // geschrieben und das Geraet trennte nach 10 s ohne Handschlag.
        handshakeGuard?.cancel()
        let guardItem = DispatchWorkItem { [weak self] in
            guard let self, !self.handshakeDone else { return }
            self.addLog("Handschlag erzwungen")
            self.completeHandshake()
        }
        handshakeGuard = guardItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: guardItem)

        p.discoverServices([SVC])
    }

    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        DispatchQueue.main.async { self.connected = false }
        inChar = nil
        handshakeGuard?.cancel()
        // Kein Fehler: das Geraet legt sich schlafen. Sofort wieder anstellen.
        setStatus("wartet auf Gerät")
        addLog("Sitzung beendet")
        central.connect(p, options: nil)
    }

    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        addLog("Verbindung fehlgeschlagen – neuer Versuch")
        central.connect(p, options: nil)
    }

    // MARK: Peripheral

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        guard let s = p.services?.first(where: { $0.uuid == SVC }) else { return }
        p.discoverCharacteristics(nil, for: s)
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        var toSubscribe: [CBCharacteristic] = []
        for ch in s.characteristics ?? [] {
            if ch.uuid == C_IN { inChar = ch }
            if SUBSCRIBE.contains(ch.uuid) { toSubscribe.append(ch) }
        }
        pendingSubscriptions = toSubscribe.count
        // Erst abonnieren, DANN char_in schreiben. Der erste Schreibzugriff ist
        // das Signal "App bereit"; kaeme er vor den Abonnements, schickte das
        // Geraet aufgelaufene Befehle ins Leere.
        for ch in toSubscribe { p.setNotifyValue(true, for: ch) }
        if toSubscribe.isEmpty { completeHandshake() }
    }

    func peripheral(_ p: CBPeripheral, didUpdateNotificationStateFor ch: CBCharacteristic, error: Error?) {
        if error != nil { addLog("Abo fehlgeschlagen: \(ch.uuid)") }
        pendingSubscriptions = max(0, pendingSubscriptions - 1)
        if pendingSubscriptions == 0 { completeHandshake() }
    }

    /// Abonnements stehen. Sofort mit den zuletzt bekannten Werten schreiben —
    /// das haelt die 10-Sekunden-Frist auch dann ein, wenn der Server lahmt —
    /// und danach den frischen Stand nachreichen.
    private func completeHandshake() {
        guard !handshakeDone else { return }
        handshakeDone = true
        handshakeGuard?.cancel()
        writeIn(wartend, sent, recv)
        pollState()
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        let cmd: String
        switch ch.uuid {
        case C_KISS: cmd = "kiss"
        case C_ACK:  cmd = "ack"
        case C_RST:  cmd = "reset"
        case C_HB:   schedulePoll(); return   // seit v2 stumm, schadet aber nicht
        default: return
        }

        // Entprellung nach WERT, nicht nach Zeit. Das Geraet schickt aufgelaufene
        // Kuesse im Abstand von 150 ms, jeden mit neuem Sequenzwert. Die frühere
        // Zeitsperre von 1,2 s hat genau die verschluckt.
        if let seq = ch.value?.last {
            if lastSeq[ch.uuid] == seq { return }
            lastSeq[ch.uuid] = seq
        }

        addLog("⟵ \(cmd)")
        switch cmd {
        case "kiss":  post("/kiss")
        case "ack":   post("/acknowledge")
        case "reset": post("/reset")
        default: break
        }
        schedulePoll()
    }

    /// Fasst mehrere Befehle einer Salve zu einem Abgleich zusammen.
    private func schedulePoll() {
        pollDebounce?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.pollState() }
        pollDebounce = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: item)
    }

    // MARK: HTTP

    private func post(_ path: String) {
        guard !token.isEmpty, let url = URL(string: base + path) else { return }
        var r = URLRequest(url: url)
        r.httpMethod = "POST"
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: r) { _, resp, _ in
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            self.addLog((200...299).contains(code) ? "✓ \(path)" : "✗ \(code) \(path)")
        }.resume()
    }

    func pollState() {
        guard !token.isEmpty, let url = URL(string: base + "/state") else { return }
        var r = URLRequest(url: url)
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: r) { data, _, _ in
            guard let data = data,
                  let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            // Rueckfall auf den alten Boolean, falls die App vor dem Server
            // ausgerollt wird: dann ist "es wartet etwas" = 1.
            let w = (j["kuss_wartend"] as? Int)
                ?? (((j["kuss_pending"] as? Bool) == true) ? 1 : 0)
            let s = (j["sent_count"] as? Int) ?? 0
            let rc = (j["received_from_count"] as? Int) ?? 0
            DispatchQueue.main.async {
                self.pending = w > 0
                self.wartend = w
                self.sent = s
                self.recv = rc
            }
            self.writeIn(w, s, rc)
        }.resume()
    }

    /// Erstes Feld ist seit 09/2026 eine ANZAHL, kein Ja/Nein mehr. Das
    /// Drahtformat "a,b,c" bleibt; alte Firmware prueft auf != 0 und sieht
    /// eine 3 genauso als wahr an wie eine 1.
    ///
    /// Jeder Schreibzugriff verlaengert die Sitzung um ~3 s. Die App trennt nie
    /// von sich aus — das entscheidet das Geraet.
    private func writeIn(_ p: Int, _ s: Int, _ r: Int) {
        guard let ch = inChar, let per = peripheral, per.state == .connected else { return }
        let str = "\(p),\(s),\(r)"
        if let d = str.data(using: .utf8) {
            per.writeValue(d, for: ch, type: .withResponse)
        }
    }
}
