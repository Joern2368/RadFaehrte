//
//  WayGraphCache.swift
//  RadFaehrte
//

import Foundation

/// Hält einmal geladene `WayGraphRepository`-Instanzen im Speicher, geschlüsselt nach Dateipfad.
///
/// Ohne diesen Cache lud `ContentView.offlineDirectRoutes` bei **jeder** Berechnung der "Direkten
/// Fahrrad-Route" (und bei jeder automatischen Neuberechnung während der Navigation, s.
/// `rerouteDirectRoute`) den kompletten Wege-Graphen neu von der Festplatte - bei kleinen
/// Bundesländern (Bremen, wenige MB) kaum spürbar, bei einem ganzen Land wie den Niederlanden
/// (466 MB, 9,6 Mio. Knoten) aber mehrere Sekunden pro Aufruf, live in Rotterdam als spürbar lange
/// Wartezeit bemerkt (2026-07-26). `nonisolated` mit eigenem Lock (analog `WayGraphStore`/
/// `RouteRepository`), damit der Zugriff aus `Task.detached`-Kontexten heraus sicher ist, ohne über
/// den MainActor zu müssen.
nonisolated final class WayGraphCache {
    static let shared = WayGraphCache()

    private let lock = NSLock()
    private var repositories: [String: WayGraphRepository] = [:]

    private init() {}

    /// Liefert die gecachte `WayGraphRepository` für `path`, oder lädt und cached sie beim ersten
    /// Zugriff. `nil`, wenn die Datei nicht gelesen werden kann.
    func repository(for path: String) -> WayGraphRepository? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = repositories[path] {
            return cached
        }
        guard let loaded = WayGraphRepository(path: path) else { return nil }
        repositories[path] = loaded
        return loaded
    }

    /// Entfernt einen gecachten Graphen, z. B. wenn die zugrundeliegende Datei gelöscht oder durch
    /// einen erneuten Download ersetzt wurde (sonst würde die App nach einem Re-Download
    /// unbemerkt weiter mit dem alten, im Speicher gehaltenen Stand rechnen).
    func invalidate(path: String) {
        lock.lock()
        defer { lock.unlock() }
        repositories[path] = nil
    }
}
