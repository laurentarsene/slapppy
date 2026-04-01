//
//  ActionExecutor.swift
//  Slappy
//
//  Created by Arsène Laurent on 28/03/2026.
//

import AppKit
import CoreGraphics
import ApplicationServices

/// Translates a PatternAction into system-level keyboard events (CGEvent).
///
/// Requires Accessibility permission — show the warning button in the UI until
/// `isAccessibilityGranted` returns true.
enum ActionExecutor {

    static var isAccessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system dialog asking the user to grant Accessibility access.
    static func requestAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    /// Fires the appropriate system event(s) for `action`. No-op for `.none`.
    static func execute(_ action: PatternAction) {
        print("[Slapppy] execute action=\(action) trusted=\(AXIsProcessTrusted())")
        switch action {
        case .none:                   break
        case .virtualKey(let code):   postKey(code)
        case .typeText(let text):     postText(text)
        case .launchApp(let bundleID, _):
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                NSWorkspace.shared.openApplication(at: url, configuration: .init(), completionHandler: nil)
            }
        }
    }

    // MARK: - Private

    private static func postKey(_ keyCode: UInt16) {
        let src = CGEventSource(stateID: .hidSystemState)
        CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true)?.post(tap: .cghidEventTap)
        CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false)?.post(tap: .cghidEventTap)
    }

    private static func postText(_ text: String) {
        let src = CGEventSource(stateID: .hidSystemState)
        for scalar in text.unicodeScalars {
            guard scalar.value <= 0xFFFF else { continue }   // BMP only
            let u = [UniChar(scalar.value)]
            let dn = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true)
            let up = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false)
            dn?.keyboardSetUnicodeString(stringLength: 1, unicodeString: u)
            up?.keyboardSetUnicodeString(stringLength: 1, unicodeString: u)
            dn?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
        }
    }
}
