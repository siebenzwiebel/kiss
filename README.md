# K.I.S.S. — iOS

Native iOS-Brücke für den [K.I.S.S.](https://git.drewers.dev/Steven/kiss) Kuss-Transmitter.
Hält per CoreBluetooth die Verbindung zum Gerät (auch im Hintergrund, via
`bluetooth-central` + State-Restoration + BLE-Heartbeat) und relayt die Events
über `kuss.drewers.dev`.

## Build
GitHub Actions baut bei jedem Push auf `main` eine **unsignierte `.ipa`**
(macOS-Runner, XcodeGen). Artefakt: Actions-Run → `KISS-unsigned-ipa`.

Installation auf dem iPhone via **AltStore** (signiert mit eigener Apple-ID).

## Tokens
Werden in der App eingegeben (Gerät A/B + zugehöriges Token), gespeichert lokal.
Keine Secrets im Repo.
