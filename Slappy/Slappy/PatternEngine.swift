//
//  PatternEngine.swift
//  Slappy
//
//  Created by Arsène Laurent on 28/03/2026.
//

import Foundation

/// Real-time pattern matcher.
///
/// Maintains a sliding window of the last 10 slaps (evicting entries older than 10 s).
/// After every new slap it checks all stored patterns:
///   - Takes the last K entries for a K-slap pattern
///   - Scores them with PatternMatcher (timing 65% + intensity 35%)
///   - Fires `onMatch` when score ≥ 70 % and the cooldown for that pattern has elapsed
@Observable
final class PatternEngine {

    /// Most recently matched pattern — update triggers UI.
    var lastMatchedPattern: Pattern? = nil
    var lastMatchScore:     Double   = 0

    /// Called on the main thread on every successful match.
    /// Step 6 will wire this to CGEvent / text-injection action execution.
    var onMatch: ((Pattern) -> Void)?

    @ObservationIgnored var settings: SettingsStore?

    @ObservationIgnored private var window: [(date: Date, event: SlapEvent)] = []
    @ObservationIgnored private var lastMatchTimes: [UUID: CFAbsoluteTime]  = [:]
    @ObservationIgnored private var currentMatchID: UUID = UUID()

    private let maxWindowAge:  TimeInterval = 10.0  // evict slaps older than this
    private let maxWindowSize: Int          = 10    // safety cap on window size

    // MARK: - Public

    /// Call this from `AccelerometerReader.onSlap`.
    /// `patterns` is the current contents of PatternStore — passed in so the engine
    /// stays stateless w.r.t. the store and requires no separate reference to it.
    func handleSlap(intensity: Double, patterns: [Pattern]) {
        guard intensity >= kMinPatternIntensity else { return }
        let now      = Date()
        let interval = window.last.map { now.timeIntervalSince($0.date) } ?? 0
        let event    = SlapEvent(interval: interval, intensity: intensity)

        // Evict stale entries
        let cutoff = now.addingTimeInterval(-maxWindowAge)
        window.removeAll { $0.date < cutoff }

        window.append((date: now, event: event))
        if window.count > maxWindowSize { window.removeFirst() }

        check(patterns: patterns)
    }

    // MARK: - Private

    private func check(patterns: [Pattern]) {
        let absNow = CFAbsoluteTimeGetCurrent()

        for pattern in patterns {
            let k = pattern.slapCount
            guard window.count >= k else { continue }

            let candidate = window.suffix(k).map(\.event)
            let s = PatternMatcher.score(reference: pattern, candidate: candidate)
            guard s >= PatternMatcher.matchThreshold else { continue }

            // Per-pattern cooldown — prevents re-triggering on overlapping windows
            let lastFired = lastMatchTimes[pattern.id] ?? 0
            let cooldown  = settings?.matchCooldown ?? 1.5
            guard absNow - lastFired > cooldown else { continue }

            lastMatchTimes[pattern.id] = absNow
            lastMatchedPattern = pattern
            lastMatchScore     = s
            onMatch?(pattern)
            print("[Slapppy] ✓ '\(pattern.name)' score=\(Int(s * 100))%")

            // Auto-clear match badge after 3 s
            let mid = UUID(); currentMatchID = mid
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                if self?.currentMatchID == mid { self?.lastMatchedPattern = nil }
            }
        }
    }
}
