import Foundation
import CoreBluetooth

let SVC    = CBUUID(string: "4b495353-0001-1000-8000-00805f9b34fb")
let C_KISS = CBUUID(string: "4b495353-0002-1000-8000-00805f9b34fb")
let C_IN   = CBUUID(string: "4b495353-0003-1000-8000-00805f9b34fb")
let C_HB   = CBUUID(string: "4b495353-0004-1000-8000-00805f9b34fb")
let C_ACK  = CBUUID(string: "4b495353-0005-1000-8000-00805f9b34fb")
let C_RST  = CBUUID(string: "4b495353-0006-1000-8000-00805f9b34fb")
let SUBSCRIBE = [C_KISS, C_ACK, C_RST, C_HB]

final class BLEManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    static let shared = BLEManager()

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var inChar: CBCharacteristic?
    private var lastCmd = ""
    private var lastCmdAt = Date.distantPast

    @Published var connected = false
    @Published var status = "Start…"
    @Published var sent = 0
    @Published var recv = 0
    @Published var pending = false
    @Published var log: [String] = []

    let base = "https://kuss.drewers.dev"
    var device: String { UserDefaults.standard.string(forKey: "dev") ?? "a" }
    var token: String { UserDefaults.standard.string(forKey: "token_\(device)") ?? "" }

    func start() {
        if central == nil {
            central = CBCentralManager(delegate: self, queue: nil,
                options: [CBCentralManagerOptionRestoreIdentifierKey: "kiss-central"])
        } else {
            scan()
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
        if c.state == .poweredOn { scan() } else { setStatus("Bluetooth aus?") }
    }

    func centralManager(_ c: CBCentralManager, willRestoreState dict: [String: Any]) {
        if let ps = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral], let p = ps.first {
            peripheral = p
            p.delegate = self
            addLog("restore")
        }
    }

    private func scan() {
        guard central?.state == .poweredOn else { return }
        if let p = peripheral, p.state == .connected { return }
        setStatus("suche…")
        central.scanForPeripherals(withServices: [SVC], options: nil)
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        central.stopScan()
        peripheral = p
        p.delegate = self
        addLog("gefunden: \(p.name ?? "KISS")")
        central.connect(p, options: nil)
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        DispatchQueue.main.async { self.connected = true }
        setStatus("verbunden")
        addLog("verbunden")
        p.discoverServices([SVC])
    }

    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        DispatchQueue.main.async { self.connected = false }
        addLog("getrennt – reconnect")
        central.connect(p, options: nil)
    }

    // MARK: Peripheral
    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        guard let s = p.services?.first(where: { $0.uuid == SVC }) else { return }
        p.discoverCharacteristics(nil, for: s)
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        for ch in s.characteristics ?? [] {
            if ch.uuid == C_IN { inChar = ch }
            if SUBSCRIBE.contains(ch.uuid) { p.setNotifyValue(true, for: ch) }
        }
        pollState()
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        let cmd: String
        switch ch.uuid {
        case C_KISS: cmd = "kiss"
        case C_ACK:  cmd = "ack"
        case C_RST:  cmd = "reset"
        case C_HB:   pollState(); return
        default: return
        }
        if cmd == lastCmd && Date().timeIntervalSince(lastCmdAt) < 1.2 { return }
        lastCmd = cmd; lastCmdAt = Date()
        addLog("⟵ \(cmd)")
        switch cmd {
        case "kiss":  post("/kiss")
        case "ack":   post("/acknowledge")
        case "reset": post("/reset")
        default: break
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.pollState() }
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
            let p = (j["kuss_pending"] as? Bool) ?? false
            let s = (j["sent_count"] as? Int) ?? 0
            let rc = (j["received_from_count"] as? Int) ?? 0
            DispatchQueue.main.async { self.pending = p; self.sent = s; self.recv = rc }
            self.writeIn(p ? 1 : 0, s, rc)
        }.resume()
    }

    private func writeIn(_ p: Int, _ s: Int, _ r: Int) {
        guard let ch = inChar, let per = peripheral, per.state == .connected else { return }
        let str = "\(p),\(s),\(r)"
        if let d = str.data(using: .utf8) {
            per.writeValue(d, for: ch, type: .withResponse)
        }
    }
}
