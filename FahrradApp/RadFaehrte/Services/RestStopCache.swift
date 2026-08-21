//
//  RestStopCache.swift
//  RadFaehrte
//

import Foundation

/// Hält einmal geladene `RestStopRepository`-Instanzen im Speicher, geschlüsselt nach Dateipfad -
/// direktes Pendant zu `WayGraphCache`, verhindert wiederholtes Öffnen derselben Datei bei jeder
/// Kartenbewegung.
nonisolated final class RestStopCache {
    static let shared = RestStopCache()

    private let lock = NSLock()
    private var repositories: [String: RestStopRepository] = [:]

    private init() {}

    func repository(for path: String) -> RestStopRepository? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = repositories[path] {
            return cached
        }
        guard let loaded = RestStopRepository(path: path) else { return nil }
        repositories[path] = loaded
        return loaded
    }

    /// Entfernt eine gecachte Repository, z. B. nach dem Löschen der zugrundeliegenden Datei in
    /// den Einstellungen - sonst würde die Karte nach einem erneuten Download unbemerkt weiter mit
    /// dem alten, im Speicher gehaltenen Stand rechnen.
    func invalidate(path: String) {
        lock.lock()
        defer { lock.unlock() }
        repositories[path] = nil
    }
}
