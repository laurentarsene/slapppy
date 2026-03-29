//
//  SlappyApp.swift
//  Slappy
//
//  Created by Arsène Laurent on 28/03/2026.
//

import SwiftUI
import Sparkle

@main
struct SlappyApp: App {
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    @State private var trackpad        = TrackpadReader()
    @State private var recorder        = PatternRecorder()
    @State private var store           = PatternStore()
    @State private var engine          = PatternEngine()
    @State private var gestureRecorder = GestureRecorder()
    @State private var gestureStore    = GestureStore()
    @State private var gestureEngine   = GestureEngine()

    var body: some Scene {
        MenuBarExtra("Slapppy", systemImage: "hand.tap.fill") {
            ContentView()
                .environment(trackpad)
                .environment(recorder)
                .environment(store)
                .environment(engine)
                .environment(gestureRecorder)
                .environment(gestureStore)
                .environment(gestureEngine)
                .onAppear {
                    trackpad.start()

                    trackpad.onTap = { [self] intensity in
                        recorder.handleSlap(intensity: intensity)
                        engine.handleSlap(intensity: intensity, patterns: store.patterns)
                    }

                    trackpad.onGesture = { [self] points in
                        if gestureRecorder.state == .recording {
                            gestureRecorder.handleGesture(points: points)
                        } else {
                            gestureEngine.handleGesture(rawPoints: points, templates: gestureStore.templates)
                        }
                    }

                    engine.onMatch = { pattern in
                        ActionExecutor.execute(pattern.action)
                    }

                    gestureEngine.onMatch = { template in
                        ActionExecutor.execute(template.action)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(
                    for: NSApplication.willTerminateNotification)) { _ in
                    trackpad.stop()
                }
        }
        .menuBarExtraStyle(.window)
    }
}
