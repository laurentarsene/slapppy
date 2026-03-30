//
//  Pattern.swift
//  Slappy
//
//  Created by Arsène Laurent on 28/03/2026.
//

import Foundation
import SwiftUI

/// Minimum posdev for a slap to participate in pattern recording / matching.
/// The detection threshold in AccelerometerReader is ~260 (noiseEnvelope + kSlapMargin).
/// Anything that barely clears 260 is likely a vibration artefact, not an intentional tap.
/// Real taps — even soft ones — should comfortably exceed this.
let kMinPatternIntensity: Double = 250.0

// MARK: - SlapEvent

/// One slap in a pattern.
/// `interval` = seconds since the previous slap (0 for the first slap).
/// `intensity` = raw deviation above EMA at the moment of detection.
struct SlapEvent: Codable, Equatable {
    var interval:  TimeInterval
    var intensity: Double
}

// MARK: - Pattern

struct Pattern: Identifiable, Codable, Equatable {
    var id:     UUID   = UUID()
    var name:   String
    var slaps:  [SlapEvent]
    var action: PatternAction = .none

    var slapCount: Int { slaps.count }

    /// Normalised intensity for slap at `index` (0 = softest, 1 = hardest in this pattern).
    func normalisedIntensity(at index: Int) -> Double {
        let max = slaps.map(\.intensity).max() ?? 1
        guard max > 0 else { return 0.5 }
        return slaps[index].intensity / max
    }
}

// MARK: - PatternAction

enum PatternAction: Codable, Equatable {
    case none
    case virtualKey(keyCode: UInt16)   // F13 = 105, F14 = 107 …
    case typeText(String)
}

// MARK: - PatternStore

@Observable
final class PatternStore {
    private(set) var patterns: [Pattern] = []

    init() { load() }

    // MARK: Mutations (all auto-save)

    func add(_ pattern: Pattern) {
        patterns.append(pattern)
        save()
    }

    func remove(id: UUID) {
        patterns.removeAll { $0.id == id }
        save()
    }

    func rename(id: UUID, to name: String) {
        guard let i = patterns.firstIndex(where: { $0.id == id }) else { return }
        let n = name.trimmingCharacters(in: .whitespaces)
        patterns[i].name = n.isEmpty ? "Pattern" : n
        save()
    }

    func setAction(_ action: PatternAction, forID id: UUID) {
        guard let i = patterns.firstIndex(where: { $0.id == id }) else { return }
        patterns[i].action = action
        save()
    }

    // MARK: Persistence

    private let saveKey = "slappy.patterns"

    func save() {
        guard let data = try? JSONEncoder().encode(patterns) else { return }
        UserDefaults.standard.set(data, forKey: saveKey)
    }

    private func load() {
        guard let data  = UserDefaults.standard.data(forKey: saveKey),
              let saved = try? JSONDecoder().decode([Pattern].self, from: data)
        else { return }
        patterns = saved
    }
}

// MARK: - PatternMatcher

/// Fuzzy similarity between a reference pattern and a live slap sequence.
///
/// Score breakdown:
///   - Timing   (55%): normalised inter-slap intervals, tolerance ±35%
///   - Intensity (45%): normalised per-slap intensities, tolerance ±25%
///
/// Both dimensions are scale-invariant:
///   - Timing is normalised by total duration    → fast & slow versions of the same rhythm match.
///   - Intensity is normalised by the local peak → hard and soft slappers match their own style.
///
/// Intensity uses a power transform (exponent 2) before comparison so that the distance
/// between e.g. soft (0.2) and medium (0.5) is amplified from 0.3 → 0.21 in linear space
/// to |0.04 − 0.25| = 0.21 after squaring — the *relative* gap grows, making soft/medium/hard
/// clearly distinguishable while small natural replaying variation stays well within tolerance.
enum PatternMatcher {

    static let timingWeight:        Double = 0.60  // timing is primary
    static let intensityWeight:     Double = 0.40  // duration-based intensity
    static var timingTolerance:     Double = 0.30  // ±30% on normalised intervals (overridden by SettingsStore)
    static let intensityTolerance:  Double = 0.40  // looser: contact-time intensity is noisier than impact
    static let intensityExponent:   Double = 1.0   // linear — duration gives enough separation without squaring
    static var matchThreshold:      Double = 0.75  // overridden by SettingsStore

    /// Returns a similarity score in [0, 1].
    /// Returns 0 immediately if slap counts differ.
    static func score(reference: Pattern, candidate: [SlapEvent]) -> Double {
        guard reference.slapCount == candidate.count, !candidate.isEmpty else { return 0 }
        let t = timingScore(ref: reference.slaps, cand: candidate)
        let i = intensityScore(ref: reference.slaps, cand: candidate)
        return timingWeight * t + intensityWeight * i
    }

    static func matches(reference: Pattern, candidate: [SlapEvent]) -> Bool {
        score(reference: reference, candidate: candidate) >= matchThreshold
    }

    // MARK: - Private

    private static func timingScore(ref: [SlapEvent], cand: [SlapEvent]) -> Double {
        // First slap has interval == 0; compare only the N-1 gaps between slaps.
        let refI  = ref.dropFirst().map(\.interval)
        let candI = cand.dropFirst().map(\.interval)
        guard !refI.isEmpty else { return 1.0 }  // single-slap pattern: timing trivially matches

        let refTotal  = refI.reduce(0, +)
        let candTotal = candI.reduce(0, +)
        guard refTotal > 0, candTotal > 0 else { return 0 }

        let refNorm  = refI.map  { $0 / refTotal  }
        let candNorm = candI.map { $0 / candTotal }

        let scores = zip(refNorm, candNorm).map { r, c -> Double in
            max(0, 1 - abs(r - c) / timingTolerance)
        }
        return scores.reduce(0, +) / Double(scores.count)
    }

    private static func intensityScore(ref: [SlapEvent], cand: [SlapEvent]) -> Double {
        let refMax  = ref.map(\.intensity).max()  ?? 1
        let candMax = cand.map(\.intensity).max() ?? 1
        guard refMax > 0, candMax > 0 else { return 0.5 }  // no intensity data: neutral score

        // Normalise then apply power transform so that the gap between soft/medium/hard
        // is amplified in proportion to the exponent, making levels clearly distinct.
        let refNorm  = ref.map  { pow($0.intensity / refMax,  intensityExponent) }
        let candNorm = cand.map { pow($0.intensity / candMax, intensityExponent) }

        let scores = zip(refNorm, candNorm).map { r, c -> Double in
            max(0, 1 - abs(r - c) / intensityTolerance)
        }
        return scores.reduce(0, +) / Double(scores.count)
    }
}
