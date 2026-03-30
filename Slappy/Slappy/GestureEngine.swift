//
//  GestureEngine.swift
//  Slappy
//
//  Created by Arsène Laurent on 28/03/2026.
//

import CoreGraphics
import Foundation

/// Matches incoming drag gestures against stored GestureTemplates.
///
/// Normalises each live gesture with DollarOneRecognizer, scores it against
/// all templates, and fires `onMatch` when score ≥ matchThreshold and the
/// per-template cooldown has elapsed.
@Observable
final class GestureEngine {

    var lastMatchedTemplate: GestureTemplate? = nil
    var lastMatchScore:      Double           = 0

    /// Called on the main thread on every successful match.
    var onMatch: ((GestureTemplate) -> Void)?

    @ObservationIgnored var settings: SettingsStore?

    @ObservationIgnored private var lastMatchTimes: [UUID: CFAbsoluteTime] = [:]
    @ObservationIgnored private var currentMatchID: UUID = UUID()

    // MARK: - Public

    func handleGesture(rawPoints: [CGPoint], templates: [GestureTemplate]) {
        guard rawPoints.count >= 5, !templates.isEmpty else { return }

        let normalised = DollarOneRecognizer.normalise(rawPoints)
        guard !normalised.isEmpty else { return }

        guard let (template, score) = DollarOneRecognizer.bestMatch(
            candidate: normalised,
            templates: templates
        ) else { return }

        guard score >= DollarOneRecognizer.matchThreshold else {
            print("[Slapppy] Gesture — best '\(template.name)' score=\(Int(score * 100))% (below threshold)")
            return
        }

        let absNow    = CFAbsoluteTimeGetCurrent()
        let lastFired = lastMatchTimes[template.id] ?? 0
        let cooldown  = settings?.matchCooldown ?? 1.5
        guard absNow - lastFired > cooldown else { return }

        lastMatchTimes[template.id] = absNow
        lastMatchedTemplate = template
        lastMatchScore      = score
        onMatch?(template)
        print("[Slapppy] Gesture ✓ '\(template.name)' score=\(Int(score * 100))%")

        // Auto-clear badge after 3 s
        let mid = UUID(); currentMatchID = mid
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            if self?.currentMatchID == mid { self?.lastMatchedTemplate = nil }
        }
    }
}
