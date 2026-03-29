//
//  ContentView.swift
//  Slappy
//
//  Created by Arsène Laurent on 28/03/2026.
//

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

    @State private var mode               = 0       // 0 = Slaps, 1 = Gestes
    @State private var newPatternName     = ""
    @State private var editingPatternID:  UUID? = nil
    @State private var newGestureName     = ""
    @State private var editingGestureID:  UUID? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            mainContent
            Divider()
            footer
        }
        .frame(width: 280)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.tap.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            Text("Slapppy")
                .font(.system(size: 14, weight: .semibold))
            Spacer()
            statusBadge
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var statusBadge: some View {
        HStack(spacing: 5) {
            Circle()
                .frame(width: 6, height: 6)
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
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .animation(.easeInOut(duration: 0.15), value: mode)
            if mode == 0, trackpad.tapCount > 0 {
                Text("· \(trackpad.tapCount)")
                    .font(.system(size: 11, design: .monospaced))
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
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 4)

            if mode == 0 {
                slapsContent
            } else {
                gesturesContent
            }

            // Match feedback — always visible regardless of active tab
            if let match = engine.lastMatchedPattern {
                Divider()
                matchBadge(name: match.name, score: engine.lastMatchScore,
                           icon: "checkmark.circle.fill")
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .transition(.opacity.combined(with: .push(from: .bottom)))
            }
            if let match = gestureEngine.lastMatchedTemplate {
                Divider()
                matchBadge(name: match.name, score: gestureEngine.lastMatchScore,
                           icon: "scribble.variable")
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
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
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

            if !store.patterns.isEmpty {
                Divider()
                patternList
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }
        }
    }

    // MARK: - Gestures tab

    private var gesturesContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            gestureRecorderSection
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

            if !gestureStore.templates.isEmpty {
                Divider()
                gestureList
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }
        }
    }

    // MARK: - Shared match badge

    private func matchBadge(name: String, score: Double, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.green)
                .font(.system(size: 13))
            Text(name)
                .font(.system(size: 12, weight: .medium))
            Spacer()
            Text("\(Int(score * 100))%")
                .font(.system(size: 11, design: .monospaced))
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
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)

        case .recording:
            HStack {
                Label("Tape ton pattern…", systemImage: "record.circle")
                    .font(.system(size: 12))
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
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    slapDots(recorder.slapEvents, color: Color.accentColor)
                    Text("\(recorder.slapCount) slaps")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    TextField("Nom du pattern", text: $newPatternName)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                        .onSubmit { savePattern() }
                    Button("Sauver", action: savePattern)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
                Button("Annuler") { recorder.discard(); newPatternName = "" }
                    .font(.system(size: 11))
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
            VStack(alignment: .leading, spacing: 4) {
                Button {
                    gestureRecorder.startRecording()
                } label: {
                    Label("Enregistrer un geste", systemImage: "plus.circle")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)

                Text("Maintiens ⌥ et bouge la souris")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

        case .recording:
            HStack {
                Label("Maintiens ⌥ et dessine…", systemImage: "record.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                Spacer()
                cancelButton { gestureRecorder.discard() }
            }

        case .captured:
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    gesturePathPreview(gestureRecorder.capturedDisplayPoints.isEmpty
                        ? gestureRecorder.capturedPoints
                        : gestureRecorder.capturedDisplayPoints)
                    Text("\(gestureRecorder.capturedPoints.count) pts capturés")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    TextField("Nom du geste", text: $newGestureName)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                        .onSubmit { saveGesture() }
                    Button("Sauver", action: saveGesture)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
                Button("Annuler") { gestureRecorder.discard(); newGestureName = "" }
                    .font(.system(size: 11))
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
            .font(.system(size: 11))
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
    }

    // MARK: - Pattern list

    private var patternList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Patterns")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.bottom, 6)

            ForEach(store.patterns) { pattern in
                VStack(alignment: .leading, spacing: 0) {
                    patternRow(pattern)
                    if editingPatternID == pattern.id {
                        actionEditor(
                            name: Binding(
                                get: { store.patterns.first { $0.id == pattern.id }?.name ?? "" },
                                set: { store.rename(id: pattern.id, to: $0) }
                            ),
                            action: store.patterns.first { $0.id == pattern.id }?.action ?? .none,
                            setAction: { store.setAction($0, forID: pattern.id) }
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
                .font(.system(size: 12))
                .lineLimit(1)
            Spacer()
            if pattern.action != .none {
                Circle().frame(width: 5, height: 5).foregroundStyle(Color.accentColor)
            }
            editToggle(id: pattern.id, binding: $editingPatternID)
            deleteButton { store.remove(id: pattern.id); if editingPatternID == pattern.id { editingPatternID = nil } }
        }
        .padding(.vertical, 3)
    }

    // MARK: - Gesture list

    private var gestureList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Gestes")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.bottom, 6)

            ForEach(gestureStore.templates) { template in
                VStack(alignment: .leading, spacing: 0) {
                    gestureRow(template)
                    if editingGestureID == template.id {
                        actionEditor(
                            name: Binding(
                                get: { gestureStore.templates.first { $0.id == template.id }?.name ?? "" },
                                set: { gestureStore.rename(id: template.id, to: $0) }
                            ),
                            action: gestureStore.templates.first { $0.id == template.id }?.action ?? .none,
                            setAction: { gestureStore.setAction($0, forID: template.id) }
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
                .font(.system(size: 12))
                .lineLimit(1)
            Spacer()
            if template.action != .none {
                Circle().frame(width: 5, height: 5).foregroundStyle(Color.accentColor)
            }
            editToggle(id: template.id, binding: $editingGestureID)
            deleteButton { gestureStore.remove(id: template.id); if editingGestureID == template.id { editingGestureID = nil } }
        }
        .padding(.vertical, 3)
    }

    // MARK: - Gesture path preview

    private func gesturePathPreview(_ points: [GesturePoint]) -> some View {
        Canvas { ctx, size in
            guard points.count >= 2 else { return }
            let s  = Double(min(size.width, size.height)) / 250.0 * 0.85
            let cx = Double(size.width)  / 2
            let cy = Double(size.height) / 2

            var path = Path()
            path.move(to: CGPoint(x: cx + points[0].x * s, y: cy - points[0].y * s))
            for pt in points.dropFirst() {
                path.addLine(to: CGPoint(x: cx + pt.x * s, y: cy - pt.y * s))
            }
            ctx.stroke(path, with: .color(Color.accentColor), lineWidth: 1.5)
        }
        .frame(width: 36, height: 36)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
    }

    // MARK: - Shared action editor (used for both patterns and gestures)

    private func actionEditor(
        name: Binding<String>,
        action: PatternAction,
        setAction: @escaping (PatternAction) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Nom", text: name)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))

            Picker("", selection: Binding(
                get: { actionTag(action) },
                set: { tag in
                    switch tag {
                    case 1: setAction(action.isVirtualKey ? action : .virtualKey(keyCode: 105))
                    case 2: setAction(action.isTypeText  ? action : .typeText(""))
                    default: setAction(.none)
                    }
                }
            )) {
                Text("—").tag(0)
                Text("Touche").tag(1)
                Text("Texte").tag(2)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch action {
            case .virtualKey(let keyCode):
                Picker("", selection: Binding(
                    get: { keyCode },
                    set: { setAction(.virtualKey(keyCode: $0)) }
                )) {
                    ForEach(fKeys, id: \.code) { k in
                        Text(k.label).tag(k.code)
                    }
                }
                .labelsHidden()

            case .typeText(let text):
                TextField("Texte à écrire", text: Binding(
                    get: { text },
                    set: { setAction(.typeText($0)) }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))

            case .none:
                EmptyView()
            }
        }
        .font(.system(size: 11))
        .padding(8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Row button helpers

    private func editToggle(id: UUID, binding: Binding<UUID?>) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                binding.wrappedValue = binding.wrappedValue == id ? nil : id
            }
        } label: {
            Image(systemName: binding.wrappedValue == id ? "chevron.up" : "slider.horizontal.3")
                .font(.system(size: 10))
                .foregroundStyle(binding.wrappedValue == id ? Color.accentColor : .secondary)
        }
        .buttonStyle(.plain)
    }

    private func deleteButton(action: @escaping () -> Void) -> some View {
        Button {
            withAnimation { action() }
        } label: {
            Image(systemName: "trash")
                .font(.system(size: 10))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
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
                .font(.system(size: 11))

            if !trackpad.isInputMonitoringGranted {
                warningButton("Input Monitoring requis") { trackpad.requestInputMonitoring() }
            }
            if !trackpad.isAccessibilityGranted {
                warningButton("Accessibilité requise") { trackpad.requestAccessibility() }
            }

            HStack {
                Button("Vérifier les mises à jour") { updater.checkForUpdates() }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
                Spacer()
                Button("Quitter") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func warningButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
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
                let size = CGFloat(5 + norm * 7)
                Circle()
                    .frame(width: size, height: size)
                    .foregroundStyle(color)
            }
        }
    }

    // MARK: - F-key table + helpers

    private let fKeys: [(label: String, code: UInt16)] = [
        ("F13", 105), ("F14", 107), ("F15", 113),
        ("F16", 106), ("F17", 64),  ("F18", 79),
        ("F19", 80),  ("F20", 90)
    ]

    private func actionTag(_ action: PatternAction) -> Int {
        switch action {
        case .none:       return 0
        case .virtualKey: return 1
        case .typeText:   return 2
        }
    }
}

// MARK: - PatternAction helpers

private extension PatternAction {
    var isVirtualKey: Bool { if case .virtualKey = self { return true }; return false }
    var isTypeText:   Bool { if case .typeText   = self { return true }; return false }
}
