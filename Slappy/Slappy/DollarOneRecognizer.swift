//
//  DollarOneRecognizer.swift
//  Slappy
//
//  Created by Arsène Laurent on 28/03/2026.
//

import CoreGraphics
import Foundation

/// Pure Swift implementation of the $1 Unistroke Recognizer.
/// Wobbrock, Wilson & Li — UIST 2007.
///
/// Pipeline (both recording and recognition):
///   1. Resample path to N evenly-spaced points
///   2. Rotate so that the angle from centroid → first point is 0
///   3. Scale non-uniformly to squareSize × squareSize bounding box
///   4. Translate centroid to origin
///
/// Recognition: golden-section search for the best rotation in [−45°, +45°]
/// that minimises average point-distance between candidate and template.
/// Score = 1 − bestDist / halfDiagonal  ∈ [0, 1]
enum DollarOneRecognizer {

    static let numPoints:      Int    = 64
    static let squareSize:     Double = 250.0
    static let matchThreshold: Double = 0.80

    private static let halfDiag:       Double = 0.5 * sqrt(2) * squareSize
    private static let angleRange:     Double = .pi / 4        // ±45°
    private static let angleThreshold: Double = .pi / 90       // 2° precision

    // MARK: - Public

    /// Convert raw screen-space points to the normalised form stored in GestureTemplate.
    static func normalise(_ raw: [CGPoint]) -> [GesturePoint] {
        guard raw.count >= 2 else { return [] }
        var pts = resample(raw, n: numPoints)
        guard !pts.isEmpty else { return [] }
        pts = rotate(pts, by: -indicativeAngle(pts))
        pts = scaleTo(pts, size: squareSize)
        pts = translateTo(pts, target: .zero)
        return pts.map { GesturePoint(x: Double($0.x), y: Double($0.y)) }
    }

    /// Convert raw points to a display-only form: resampled, uniformly scaled,
    /// centered — but NOT rotated and NOT non-uniformly stretched.
    static func normaliseForDisplay(_ raw: [CGPoint]) -> [GesturePoint] {
        guard raw.count >= 2 else { return [] }
        var pts = resample(raw, n: numPoints)
        guard !pts.isEmpty else { return [] }
        pts = scaleUniform(pts, size: squareSize)
        pts = translateTo(pts, target: .zero)
        return pts.map { GesturePoint(x: Double($0.x), y: Double($0.y)) }
    }

    /// Score a normalised candidate against all stored templates.
    /// Returns the best match and its score, or nil if `templates` is empty.
    static func bestMatch(
        candidate: [GesturePoint],
        templates: [GestureTemplate]
    ) -> (template: GestureTemplate, score: Double)? {
        guard !candidate.isEmpty, !templates.isEmpty else { return nil }
        let cPts = candidate.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) }
        var best = (template: templates[0], score: 0.0)
        for t in templates {
            let tPts = t.path.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) }
            guard tPts.count == cPts.count else { continue }
            let s = goldenSection(cPts, tPts)
            if s > best.score { best = (t, s) }
        }
        return best
    }

    // MARK: - Core: golden-section search

    private static func goldenSection(_ cand: [CGPoint], _ tmpl: [CGPoint]) -> Double {
        let phi = 0.5 * (sqrt(5.0) - 1.0)
        var a = -angleRange, b = angleRange
        var x1 = phi * a + (1 - phi) * b
        var x2 = (1 - phi) * a + phi * b
        var f1 = avgDist(rotate(cand, by: x1), tmpl)
        var f2 = avgDist(rotate(cand, by: x2), tmpl)
        while abs(b - a) > angleThreshold {
            if f1 < f2 {
                b = x2; x2 = x1; f2 = f1
                x1 = phi * a + (1 - phi) * b
                f1 = avgDist(rotate(cand, by: x1), tmpl)
            } else {
                a = x1; x1 = x2; f1 = f2
                x2 = (1 - phi) * a + phi * b
                f2 = avgDist(rotate(cand, by: x2), tmpl)
            }
        }
        return max(0, 1.0 - min(f1, f2) / halfDiag)
    }

    private static func avgDist(_ a: [CGPoint], _ b: [CGPoint]) -> Double {
        zip(a, b).reduce(0.0) {
            $0 + hypot(Double($1.0.x - $1.1.x), Double($1.0.y - $1.1.y))
        } / Double(a.count)
    }

    // MARK: - Normalisation steps

    /// Resample `pts` to `n` evenly-spaced points along the path.
    private static func resample(_ pts: [CGPoint], n: Int) -> [CGPoint] {
        let total = pathLen(pts)
        guard total > 0, n > 1 else { return Array(repeating: pts[0], count: n) }
        let I   = total / Double(n - 1)
        var D   = 0.0
        var out = [pts[0]]
        var arr = pts          // mutable copy; we insert interpolated pts as we go
        var i   = 1
        while i < arr.count && out.count < n {
            let d = hypot(Double(arr[i].x - arr[i-1].x), Double(arr[i].y - arr[i-1].y))
            if D + d >= I {
                let t = CGFloat((I - D) / d)
                let q = CGPoint(x: arr[i-1].x + t * (arr[i].x - arr[i-1].x),
                                y: arr[i-1].y + t * (arr[i].y - arr[i-1].y))
                out.append(q)
                arr.insert(q, at: i)  // q becomes new prev for next segment
                D = 0
            } else {
                D += d
                i += 1
            }
        }
        while out.count < n { out.append(arr.last!) }
        return Array(out.prefix(n))
    }

    private static func pathLen(_ pts: [CGPoint]) -> Double {
        zip(pts, pts.dropFirst()).reduce(0.0) {
            $0 + hypot(Double($1.1.x - $1.0.x), Double($1.1.y - $1.0.y))
        }
    }

    /// Angle from centroid to first point — used to zero-align the path.
    private static func indicativeAngle(_ pts: [CGPoint]) -> Double {
        let c = centroid(pts)
        return atan2(Double(pts[0].y - c.y), Double(pts[0].x - c.x))
    }

    private static func rotate(_ pts: [CGPoint], by angle: Double) -> [CGPoint] {
        let c = centroid(pts)
        let cosA = cos(angle), sinA = sin(angle)
        return pts.map {
            let dx = Double($0.x - c.x), dy = Double($0.y - c.y)
            return CGPoint(x: CGFloat(dx * cosA - dy * sinA) + c.x,
                           y: CGFloat(dx * sinA + dy * cosA) + c.y)
        }
    }

    /// Non-uniform scale so bounding box fits exactly in `size × size`.
    private static func scaleTo(_ pts: [CGPoint], size: Double) -> [CGPoint] {
        let xs = pts.map { Double($0.x) }, ys = pts.map { Double($0.y) }
        let w = (xs.max()! - xs.min()!), h = (ys.max()! - ys.min()!)
        let sw = w > 0 ? CGFloat(size / w) : 1
        let sh = h > 0 ? CGFloat(size / h) : 1
        return pts.map { CGPoint(x: $0.x * sw, y: $0.y * sh) }
    }

    /// Uniform scale so the largest dimension fits within `size`, preserving aspect ratio.
    private static func scaleUniform(_ pts: [CGPoint], size: Double) -> [CGPoint] {
        let xs = pts.map { Double($0.x) }, ys = pts.map { Double($0.y) }
        let w = (xs.max()! - xs.min()!), h = (ys.max()! - ys.min()!)
        let maxDim = max(w, h)
        let s = maxDim > 0 ? CGFloat(size / maxDim) : 1
        return pts.map { CGPoint(x: $0.x * s, y: $0.y * s) }
    }

    /// Translate so the centroid lands exactly at `target`.
    private static func translateTo(_ pts: [CGPoint], target: CGPoint) -> [CGPoint] {
        let c = centroid(pts)
        return pts.map { CGPoint(x: $0.x + target.x - c.x, y: $0.y + target.y - c.y) }
    }

    private static func centroid(_ pts: [CGPoint]) -> CGPoint {
        let n = CGFloat(pts.count)
        return CGPoint(x: pts.reduce(CGFloat(0)) { $0 + $1.x } / n,
                       y: pts.reduce(CGFloat(0)) { $0 + $1.y } / n)
    }
}
