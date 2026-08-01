//
//  ActivityView.swift
//  RadFaehrte
//

import SwiftUI

/// Dünner Wrapper um `UIActivityViewController` fürs native Teilen-Sheet (GPX-Export in
/// `ContentView`/`HistoryView`). Die Datei wird synchron vor dem Öffnen erzeugt, daher reicht der
/// direkte Wrapper statt SwiftUIs `ShareLink`/`Transferable`.
struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
