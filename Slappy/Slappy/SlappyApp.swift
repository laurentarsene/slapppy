//
//  SlappyApp.swift
//  Slappy
//
//  Created by Arsène Laurent on 28/03/2026.
//

import SwiftUI

@main
struct SlappyApp: App {
    @State private var license         = LicenseManager()
    @State private var updater         = AppUpdater()
    @State private var trackpad        = TrackpadReader()
    @State private var recorder        = PatternRecorder()
    @State private var store           = PatternStore()
    @State private var engine          = PatternEngine()
    @State private var gestureRecorder = GestureRecorder()
    @State private var gestureStore    = GestureStore()
    @State private var gestureEngine   = GestureEngine()
    @State private var settings        = SettingsStore()
    @State private var menuIcon        = "hand.tap.fill"
    @State private var enginesStarted  = false
    @AppStorage("onboardingDone") private var onboardingDone = false

    private var shouldShowOnboarding: Bool {
        !onboardingDone && store.patterns.isEmpty && gestureStore.templates.isEmpty
    }

    var body: some Scene {
        MenuBarExtra {
            if license.isActivated {
                if shouldShowOnboarding {
                    OnboardingView { onboardingDone = true }
                        .environment(trackpad)
                } else {
                    ContentView()
                        .environment(updater)
                        .environment(trackpad)
                        .environment(recorder)
                        .environment(store)
                        .environment(engine)
                        .environment(gestureRecorder)
                        .environment(gestureStore)
                        .environment(gestureEngine)
                        .environment(settings)
                        .environment(license)
                        .onAppear { startEngines() }
                        .onReceive(NotificationCenter.default.publisher(
                            for: NSApplication.willTerminateNotification)) { _ in
                            trackpad.stop()
                        }
                }
            } else {
                ActivationView()
                    .environment(license)
            }
        } label: {
            Image(systemName: menuIcon)
                .symbolRenderingMode(.hierarchical)
        }
        .menuBarExtraStyle(.window)
    }

    // MARK: – Engine setup (runs once after first activation)

    private func startEngines() {
        guard !enginesStarted else { return }
        enginesStarted = true

        engine.settings        = settings
        gestureEngine.settings = settings
        trackpad.settings      = settings
        trackpad.start()

        trackpad.onTap = { [self] intensity in
            recorder.handleSlap(intensity: intensity)
            engine.handleSlap(intensity: intensity, patterns: store.patterns)
        }

        trackpad.onLiveGestureUpdate = { [self] points in
            if gestureRecorder.state == .recording {
                gestureRecorder.updateLivePoints(points)
            }
        }

        trackpad.onGesture = { [self] points in
            if gestureRecorder.state == .recording {
                gestureRecorder.handleGesture(points: points)
            } else {
                gestureEngine.handleGesture(rawPoints: points, templates: gestureStore.templates)
            }
        }

        engine.onMatch = { [self] pattern in
            flashIcon()
            ActionExecutor.execute(pattern.action)
        }

        gestureEngine.onMatch = { [self] template in
            flashIcon()
            ActionExecutor.execute(template.action)
        }
    }

    private func flashIcon() {
        menuIcon = "checkmark.circle.fill"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            menuIcon = "hand.tap.fill"
        }
    }
}
