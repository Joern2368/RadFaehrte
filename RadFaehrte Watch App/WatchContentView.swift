//
//  WatchContentView.swift
//  RadFaehrte Watch App
//

import SwiftUI

struct WatchContentView: View {
    @StateObject private var session = WatchSessionManager.shared

    var body: some View {
        VStack(spacing: 6) {
            if session.state.isNavigating {
                Image(systemName: instructionIcon)
                    .font(.system(size: 32, weight: .bold))
                Text(session.state.instructionText)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                Text(session.state.distanceText)
                    .font(.title3.bold())
                    .foregroundStyle(.orange)
                if let routeName = session.state.routeName {
                    Text(routeName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                Image(systemName: "bicycle")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
                Text("Keine Navigation aktiv")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
    }

    private var instructionIcon: String {
        switch session.state.direction {
        case .straight: return "arrow.up"
        case .left: return "arrow.turn.up.left"
        case .right: return "arrow.turn.up.right"
        }
    }
}

#Preview {
    WatchContentView()
}
