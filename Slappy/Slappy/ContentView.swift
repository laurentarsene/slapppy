//
//  ContentView.swift
//  Slappy
//
//  Created by Arsène Laurent on 28/03/2026.
//

import AppKit
import SwiftUI
import ServiceManagement

struct ContentView: View {
    @Environment(AppUpdater.self)       private var updater
    @Environment(TrackpadReader.self)   private var trackpad
    @Environment(PatternRecorder.self)  private var recorder
    @Environment(PatternStore.self)     private var store
    @Environment(PatternEngine.self)    private var engine
    @Environment(GestureRecorder.self)  private var gestureRecorder
    @Environment(GestureStore.self)     private var gestureStore
    @Environment(GestureEngine.self)    private var gestureEngine
    @Environment(SettingsStore.self)    private var settings

    @State private var mode               = 0       // 0 = Slaps, 1 = Gestes, 2 = Réglages
    @State private var newPatternName     = ""
    @State private var editingPatternID:  UUID? = nil
    @State private var newGestureName     = ""
    @State private var editingGestureID:  UUID? = nil
    @State private var showResetAlert           = false
    @State private var tapDisplayIntensity:     Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            mainContent
            Divider()
            footer
        }
        .frame(width: 360)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.tap.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            Text("Slapppy")
                .font(.system(size: 15, weight: .semibold))
            Spacer()
            statusBadge
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var statusBadge: some View {
        HStack(spacing: 5) {
            Circle()
                .frame(width: 7, height: 7)
                .foregroundStyle(trackpad.isListening ? Color.green : Color.secondary)
            Group {
                if !trackpad.isListening {
                    Text("Arrêté")
                } else if mode == 1 {
                    Text("⌥ + mouv.")
                } else {
                    Text("⌥ + tap")
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .animation(.easeInOut(duration: 0.15), value: mode)
            if mode == 0, trackpad.tapCount > 0 {
                Text("· \(trackpad.tapCount)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Main content

    private var mainContent: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Mode switcher
            Picker("", selection: $mode) {
                Label("Slaps", systemImage: "hand.tap.fill").tag(0)
                Label("Gestes", systemImage: "scribble").tag(1)
                Image(systemName: "gearshape").tag(2)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 6)

            if mode == 0 {
                slapsContent
            } else if mode == 1 {
                gesturesContent
            } else {
                settingsContent
            }

            // Match feedback — always visible regardless of active tab
            if let match = engine.lastMatchedPattern {
                Divider()
                matchBadge(name: match.name, score: engine.lastMatchScore,
                           icon: "checkmark.circle.fill")
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .transition(.opacity.combined(with: .push(from: .bottom)))
            }
            if let match = gestureEngine.lastMatchedTemplate {
                Divider()
                matchBadge(name: match.name, score: gestureEngine.lastMatchScore,
                           icon: "scribble.variable")
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .transition(.opacity.combined(with: .push(from: .bottom)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: engine.lastMatchedPattern?.id)
        .animation(.easeInOut(duration: 0.2), value: gestureEngine.lastMatchedTemplate?.id)
    }

    // MARK: - Slaps tab

    private var slapsContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            recorderSection
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

            if !store.patterns.isEmpty {
                Divider()
                patternList
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
        }
    }

    // MARK: - Gestures tab

    private var gesturesContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            gestureRecorderSection
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

            if !gestureStore.templates.isEmpty {
                Divider()
                gestureList
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
        }
    }

    // MARK: - Settings tab

    @ViewBuilder
    private var settingsContent: some View {
        @Bindable var s = settings
        VStack(alignment: .leading, spacing: 0) {
            settingsGroup("Patterns") {
                settingRow("Seuil de match", value: $s.patternThreshold, in: 0.50...1.0,
                           display: "\(Int(s.patternThreshold * 100))%")
                    .help("Score de similarité minimum pour déclencher l'action. Plus bas = plus permissif, mais plus de faux positifs.")
                settingRow("Tolérance timing", value: $s.timingTolerance, in: 0.10...0.60,
                           display: "±\(Int(s.timingTolerance * 100))%")
                    .help("Variation autorisée sur les intervalles entre slaps. À 30 %, un écart de ±30 % sur le rythme est accepté.")
                tapMeter
            }
            Divider()
            settingsGroup("Gestes") {
                settingRow("Seuil de match", value: $s.gestureThreshold, in: 0.50...1.0,
                           display: "\(Int(s.gestureThreshold * 100))%")
                    .help("Score de ressemblance minimum. La vitesse, la taille et l'orientation sont ignorées — seule la forme compte.")
                settingRow("Longueur min", value: $s.minGesturePathLength, in: 10.0...100.0,
                           display: "\(Int(s.minGesturePathLength)) pt")
                    .help("Déplacement minimum (en points écran) pour qu'un tracé soit traité comme un geste, et non comme un simple clic.")
            }
            Divider()
            settingsGroup("Général") {
                settingRow("Délai anti-double", value: $s.matchCooldown, in: 0.5...3.0,
                           display: String(format: "%.1f s", s.matchCooldown))
                    .help("Délai après un match avant que le même pattern ou geste puisse se déclencher à nouveau. Évite les répétitions involontaires.")
            }
            Divider()
            if showResetAlert {
                HStack(spacing: 8) {
                    Text("Réinitialiser ?")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Annuler") { showResetAlert = false }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Button("Confirmer") { settings.reset(); showResetAlert = false }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .tint(.red)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .transition(.opacity.combined(with: .push(from: .bottom)))
            } else {
                Button("Réinitialiser les réglages") {
                    withAnimation(.easeInOut(duration: 0.15)) { showResetAlert = true }
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: showResetAlert)
    }

    @ViewBuilder
    private func settingsGroup<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func settingRow(_ label: String, value: Binding<Double>,
                            in range: ClosedRange<Double>, display: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 12))
                Spacer()
                Text(display)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
                .controlSize(.small)
        }
    }

    // MARK: - Live tap meter

    private var tapMeter: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("Frappe live")
                    .font(.system(size: 12))
                Spacer()
                if trackpad.lastTapIntensity > 0 {
                    Text("\(Int(trackpad.lastTapIntensity))")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(.quaternary).frame(height: 6)
                    let norm = min(1, max(0, (tapDisplayIntensity - 400) / 800))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.accentColor)
                        .frame(width: geo.size.width * norm, height: 6)
                }
            }
            .frame(height: 6)
            Text("Maintiens ⌥ et frappe le trackpad")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .onChange(of: trackpad.tapCount) { _, _ in
            // Montée instantanée
            withAnimation(.spring(response: 0.08, dampingFraction: 0.7)) {
                tapDisplayIntensity = trackpad.lastTapIntensity
            }
            // Descente progressive après 200 ms
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation(.easeOut(duration: 0.9)) {
                    tapDisplayIntensity = 0
                }
            }
        }
    }

    // MARK: - Shared match badge

    private func matchBadge(name: String, score: Double, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.green)
                .font(.system(size: 14))
            Text(name)
                .font(.system(size: 13, weight: .medium))
            Spacer()
            Text("\(Int(score * 100))%")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Recorder section (slaps)

    @ViewBuilder
    private var recorderSection: some View {
        switch recorder.state {

        case .idle:
            Button {
                recorder.startRecording()
            } label: {
                Label("Enregistrer un pattern", systemImage: "plus.circle")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)

        case .recording:
            HStack {
                Label("Tape ton pattern…", systemImage: "record.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(.red)
                Spacer()
                cancelButton { recorder.discard() }
            }

        case .active:
            HStack(spacing: 8) {
                slapDots(recorder.slapEvents, color: .red)
                Image(systemName: "ellipsis")
                    .foregroundStyle(.secondary)
                    .font(.caption2)
                Spacer()
                cancelButton { recorder.discard() }
            }

        case .captured:
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    slapDots(recorder.slapEvents, color: Color.accentColor)
                    Text("\(recorder.slapCount) slaps")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    TextField("Nom du pattern", text: $newPatternName)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13))
                        .onSubmit { savePattern() }
                    Button("Sauver", action: savePattern)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
                Button("Annuler") { recorder.discard(); newPatternName = "" }
                    .font(.system(size: 12))
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func savePattern() {
        if let p = recorder.build(name: newPatternName) { store.add(p) }
        newPatternName = ""
    }

    // MARK: - Gesture recorder section

    @ViewBuilder
    private var gestureRecorderSection: some View {
        switch gestureRecorder.state {

        case .idle:
            VStack(alignment: .leading, spacing: 5) {
                Button {
                    gestureRecorder.startRecording()
                } label: {
                    Label("Enregistrer un geste", systemImage: "plus.circle")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)

                Text("Maintiens ⌥ et bouge la souris")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Text("Forme uniquement — vitesse, taille et orientation ignorées")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

        case .recording:
            HStack {
                Label("Maintiens ⌥ et dessine…", systemImage: "record.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(.red)
                Spacer()
                cancelButton { gestureRecorder.discard() }
            }

        case .captured:
            VStack(alignment: .leading, spacing: 10) {
                gesturePathPreview(gestureRecorder.capturedDisplayPoints.isEmpty
                    ? gestureRecorder.capturedPoints
                    : gestureRecorder.capturedDisplayPoints, side: 100)
                Text("\(gestureRecorder.capturedPoints.count) pts capturés")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                HStack(spacing: 6) {
                    TextField("Nom du geste", text: $newGestureName)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13))
                        .onSubmit { saveGesture() }
                    Button("Sauver", action: saveGesture)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
                Button("Annuler") { gestureRecorder.discard(); newGestureName = "" }
                    .font(.system(size: 12))
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func saveGesture() {
        if let t = gestureRecorder.build(name: newGestureName) { gestureStore.add(t) }
        newGestureName = ""
    }

    // MARK: - Cancel button helper

    private func cancelButton(action: @escaping () -> Void) -> some View {
        Button("Annuler", action: action)
            .font(.system(size: 12))
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
    }

    // MARK: - Pattern list

    private var patternList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Patterns")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.bottom, 8)

            ForEach(store.patterns) { pattern in
                VStack(alignment: .leading, spacing: 0) {
                    patternRow(pattern)
                    if editingPatternID == pattern.id {
                        ActionEditorView(
                            name: Binding(
                                get: { store.patterns.first { $0.id == pattern.id }?.name ?? "" },
                                set: { store.rename(id: pattern.id, to: $0) }
                            ),
                            action: store.patterns.first { $0.id == pattern.id }?.action ?? .none,
                            setAction: { store.setAction($0, forID: pattern.id) },
                            onDismiss: { withAnimation(.easeInOut(duration: 0.18)) { editingPatternID = nil } }
                        )
                        .padding(.top, 6)
                        .padding(.bottom, 4)
                        .transition(.opacity.combined(with: .push(from: .top)))
                    }
                }
                .animation(.easeInOut(duration: 0.18), value: editingPatternID)
            }
        }
    }

    private func patternRow(_ pattern: Pattern) -> some View {
        HStack(spacing: 6) {
            slapDots(pattern.slaps, color: .secondary)
            Text(pattern.name)
                .font(.system(size: 13))
                .lineLimit(1)
            Spacer()
            if let label = actionSummary(pattern.action) {
                HStack(spacing: 4) {
                    if let icon = actionIcon(pattern.action) {
                        Image(nsImage: icon).resizable().frame(width: 14, height: 14)
                    }
                    Text(label)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                .frame(maxWidth: 100, alignment: .trailing)
            }
            editToggle(id: pattern.id, binding: $editingPatternID)
            deleteButton { store.remove(id: pattern.id); if editingPatternID == pattern.id { editingPatternID = nil } }
        }
        .padding(.vertical, 5)
    }

    // MARK: - Gesture list

    private var gestureList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Gestes")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.bottom, 8)

            ForEach(gestureStore.templates) { template in
                VStack(alignment: .leading, spacing: 0) {
                    gestureRow(template)
                    if editingGestureID == template.id {
                        ActionEditorView(
                            name: Binding(
                                get: { gestureStore.templates.first { $0.id == template.id }?.name ?? "" },
                                set: { gestureStore.rename(id: template.id, to: $0) }
                            ),
                            action: gestureStore.templates.first { $0.id == template.id }?.action ?? .none,
                            setAction: { gestureStore.setAction($0, forID: template.id) },
                            onDismiss: { withAnimation(.easeInOut(duration: 0.18)) { editingGestureID = nil } }
                        )
                        .padding(.top, 6)
                        .padding(.bottom, 4)
                        .transition(.opacity.combined(with: .push(from: .top)))
                    }
                }
                .animation(.easeInOut(duration: 0.18), value: editingGestureID)
            }
        }
    }

    private func gestureRow(_ template: GestureTemplate) -> some View {
        HStack(spacing: 6) {
            gesturePathPreview(template.displayPath.isEmpty ? template.path : template.displayPath)
            Text(template.name)
                .font(.system(size: 13))
                .lineLimit(1)
            Spacer()
            if let label = actionSummary(template.action) {
                HStack(spacing: 4) {
                    if let icon = actionIcon(template.action) {
                        Image(nsImage: icon).resizable().frame(width: 14, height: 14)
                    }
                    Text(label)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                .frame(maxWidth: 100, alignment: .trailing)
            }
            editToggle(id: template.id, binding: $editingGestureID)
            deleteButton { gestureStore.remove(id: template.id); if editingGestureID == template.id { editingGestureID = nil } }
        }
        .padding(.vertical, 5)
    }

    // MARK: - Gesture path preview

    private func gesturePathPreview(_ points: [GesturePoint], side: CGFloat = 42) -> some View {
        Canvas { ctx, size in
            guard points.count >= 2 else { return }

            // Fit the gesture's bounding box into the canvas
            let xs     = points.map(\.x),  ys     = points.map(\.y)
            let minX   = xs.min()!,        maxX   = xs.max()!
            let minY   = ys.min()!,        maxY   = ys.max()!
            let rangeX = maxX - minX,      rangeY = maxY - minY
            let range  = max(rangeX, rangeY, 1.0)
            let pad    = Double(min(size.width, size.height)) * 0.12
            let avail  = Double(min(size.width, size.height)) - 2 * pad
            let scale  = avail / range
            let midX   = (minX + maxX) / 2
            let midY   = (minY + maxY) / 2
            let cx     = Double(size.width)  / 2
            let cy     = Double(size.height) / 2

            func pt(_ p: GesturePoint) -> CGPoint {
                CGPoint(x: cx + (p.x - midX) * scale,
                        y: cy - (p.y - midY) * scale)
            }

            // Stroke — Catmull-Rom spline so curves stay smooth regardless of drawing speed
            var path = Path()
            let screenPts = points.map { pt($0) }
            let n = screenPts.count
            path.move(to: screenPts[0])
            for i in 1..<n {
                let p0 = screenPts[max(0, i - 2)]
                let p1 = screenPts[i - 1]
                let p2 = screenPts[i]
                let p3 = screenPts[min(n - 1, i + 1)]
                let cp1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6.0,
                                  y: p1.y + (p2.y - p0.y) / 6.0)
                let cp2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6.0,
                                  y: p2.y - (p3.y - p1.y) / 6.0)
                path.addCurve(to: p2, control1: cp1, control2: cp2)
            }
            ctx.stroke(path, with: .color(Color.accentColor), lineWidth: side > 42 ? 2.0 : 1.5)

            // Start — filled circle
            let start = pt(points[0])
            let dotR: Double = side > 42 ? 3.5 : 2.5
            var startDot = Path()
            startDot.addEllipse(in: CGRect(x: start.x - dotR, y: start.y - dotR,
                                           width: dotR * 2, height: dotR * 2))
            ctx.fill(startDot, with: .color(Color.accentColor))

            // End — ring
            let end = pt(points[points.count - 1])
            var endDot = Path()
            endDot.addEllipse(in: CGRect(x: end.x - dotR, y: end.y - dotR,
                                         width: dotR * 2, height: dotR * 2))
            ctx.stroke(endDot, with: .color(Color.accentColor), lineWidth: 1.5)
        }
        .frame(width: side, height: side)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: side > 42 ? 10 : 6))
    }

    // MARK: - Action icon

    private func actionIcon(_ action: PatternAction) -> NSImage? {
        guard case .launchApp(let bundleID, _) = action,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    // MARK: - Action summary

    private func actionSummary(_ action: PatternAction) -> String? {
        switch action {
        case .none:
            return nil
        case .virtualKey(let keyCode):
            let map: [UInt16: String] = [105: "F13", 107: "F14", 113: "F15",
                                         106: "F16",  64: "F17",  79: "F18",
                                          80: "F19",  90: "F20"]
            return map[keyCode] ?? "F?"
        case .typeText(let t):
            let line = t.components(separatedBy: .newlines)
                        .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? ""
            guard !line.isEmpty else { return nil }
            return line.count > 22 ? String(line.prefix(22)) + "…" : line
        case .launchApp(_, let appName):
            return appName.isEmpty ? nil : appName
        }
    }

    // MARK: - Row button helpers

    private func editToggle(id: UUID, binding: Binding<UUID?>) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                binding.wrappedValue = binding.wrappedValue == id ? nil : id
            }
        } label: {
            Image(systemName: binding.wrappedValue == id ? "chevron.up" : "slider.horizontal.3")
                .font(.system(size: 11))
                .foregroundStyle(binding.wrappedValue == id ? Color.accentColor : .secondary)
        }
        .buttonStyle(.plain)
    }

    private func deleteButton(action: @escaping () -> Void) -> some View {
        Button {
            withAnimation { action() }
        } label: {
            Image(systemName: "trash")
                .font(.system(size: 11))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(
                get: { SMAppService.mainApp.status == .enabled },
                set: { on in
                    do {
                        if on { try SMAppService.mainApp.register() }
                        else  { try SMAppService.mainApp.unregister() }
                    } catch { print("[Slapppy] Login item: \(error)") }
                }
            )) { Text("Lancer au démarrage") }
                .toggleStyle(.checkbox)
                .font(.system(size: 12))

            if !trackpad.isInputMonitoringGranted {
                warningButton("Input Monitoring requis") { trackpad.requestInputMonitoring() }
            }
            if !trackpad.isAccessibilityGranted {
                warningButton("Accessibilité requise") { trackpad.requestAccessibility() }
            }

            HStack {
                Button("Vérifier les mises à jour") { updater.checkForUpdates() }
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
                Spacer()
                Button("Quitter") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func warningButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.orange)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Slap dots

    private func slapDots(_ events: [SlapEvent], color: Color) -> some View {
        let maxI = events.map(\.intensity).max() ?? 1
        return HStack(spacing: 3) {
            ForEach(events.prefix(8).indices, id: \.self) { i in
                let norm = maxI > 0 ? events[i].intensity / maxI : 0.5
                let size = CGFloat(6 + norm * 8)
                Circle()
                    .frame(width: size, height: size)
                    .foregroundStyle(color)
            }
        }
    }

}

// MARK: - PatternAction helpers

private extension PatternAction {
    var isVirtualKey: Bool { if case .virtualKey = self { return true }; return false }
    var isTypeText:   Bool { if case .typeText   = self { return true }; return false }
    var isLaunchApp:  Bool { if case .launchApp  = self { return true }; return false }
}

// MARK: - AppEntry

private struct AppEntry: Identifiable {
    let id:   String  // bundleID
    let name: String
    let url:  URL

    static func loadAll() -> [AppEntry] {
        let dirs: [String] = [
            "/Applications",
            "/System/Applications",
            "/System/Applications/Utilities",
            "/Applications/Utilities",
            NSString(string: "~/Applications").expandingTildeInPath
        ]
        var seen    = Set<String>()
        var entries = [AppEntry]()
        for dir in dirs {
            guard let urls = try? FileManager.default.contentsOfDirectory(
                at: URL(fileURLWithPath: dir), includingPropertiesForKeys: nil
            ) else { continue }
            for url in urls where url.pathExtension == "app" {
                let plist = url.appendingPathComponent("Contents/Info.plist")
                guard let info     = NSDictionary(contentsOf: plist),
                      let bundleID = info["CFBundleIdentifier"] as? String,
                      !seen.contains(bundleID) else { continue }
                let name = info["CFBundleDisplayName"] as? String
                    ?? info["CFBundleName"] as? String
                    ?? url.deletingPathExtension().lastPathComponent
                seen.insert(bundleID)
                entries.append(AppEntry(id: bundleID, name: name, url: url))
            }
        }
        return entries.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

private struct TextHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

// MARK: - ActionEditorView

/// Inline editor for renaming a pattern/gesture and assigning an action.
/// Name and typeText fields buffer their values locally and only commit
/// to the store on Enter or focus loss. A ✓ button appears when the
/// buffer differs from the saved value.
private struct ActionEditorView: View {

    let name:      Binding<String>
    let action:    PatternAction
    let setAction: (PatternAction) -> Void
    let onDismiss: () -> Void

    @State private var nameBuffer: String
    @State private var textBuffer: String
    @FocusState private var nameFocused:  Bool
    @FocusState private var textFocused:  Bool
    @State private var appSearch:         String     = ""
    @State private var textEditorHeight:  CGFloat    = 60
    @State private var installedApps:     [AppEntry] = []
    @State private var selectedBundleID:  String     = ""
    @State private var selectedAppName:   String     = ""

    private let fKeys: [(label: String, code: UInt16)] = [
        ("F13", 105), ("F14", 107), ("F15", 113),
        ("F16", 106), ("F17", 64),  ("F18", 79),
        ("F19", 80),  ("F20", 90)
    ]

    init(name: Binding<String>, action: PatternAction,
         setAction: @escaping (PatternAction) -> Void,
         onDismiss: @escaping () -> Void) {
        self.name      = name
        self.action    = action
        self.setAction = setAction
        self.onDismiss = onDismiss
        _nameBuffer    = State(initialValue: name.wrappedValue)
        if case .typeText(let t) = action {
            _textBuffer = State(initialValue: t)
        } else {
            _textBuffer = State(initialValue: "")
        }
        if case .launchApp(let bid, let appN) = action {
            _selectedBundleID = State(initialValue: bid)
            _selectedAppName  = State(initialValue: appN)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {

            // Name — saves on Enter or focus loss
            HStack(spacing: 4) {
                TextField("Nom", text: $nameBuffer)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .focused($nameFocused)
                    .onSubmit { commitName() }
                    .onChange(of: nameFocused) { _, focused in
                        if !focused { commitName() }
                    }
                if nameBuffer != name.wrappedValue {
                    Button { commitName(); onDismiss() } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }

            // Action type picker
            Picker("", selection: Binding(
                get: { actionTag },
                set: { tag in
                    switch tag {
                    case 1: setAction(action.isVirtualKey ? action : .virtualKey(keyCode: 105))
                    case 2: setAction(action.isTypeText  ? action : .typeText(textBuffer))
                    case 3: setAction(action.isLaunchApp ? action : .launchApp(bundleID: "", appName: ""))
                    default: setAction(.none)
                    }
                }
            )) {
                Text("—").tag(0)
                Text("Touche").tag(1)
                Text("Texte").tag(2)
                Text("App").tag(3)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            // Action-specific field
            switch action {
            case .virtualKey(let keyCode):
                Picker("", selection: Binding(
                    get: { keyCode },
                    set: { setAction(.virtualKey(keyCode: $0)) }
                )) {
                    ForEach(fKeys, id: \.code) { k in Text(k.label).tag(k.code) }
                }
                .labelsHidden()

            case .typeText(let saved):
                VStack(alignment: .trailing, spacing: 4) {
                    ZStack(alignment: .topLeading) {
                        // Placeholder
                        if textBuffer.isEmpty {
                            Text("Texte à écrire…")
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 8)
                                .allowsHitTesting(false)
                        }
                        // Hidden text that drives auto-height
                        Text(textBuffer.isEmpty ? " " : textBuffer)
                            .font(.system(size: 12))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .opacity(0)
                            .background {
                                GeometryReader { geo in
                                    Color.clear.preference(
                                        key: TextHeightKey.self,
                                        value: geo.size.height
                                    )
                                }
                            }
                        TextEditor(text: $textBuffer)
                            .font(.system(size: 12))
                            .scrollContentBackground(.hidden)
                            .focused($textFocused)
                            .onChange(of: textFocused) { _, focused in
                                if !focused { commitText() }
                            }
                    }
                    .onPreferenceChange(TextHeightKey.self) { h in
                        textEditorHeight = max(60, min(400, h))
                    }
                    .frame(height: textEditorHeight)
                    .background(.background, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator, lineWidth: 0.5))

                    if textBuffer != saved {
                        Button { commitText(); onDismiss() } label: {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }

            case .launchApp:
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Rechercher une app…", text: $appSearch)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                    ScrollView {
                        if installedApps.isEmpty {
                            HStack {
                                Spacer()
                                Text("Chargement…")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .padding(.vertical, 10)
                        }
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(filteredApps) { app in
                                HStack(spacing: 6) {
                                    Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                                        .resizable()
                                        .frame(width: 16, height: 16)
                                    Text(app.name)
                                        .font(.system(size: 12))
                                        .lineLimit(1)
                                    Spacer()
                                    if app.id == selectedBundleID {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedBundleID = app.id
                                    selectedAppName  = app.name
                                }
                                .padding(.horizontal, 4)
                                .padding(.vertical, 4)
                                .background(
                                    app.id == selectedBundleID
                                        ? Color.accentColor.opacity(0.1) : .clear,
                                    in: RoundedRectangle(cornerRadius: 4)
                                )
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .frame(minHeight: 120, maxHeight: 220)
                    .background(.background, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator, lineWidth: 0.5))

                }

            case .none:
                EmptyView()
            }

            HStack {
                Button("Annuler") {
                    nameBuffer = name.wrappedValue
                    if case .typeText(let t) = action { textBuffer = t }
                    if case .launchApp(let bid, let appN) = action {
                        selectedBundleID = bid
                        selectedAppName  = appN
                    } else {
                        selectedBundleID = ""
                        selectedAppName  = ""
                    }
                    onDismiss()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Spacer()
                if hasPendingAppChange {
                    Button("Sauver") {
                        setAction(.launchApp(bundleID: selectedBundleID, appName: selectedAppName))
                        onDismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        }
        .font(.system(size: 12))
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        .onChange(of: name.wrappedValue) { _, newName in
            if !nameFocused { nameBuffer = newName }
        }
        .onChange(of: action) { _, newAction in
            if case .typeText(let t) = newAction, !textFocused { textBuffer = t }
            if case .launchApp(let bid, let appN) = newAction {
                selectedBundleID = bid
                selectedAppName  = appN
            }
        }
        .task {
            guard installedApps.isEmpty else { return }
            installedApps = AppEntry.loadAll()
        }
    }

    private var hasPendingAppChange: Bool {
        guard case .launchApp(let savedID, _) = action else { return false }
        return !selectedBundleID.isEmpty && selectedBundleID != savedID
    }

    private var filteredApps: [AppEntry] {
        appSearch.isEmpty ? installedApps
            : installedApps.filter { $0.name.localizedCaseInsensitiveContains(appSearch) }
    }

    private var actionTag: Int {
        switch action {
        case .none:       return 0
        case .virtualKey: return 1
        case .typeText:   return 2
        case .launchApp:  return 3
        }
    }

    private func commitName() {
        name.wrappedValue = nameBuffer.trimmingCharacters(in: .whitespaces)
    }

    private func commitText() {
        setAction(.typeText(textBuffer))
    }
}
