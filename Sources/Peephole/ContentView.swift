import SwiftUI
import AppKit

struct ContentView: View {
    @Environment(PeepholeStore.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            header
            pills
            Divider()
            list
            Divider()
            footer
        }
        .frame(width: 380, height: 520)
    }

    private var header: some View {
        HStack(alignment: .center) {
            HStack(alignment: .center, spacing: 6) {
                Image(systemName: store.cameraActive || store.micActive
                      ? "eye.fill" : "eye.trianglebadge.exclamationmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(store.cameraActive || store.micActive ? .red : .primary)
                Text("PEEPHOLE")
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(2)
                LiveDot()
            }
            Spacer()
            Text(store.cameraActive || store.micActive ? "WATCHING" : "ALL CLEAR")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(store.cameraActive || store.micActive ? .red : .secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var pills: some View {
        HStack(spacing: 10) {
            StatusPill(title: "Camera", icon: "camera.fill", active: store.cameraActive)
            StatusPill(title: "Microphone", icon: "mic.fill", active: store.micActive)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if store.events.isEmpty {
                    VStack(spacing: 6) {
                        Text("No camera or microphone use recorded yet.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Text("Peephole watches the unified log every few seconds.")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 220)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(store.events.enumerated()), id: \.element.id) { index, event in
                            EventRow(
                                event: event,
                                highlighted: store.focusedKey == event.id
                            )
                            .id(event.id)
                            if index < store.events.count - 1 {
                                Divider()
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
            .onChange(of: store.focusedKey) { _, key in
                guard let key else { return }
                withAnimation { proxy.scrollTo(key, anchor: .center) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    if store.focusedKey == key { store.focusedKey = nil }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button {
                store.clearHistory()
            } label: {
                Label("Clear history", systemImage: "trash")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            Spacer()
            Button("Quit Peephole") {
                NSApplication.shared.terminate(nil)
            }
            .font(.system(size: 11))
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

private struct StatusPill: View {
    let title: String
    let icon: String
    let active: Bool

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
            Text(title)
                .font(.system(size: 12, weight: .semibold))
            Spacer()
            Circle()
                .fill(active ? Color.red : Color.secondary.opacity(0.4))
                .frame(width: 8, height: 8)
        }
        .foregroundStyle(active ? Color.red : Color.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(active ? Color.red.opacity(0.12) : Color.secondary.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(active ? Color.red.opacity(0.35) : Color.white.opacity(0.06), lineWidth: 1)
        )
    }
}

private struct EventRow: View {
    let event: UsageEvent
    let highlighted: Bool

    private var deviceIcon: String {
        event.device == .camera ? "camera.fill" : "mic.fill"
    }

    private var appLabel: String {
        if let app = event.app, !app.isEmpty { return app }
        return "Unknown app"
    }

    private var startText: String {
        let f = DateFormatter()
        f.dateFormat = "MMM d, HH:mm:ss"
        return f.string(from: event.start)
    }

    private var durationText: String {
        if event.isActive { return "active now" }
        let secs = Int((event.end ?? event.start).timeIntervalSince(event.start))
        if secs < 60 { return "\(max(secs, 0))s" }
        let m = secs / 60, s = secs % 60
        return "\(m)m \(s)s"
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: deviceIcon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(event.isActive ? Color.red : Color.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(appLabel)
                        .font(.system(size: 12, weight: .semibold))
                    if event.app == nil {
                        Text("heuristic")
                            .font(.system(size: 8, weight: .medium))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.15))
                            .foregroundStyle(.secondary)
                            .clipShape(Capsule())
                    }
                }
                Text("\(event.device == .camera ? "Camera" : "Microphone")  ·  \(startText)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()

            Text(durationText)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(event.isActive ? Color.red : Color.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(highlighted ? Color.red.opacity(0.16) : Color.clear)
        .animation(.easeInOut(duration: 0.25), value: highlighted)
        .contentShape(Rectangle())
    }
}

private struct LiveDot: View {
    @State private var on = false

    var body: some View {
        Circle()
            .fill(Color.green)
            .frame(width: 6, height: 6)
            .opacity(on ? 1 : 0.25)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
            .help("Live — polling the unified log every few seconds")
    }
}
