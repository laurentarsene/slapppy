//
//  TrackpadReader.swift
//  Slappy
//
//  Created by Arsène Laurent on 28/03/2026.
//

import AppKit
import Foundation
import CoreGraphics
import ApplicationServices

/// Detects rhythmic ⌥ + trackpad taps and converts them into slap events.
///
/// Intensity is derived from contact duration (mouse-down → mouse-up):
///   long press / physical click (~150–200 ms) → high intensity (~1200)
///   light quick tap             (~20–50 ms)   → low intensity  (~400)
///
/// This gives meaningful intensity variation on every MacBook, with no
/// dependency on Force Touch hardware.
@Observable
final class TrackpadReader {

    var onTap:     ((Double)    -> Void)?
    var onGesture: (([CGPoint]) -> Void)?

    var isListening              = false
    var isInputMonitoringGranted = false
    var isAccessibilityGranted   = false
    var tapCount:    Int  = 0
    var lastTapDate: Date = .distantPast

    @ObservationIgnored var settings: SettingsStore?

    @ObservationIgnored private var tapDownDate:     Date?     = nil
    @ObservationIgnored private var optionHeld:      Bool      = false
    @ObservationIgnored private var gesturePoints:   [CGPoint] = []
    @ObservationIgnored private var globalMonitor:   Any?
    @ObservationIgnored private var localMonitor:    Any?
    @ObservationIgnored private var permissionTimer: Timer?

    // MARK: - Lifecycle

    func start() {
        guard globalMonitor == nil else { return }

        // DOWN — record tap timestamp if ⌥ is held
        let onDown: (NSEvent) -> Void = { [weak self] event in
            guard event.modifierFlags.contains(.option) else { return }
            self?.tapDownDate = Date()
        }

        // UP — fire tap callback; also reset gesture buffer so an accidental
        //       click during a gesture draw doesn't leave stale points.
        let onUp: (NSEvent) -> Void = { [weak self] event in
            guard let self, let downDate = tapDownDate else { return }
            tapDownDate   = nil
            gesturePoints = []   // discard any movement that happened during the click
            let ms = Date().timeIntervalSince(downDate) * 1000
            let intensity = max(400.0, min(1200.0, 400.0 + ms * 5.3))
            tapCount    += 1
            lastTapDate  = Date()
            onTap?(intensity)
            print("[Slapppy] Tap! \(Int(ms)) ms → intensity \(Int(intensity))")
        }

        // MOVE — accumulate relative deltas while ⌥ is held
        // deltaX/deltaY capture actual finger movement, independent of
        // cursor speed settings and screen position.
        let onMove: (NSEvent) -> Void = { [weak self] event in
            guard let self, optionHeld, let last = gesturePoints.last else { return }
            gesturePoints.append(CGPoint(
                x: last.x + Double(event.deltaX),
                y: last.y - Double(event.deltaY)  // deltaY is positive downward in AppKit
            ))
        }

        // FLAGS — detect ⌥ press/release to start/finish gesture capture
        let onFlags: (NSEvent) -> Void = { [weak self] event in
            guard let self else { return }
            let nowHeld = event.modifierFlags.contains(.option)
            if nowHeld && !optionHeld {
                // ⌥ just pressed → start fresh capture from origin
                optionHeld    = true
                gesturePoints = [.zero]
            } else if !nowHeld && optionHeld {
                // ⌥ just released → evaluate the collected path
                optionHeld = false
                let captured = gesturePoints
                gesturePoints = []
                let pathLen = zip(captured, captured.dropFirst()).reduce(0.0) {
                    $0 + hypot(Double($1.1.x - $1.0.x), Double($1.1.y - $1.0.y))
                }
                let minLen = settings?.minGesturePathLength ?? 30.0
                if pathLen >= minLen {
                    onGesture?(captured)
                    print("[Slapppy] Gesture! \(captured.count) pts, path=\(Int(pathLen))pt")
                }
            }
        }

        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseUp,
                                           .mouseMoved, .flagsChanged]

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { event in
            switch event.type {
            case .leftMouseDown: onDown(event)
            case .leftMouseUp:   onUp(event)
            case .mouseMoved:    onMove(event)
            case .flagsChanged:  onFlags(event)
            default: break
            }
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { event in
            switch event.type {
            case .leftMouseDown: onDown(event)
            case .leftMouseUp:   onUp(event)
            case .mouseMoved:    onMove(event)
            case .flagsChanged:  onFlags(event)
            default: break
            }
            return event    // pass through so Slappy's own UI still works
        }

        isListening = globalMonitor != nil || localMonitor != nil

        checkPermissions()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.checkPermissions()
        }

        print("[Slapppy] TrackpadReader started — global=\(globalMonitor != nil) local=\(localMonitor != nil)")
    }

    func stop() {
        permissionTimer?.invalidate(); permissionTimer = nil
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
        if let m = localMonitor  { NSEvent.removeMonitor(m); localMonitor  = nil }
        isListening = false
    }

    func requestInputMonitoring() { CGRequestListenEventAccess() }

    func requestAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    // MARK: - Private

    private func checkPermissions() {
        isInputMonitoringGranted = CGPreflightListenEventAccess()
        isAccessibilityGranted   = AXIsProcessTrusted()
    }
}
