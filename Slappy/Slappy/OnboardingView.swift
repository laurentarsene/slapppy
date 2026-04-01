//
//  OnboardingView.swift
//  Slappy
//
//  Created by Arsène Laurent on 30/03/2026.
//

import SwiftUI
import Combine

struct OnboardingView: View {
    @Environment(TrackpadReader.self) private var trackpad

    let onComplete: () -> Void

    private var allGranted: Bool {
        trackpad.isInputMonitoringGranted && trackpad.isAccessibilityGranted
    }

    var body: some View {
        VStack(spacing: 24) {

            // ── Header ────────────────────────────────────────────────
            VStack(spacing: 10) {
                Image(systemName: "hand.tap.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Color.accentColor)
                Text("Bienvenue dans Slapppy")
                    .font(.headline)
                Text("Deux permissions sont nécessaires\npour détecter les taps et gestes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 4)

            // ── Permissions ───────────────────────────────────────────
            VStack(spacing: 10) {
                permissionRow(
                    icon: "keyboard.badge.eye",
                    title: "Input Monitoring",
                    subtitle: "Lit les événements trackpad en arrière-plan",
                    granted: trackpad.isInputMonitoringGranted,
                    action: { trackpad.requestInputMonitoring() }
                )
                permissionRow(
                    icon: "figure.arms.open",
                    title: "Accessibilité",
                    subtitle: "Permet d'envoyer des touches virtuelles",
                    granted: trackpad.isAccessibilityGranted,
                    action: { trackpad.requestAccessibility() }
                )
            }

            // ── CTA ───────────────────────────────────────────────────
            VStack(spacing: 10) {
                Button {
                    onComplete()
                } label: {
                    Text(allGranted ? "Commencer →" : "En attente des permissions…")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!allGranted)

                Button("Passer pour l'instant") { onComplete() }
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .buttonStyle(.plain)
            }
        }
        .padding(24)
        .frame(width: 320)
        // Poll permissions every second while the user grants them
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            trackpad.refreshPermissions()
        }
    }

    private func permissionRow(icon: String, title: String, subtitle: String,
                                granted: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(granted ? Color.green.opacity(0.12) : Color.accentColor.opacity(0.10))
                    .frame(width: 36, height: 36)
                Image(systemName: granted ? "checkmark.circle.fill" : icon)
                    .font(.system(size: 18))
                    .foregroundStyle(granted ? .green : Color.accentColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !granted {
                Button("Autoriser") { action() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
        .animation(.easeInOut(duration: 0.2), value: granted)
    }
}
