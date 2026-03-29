//
//  GestureRecorder.swift
//  Slappy
//
//  Created by Arsène Laurent on 28/03/2026.
//

import CoreGraphics
import Foundation

/// Captures a single ⌥+drag gesture and converts it into a GestureTemplate.
///
/// State machine:
///   idle → startRecording → recording
///   recording → handleGesture(points:) → captured   (≥ 5 points)
///   recording → handleGesture(points:) → idle        (< 5 points — too short, discarded)
///   captured  → build(name:)           → idle
///   any       → discard()              → idle
@Observable
final class GestureRecorder {

    enum State { case idle, recording, captured }

    var state:                State          = .idle
    var capturedPoints:       [GesturePoint] = []   // normalised, ready for recognition
    var capturedDisplayPoints:[GesturePoint] = []   // for display only (no rotation/stretch)

    // MARK: - Public API

    func startRecording() {
        capturedPoints        = []
        capturedDisplayPoints = []
        state                 = .recording
    }

    /// Called once per completed drag gesture (all points delivered in one batch).
    func handleGesture(points: [CGPoint]) {
        guard state == .recording else { return }
        let normalised = DollarOneRecognizer.normalise(points)
        if normalised.count >= 5 {
            capturedPoints        = normalised
            capturedDisplayPoints = DollarOneRecognizer.normaliseForDisplay(points)
            state                 = .captured
        } else {
            discard()
        }
    }

    /// Build a GestureTemplate from the captured path and reset the recorder.
    /// Returns nil if not in the captured state.
    func build(name: String) -> GestureTemplate? {
        guard state == .captured else { return nil }
        let n = name.trimmingCharacters(in: .whitespaces)
        let t = GestureTemplate(name: n.isEmpty ? "Geste" : n,
                                path: capturedPoints,
                                displayPath: capturedDisplayPoints)
        discard()
        return t
    }

    func discard() {
        capturedPoints        = []
        capturedDisplayPoints = []
        state                 = .idle
    }
}
