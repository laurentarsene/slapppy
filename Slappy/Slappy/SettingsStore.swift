//
//  SettingsStore.swift
//  Slappy
//
//  Created by Arsène Laurent on 28/03/2026.
//

import Foundation

/// Persisted user-adjustable sensitivity settings.
/// Property observers automatically push changed values to the static
/// constants used by PatternMatcher and DollarOneRecognizer.
/// PatternEngine / GestureEngine / TrackpadReader read their own values
/// from this store directly at runtime via a stored reference.
@Observable
final class SettingsStore {

    // MARK: - Settings

    /// Minimum similarity score (0–1) for a slap pattern to match.
    var patternThreshold: Double = 0.75 {
        didSet { save(); PatternMatcher.matchThreshold = patternThreshold }
    }

    /// Allowed inter-slap timing variation (0–1, e.g. 0.30 = ±30 %).
    var timingTolerance: Double = 0.30 {
        didSet { save(); PatternMatcher.timingTolerance = timingTolerance }
    }

    /// Minimum similarity score (0–1) for a gesture to match.
    var gestureThreshold: Double = 0.80 {
        didSet { save(); DollarOneRecognizer.matchThreshold = gestureThreshold }
    }

    /// Minimum seconds before the same pattern/gesture can fire again.
    var matchCooldown: Double = 1.5 {
        didSet { save() }
    }

    /// Minimum trackpad path length (pts) required to register a gesture.
    var minGesturePathLength: Double = 30.0 {
        didSet { save() }
    }

    // MARK: - Init

    init() {
        let d = UserDefaults.standard
        if let v = d.object(forKey: "s.patternThreshold")     as? Double { patternThreshold     = v }
        if let v = d.object(forKey: "s.timingTolerance")      as? Double { timingTolerance      = v }
        if let v = d.object(forKey: "s.gestureThreshold")     as? Double { gestureThreshold     = v }
        if let v = d.object(forKey: "s.matchCooldown")        as? Double { matchCooldown        = v }
        if let v = d.object(forKey: "s.minGesturePathLength") as? Double { minGesturePathLength = v }
        // didSet is not called during init — push loaded values manually.
        PatternMatcher.matchThreshold      = patternThreshold
        PatternMatcher.timingTolerance     = timingTolerance
        DollarOneRecognizer.matchThreshold = gestureThreshold
    }

    // MARK: - Reset

    func reset() {
        patternThreshold     = 0.75
        timingTolerance      = 0.30
        gestureThreshold     = 0.80
        matchCooldown        = 1.5
        minGesturePathLength = 30.0
    }

    // MARK: - Persistence

    private func save() {
        let d = UserDefaults.standard
        d.set(patternThreshold,     forKey: "s.patternThreshold")
        d.set(timingTolerance,      forKey: "s.timingTolerance")
        d.set(gestureThreshold,     forKey: "s.gestureThreshold")
        d.set(matchCooldown,        forKey: "s.matchCooldown")
        d.set(minGesturePathLength, forKey: "s.minGesturePathLength")
    }
}
