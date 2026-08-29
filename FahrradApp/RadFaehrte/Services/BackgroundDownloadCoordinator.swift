//
//  BackgroundDownloadCoordinator.swift
//  RadFaehrte
//

import Foundation

/// Zielordner (relativ zu `Documents/`) für die von diesem Koordinator verwalteten Downloads -
/// identisch zu den Ordnernamen aus `WayGraphStore`/`RestStopStore`, s. Doc-Kommentar an
/// `BackgroundDownloadCoordinator`.
enum BackgroundDownloadKind: String {
    case wayGraph = "WayGraphs"
    case restStop = "RestStops"
}

/// Zentrale Download-Instanz für alle Wege-Graph-/Rastplatz-Downloads (`WayGraphDownloadManager`,
/// `RestStopDownloadManager`) über eine Hintergrund-`URLSession` statt der bisherigen
/// `URLSession.shared`. Grund: `URLSession.shared` ist eine reine Vordergrund-Session - verlässt die
/// App den Vordergrund (Display gesperrt, App wechselt in den Hintergrund oder wird vom Nutzer
/// beendet) länger als die vom System gewährte kurze Nachlaufzeit (~30 s), killt iOS den laufenden
/// Download komplett; ein erneuter Start ist dann nur manuell von vorn möglich (Nutzer-Meldung
/// 2026-08-28, bei großen Bundesland-/Länder-Downloads besonders störend). Eine `.background(
/// withIdentifier:)`-Session dagegen läuft als eigener System-Task (`nsurlsessiond`) weiter,
/// unabhängig vom App-Prozess - auch nach Sperren des Displays oder vollständigem Beenden der App
/// durch den Nutzer (nicht durch das System selbst, z. B. wegen Speicherdrucks o. Ä. - das killt
/// auch den System-Task).
///
/// Die eigentliche Zieldatei wird direkt hier ermittelt (`Documents/{kind.rawValue}/
/// {regionRawValue}.sqlite`, analog `WayGraphStore`/`RestStopStore.fileURL(for:)`) statt über die
/// jeweilige, generische `Store`-Instanz: Ein Hintergrund-Download kann fertig werden, während die
/// App komplett beendet ist und das System sie nur kurz reaktiviert, um die
/// `URLSessionDelegate`-Events entgegenzunehmen (`AppDelegate.application(_:
/// handleEventsForBackgroundURLSession:completionHandler:)`) - dann existiert keine SwiftUI-View
/// und damit auch keine `WayGraphDownloadManager`/`Store`-Instanz, die die Datei sonst übernehmen
/// würde. Region-Typ und Zielordner werden deshalb als einfache Strings im `taskDescription` des
/// `URLSessionDownloadTask` kodiert (`"\(kind.rawValue)|\(regionRawValue)"`) statt über Swift-
/// Generics, die sich mit einem `URLSessionDelegate` (muss eine `NSObject`-Subklasse sein) nicht
/// vertragen.
///
/// `nonisolated`, damit die `URLSessionDownloadDelegate`-Methoden (feuern auf einer beliebigen
/// Hintergrund-Queue, s. `delegateQueue: nil` unten) nicht durch die MainActor-Standardisolierung
/// des Projekts (`-default-isolation=MainActor`) isoliert werden - sonst Fehler "conformance ...
/// crosses into main actor-isolated code" (analog `WayGraphStore`/`WayGraphCache`). Der Zugriff auf
/// den gemeinsamen State (`progress`, registrierte Callbacks) läuft deshalb wie bei `WayGraphCache`
/// über ein `NSLock` statt über Actor-Isolation.
nonisolated final class BackgroundDownloadCoordinator: NSObject {
    static let shared = BackgroundDownloadCoordinator()

    /// Muss eindeutig und über App-Neustarts hinweg stabil sein - das System nutzt sie, um beim
    /// Reaktivieren der App nach einem im Hintergrund fertiggestellten Download die passende
    /// Session wiederzufinden.
    private static let sessionIdentifier = "com.frankenfeld.RadFaehrte.background-downloads"

    /// Vom `AppDelegate` gesetzt, sobald das System die App zum Verarbeiten von Hintergrund-
    /// Download-Events reaktiviert hat. Muss laut Apple-Dokumentation aufgerufen werden, nachdem
    /// `urlSessionDidFinishEvents(forBackgroundURLSession:)` gefeuert hat - sonst zeigt iOS für
    /// diese App keine weiteren Hintergrund-Download-Events mehr an.
    private var backgroundSessionCompletionHandler: (() -> Void)?

    private let lock = NSLock()
    /// Fortschritt je "kind|rawValue"-Schlüssel - Quelle der Wahrheit, damit ein
    /// `WayGraphDownloadManager`/`RestStopDownloadManager` beim erneuten Erscheinen der
    /// zugehörigen View einen bereits laufenden Hintergrund-Download sofort mit dem aktuellen
    /// Fortschritt weiter anzeigt statt bei 0 % neu zu wirken.
    private var progressByKey: [String: Double] = [:]
    /// Callbacks, solange die zugehörige View sichtbar ist und ihr `WayGraphDownloadManager`/
    /// `RestStopDownloadManager` beobachtet - laufen absichtlich auf dem MainActor (s.
    /// `notify(key:...)`), da sie direkt `@Observable`-Properties dieser Manager setzen.
    private var progressHandlers: [String: @MainActor (Double) -> Void] = [:]
    private var completionHandlers: [String: @MainActor (Result<Void, Error>) -> Void] = [:]

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    private override init() {
        super.init()
    }

    /// Muss früh im App-Start aufgerufen werden (s. `RadFaehrteApp.init`/`AppDelegate`), damit die
    /// Session schon existiert, bevor eventuell wartende Delegate-Events eintreffen.
    func activate() {
        _ = session
    }

    func setBackgroundSessionCompletionHandler(_ handler: @escaping () -> Void) {
        lock.lock()
        backgroundSessionCompletionHandler = handler
        lock.unlock()
        activate()
    }

    private static func key(kind: BackgroundDownloadKind, regionRawValue: String) -> String {
        "\(kind.rawValue)|\(regionRawValue)"
    }

    func currentProgress(kind: BackgroundDownloadKind, regionRawValue: String) -> Double? {
        lock.lock()
        defer { lock.unlock() }
        return progressByKey[Self.key(kind: kind, regionRawValue: regionRawValue)]
    }

    /// Registriert Fortschritts-/Abschluss-Callbacks für eine Region - der Aufrufer (`download(_:)`
    /// bzw. `init` der beiden Download-Manager) muss `startDownload` selbst aufrufen bzw. prüfen,
    /// ob der Download bereits läuft (s. `currentProgress`).
    func observe(
        kind: BackgroundDownloadKind,
        regionRawValue: String,
        onProgress: @escaping @MainActor (Double) -> Void,
        onCompletion: @escaping @MainActor (Result<Void, Error>) -> Void
    ) {
        let key = Self.key(kind: kind, regionRawValue: regionRawValue)
        lock.lock()
        progressHandlers[key] = onProgress
        completionHandlers[key] = onCompletion
        lock.unlock()
    }

    func stopObserving(kind: BackgroundDownloadKind, regionRawValue: String) {
        let key = Self.key(kind: kind, regionRawValue: regionRawValue)
        lock.lock()
        progressHandlers[key] = nil
        completionHandlers[key] = nil
        lock.unlock()
    }

    func startDownload(kind: BackgroundDownloadKind, regionRawValue: String, url: URL) {
        let key = Self.key(kind: kind, regionRawValue: regionRawValue)
        lock.lock()
        let alreadyTracked = progressByKey[key] != nil
        if !alreadyTracked {
            progressByKey[key] = 0
        }
        lock.unlock()
        guard !alreadyTracked else { return }

        session.getAllTasks { [weak self] tasks in
            guard let self else { return }
            if tasks.contains(where: { $0.taskDescription == key && $0.state != .completed }) {
                // Läuft bereits als System-Task (z. B. nach App-Neustart während eines laufenden
                // Hintergrund-Downloads) - keinen zweiten Task für dieselbe Region starten.
                return
            }
            let task = self.session.downloadTask(with: url)
            task.taskDescription = key
            task.resume()
        }
    }

    func cancelDownload(kind: BackgroundDownloadKind, regionRawValue: String) {
        let key = Self.key(kind: kind, regionRawValue: regionRawValue)
        session.getAllTasks { tasks in
            tasks.first { $0.taskDescription == key }?.cancel()
        }
    }

    private func destinationURL(for key: String) -> URL? {
        let parts = key.split(separator: "|", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let directory = documents.appendingPathComponent(String(parts[0]), isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("\(parts[1]).sqlite")
    }

    /// Räumt den Callback-/Fortschritt-State für `key` auf und ruft den passenden, zuvor über
    /// `observe` registrierten Callback auf dem MainActor auf - läuft immer aus den (auf einer
    /// Hintergrund-Queue feuernden) Delegate-Methoden unten heraus.
    private func notify(key: String, result: Result<Void, Error>?) {
        lock.lock()
        progressByKey[key] = nil
        progressHandlers[key] = nil
        let completionHandler = completionHandlers.removeValue(forKey: key)
        lock.unlock()
        guard let result else { return }
        Task { @MainActor in
            completionHandler?(result)
        }
    }
}

extension BackgroundDownloadCoordinator: URLSessionDownloadDelegate {
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let key = downloadTask.taskDescription, let destination = destinationURL(for: key) else { return }
        // Muss synchron in diesem Delegate-Aufruf passieren - das System löscht die temporäre
        // Datei sofort, sobald er zurückkehrt (analog dem Completion-Handler-Kommentar in den
        // bisherigen, mittlerweile ersetzten `URLSession.shared`-basierten Download-Managern).
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: location, to: destination)
            let path = destination.path
            if key.hasPrefix(BackgroundDownloadKind.wayGraph.rawValue + "|") {
                WayGraphCache.shared.invalidate(path: path)
                Task.detached(priority: .background) {
                    _ = WayGraphCache.shared.repository(for: path)
                }
            } else {
                RestStopCache.shared.invalidate(path: path)
                Task.detached(priority: .background) {
                    _ = RestStopCache.shared.repository(for: path)
                }
            }
            notify(key: key, result: .success(()))
        } catch {
            notify(key: key, result: .failure(error))
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let key = downloadTask.taskDescription, totalBytesExpectedToWrite > 0 else { return }
        let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        lock.lock()
        progressByKey[key] = fraction
        let handler = progressHandlers[key]
        lock.unlock()
        guard let handler else { return }
        Task { @MainActor in
            handler(fraction)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, let key = task.taskDescription else { return }
        let wasCancelled = (error as? URLError)?.code == .cancelled
        // Beim selbst ausgelösten Abbruch (`cancelDownload`) keinen Fehler melden - das ist ein
        // vom Nutzer gewollter Zustand, kein Fehler-Alert wert (analog dem bisherigen Verhalten der
        // `URLSession.shared`-basierten Manager).
        notify(key: key, result: wasCancelled ? nil : .failure(error))
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        lock.lock()
        let handler = backgroundSessionCompletionHandler
        backgroundSessionCompletionHandler = nil
        lock.unlock()
        guard let handler else { return }
        Task { @MainActor in
            handler()
        }
    }
}
