//
//  SplashView.swift
//  RadFaehrte
//

import SwiftUI

/// Bildet den System-Launch-Screen (`LaunchScreen.storyboard`) 1:1 nach, damit der Übergang
/// nahtlos wirkt. Der System-Launch-Screen selbst verschwindet, sobald die App startbereit ist
/// (von Apple nicht künstlich verlängerbar) - diese Ansicht hält das gleiche Bild danach noch
/// kurz sichtbar, siehe `RootTabView`.
struct SplashView: View {
    var body: some View {
        Color(red: 0.10980392156862745, green: 0.29019607843137257, blue: 0.3411764705882353)
            .ignoresSafeArea()
            .overlay {
                Image("LaunchIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 220, height: 220)
            }
    }
}

#Preview {
    SplashView()
}
