//
//  AboutView.swift
//  RadFaehrte
//

import SwiftUI

/// Versionsnummer + Kontakt-E-Mail, wie in den Einstellungen fast jeder App üblich. Liest Version
/// und Build direkt aus dem Bundle (`MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` im
/// Xcode-Projekt), damit hier bei einer neuen Version nichts von Hand nachgepflegt werden muss.
struct AboutView: View {
    private let contactEmail = "frankenfeld@icloud.com"

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"
    }

    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "–"
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 12) {
                    Image("LaunchIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 80, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                    Text("RadFährte")
                        .font(.title3.bold())
                    Text("Version \(version) (\(build))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .listRowBackground(Color.clear)
            }

            Section {
                if let url = URL(string: "mailto:\(contactEmail)") {
                    Link(destination: url) {
                        HStack {
                            Text("Kontakt")
                            Spacer()
                            Text(contactEmail)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } footer: {
                Text("Fragen, Ideen oder ein Problem gefunden? Einfach melden.")
            }
        }
        .navigationTitle("Info")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        AboutView()
    }
}
