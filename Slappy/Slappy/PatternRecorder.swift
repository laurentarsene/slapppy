//
//  PatternRecorder.swift
//  Slappy
//
//  Created by Arsène Laurent on 28/03/2026.
//

import Foundation

/// Records a rhythmic slap sequence (timing + intensity) and turns it into a Pattern.
///
/// State machine:
///   idle → startRecording → recording
///   recording / active → handleSlap(intensity:) → active   (resets 1.5 s end-timer)
///   active → [1.5 s silence, ≥2 slaps] → captured         (awaiting name + save)
///   active → [1.5 s silence, <2 slaps]  → idle             (too few slaps, discarded)
@Observable
final class PatternRecorder {

    enum State { case idle, recording, active, captured }

    var state:      State       = .idle
    var slapEvents: [SlapEvent] = []

    var slapCount: Int { slapEvents.count }

    private var lastEventTime: Date?
    private var timeoutTask:   Task<Void, Never>?
    private let endTimeout:    TimeInterval = 1.5

    // MARK: - Public API

    func startRecording() {
        cancelTimeout()
        slapEvents    = []
        lastEventTime = nil
        state         = .recording
    }

    /// Called by AccelerometerReader.onSlap — receives the raw posdev at slap time.
    func handleSlap(intensity: Double) {
        guard intensity >= kMinPatternIntensity else { return }
        guard state == .recording || state == .active else { return }
        let now      = Date()
        let interval = lastEventTime.map { now.timeIntervalSince($0) } ?? 0
        slapEvents.append(SlapEvent(interval: interval, intensity: intensity))
        lastEventTime = now
        state         = .active
        resetTimeout()
    }

    func discard() {
        cancelTimeout()
        slapEvents    = []
        lastEventTime = nil
        state         = .idle
    }

    /// Builds a Pattern from the recorded slaps and resets the recorder.
    /// Returns nil if fewer than 2 slaps were recorded.
    func build(name: String) -> Pattern? {
        guard slapEvents.count >= 2 else { discard(); return nil }
        let n       = name.trimmingCharacters(in: .whitespaces)
        let pattern = Pattern(name: n.isEmpty ? "Pattern" : n, slaps: slapEvents)
        discard()
        return pattern
    }

    // MARK: - Private

    private func resetTimeout() {
        cancelTimeout()
        timeoutTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(endTimeout * 1_000_000_000))
            guard !Task.isCancelled else { return }
            if slapEvents.count >= 2 {
                state = .captured
            } else {
                discard()
            }
        }
    }

    private func cancelTimeout() {
        timeoutTask?.cancel()
        timeoutTask = nil
    }
}
