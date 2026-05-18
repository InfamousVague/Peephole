import Foundation

enum UsageDevice: String, Hashable, Sendable {
    case camera
    case microphone
}

/// One open/close transition derived from the unified log.
struct UsageTransition: Sendable {
    let device: UsageDevice
    let active: Bool          // true = stream started, false = stream stopped
    let token: String         // stable stream/context id, used to pair start↔stop
    let app: String?          // best-effort responsible app; nil = "unknown"
    let date: Date
}

/// Reads the unified log (`/usr/bin/log show --style ndjson`) and turns
/// camera / microphone stream start & stop messages into `UsageTransition`s.
///
/// This is best-effort and entitlement-free: it observes Apple's own logging,
/// which is undocumented and varies by macOS version. Responsible-app
/// attribution is heuristic — the log frequently only names the system
/// assistant daemon, in which case `app` is left nil ("unknown").
enum UsageMonitor {
    /// Query the last `window` seconds of log and return ordered transitions.
    static func poll(window: TimeInterval) -> [UsageTransition] {
        let seconds = max(2, Int(window.rounded(.up)))
        guard let lines = runLogShow(lastSeconds: seconds) else { return [] }

        var out: [UsageTransition] = []
        for line in lines {
            guard let data = line.data(using: .utf8),
                  let entry = try? JSONDecoder().decode(LogEntry.self, from: data) else { continue }
            if let t = transition(from: entry) { out.append(t) }
        }
        out.sort { $0.date < $1.date }
        return out
    }

    // MARK: - log show invocation

    private static func runLogShow(lastSeconds: Int) -> [String]? {
        let predicate = """
        (subsystem == "com.apple.cmio" OR subsystem == "com.apple.coreaudio" \
        OR processImagePath ENDSWITH "coreaudiod" \
        OR processImagePath CONTAINS "UVCAssistant" \
        OR senderImagePath CONTAINS "appleh13camera") \
        AND (eventMessage CONTAINS "CMIO_DAL_CMIOExtension_Stream" \
        OR eventMessage CONTAINS "Post event kCameraStream" \
        OR eventMessage CONTAINS "HALS_IOEngine2::_StartIO" \
        OR eventMessage CONTAINS "HALS_IOEngine2::_StopIO" \
        OR eventMessage CONTAINS "client starting" \
        OR eventMessage CONTAINS "client stopping" \
        OR eventMessage CONTAINS "StartStream" \
        OR eventMessage CONTAINS "StopStream")
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        process.arguments = [
            "show",
            "--style", "ndjson",
            "--last", "\(lastSeconds)s",
            "--predicate", predicate,
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        return text.split(separator: "\n").map(String.init)
    }

    // MARK: - parsing

    private struct LogEntry: Decodable {
        let subsystem: String?
        let eventMessage: String?
        let processImagePath: String?
        let senderImagePath: String?
        let timestamp: String?
    }

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSSZ"
        return f
    }()

    private static func parseDate(_ raw: String?) -> Date {
        guard let raw else { return Date() }
        return timestampFormatter.date(from: raw) ?? Date()
    }

    /// Maps one log line to a transition, or nil if it isn't a start/stop we
    /// can interpret. Camera signal comes from CoreMediaIO's DAL stream
    /// Start/Stop; microphone signal from coreaudiod's input IO engine.
    private static func transition(from e: LogEntry) -> UsageTransition? {
        guard let msg = e.eventMessage else { return nil }
        let date = parseDate(e.timestamp)
        let isCMIO = (e.subsystem == "com.apple.cmio")
            || msg.contains("CMIO_DAL_CMIOExtension_Stream")

        if isCMIO {
            // e.g. "CMIO_DAL_CMIOExtension_Stream.mm:3194:Stop (streamID 90 89 0)"
            if let r = msg.range(of: "Start ("), let id = streamID(in: msg, after: r.upperBound) {
                return UsageTransition(device: .camera, active: true,
                                       token: "cam:\(id)", app: app(from: e), date: date)
            }
            if let r = msg.range(of: "Stop ("), let id = streamID(in: msg, after: r.upperBound) {
                return UsageTransition(device: .camera, active: false,
                                       token: "cam:\(id)", app: app(from: e), date: date)
            }
            if msg.contains("StartStream") {
                return UsageTransition(device: .camera, active: true,
                                       token: "cam:\(streamFallback(msg))", app: app(from: e), date: date)
            }
            if msg.contains("StopStream") {
                return UsageTransition(device: .camera, active: false,
                                       token: "cam:\(streamFallback(msg))", app: app(from: e), date: date)
            }
            return nil
        }

        // Microphone: only treat *input* IO engine start/stop as mic activity.
        // coreaudiod logs output devices on the same paths, so require an
        // input/recording hint to avoid counting speaker playback as "mic".
        let lower = msg.lowercased()
        let looksInput = lower.contains("input") || lower.contains("vpio")
            || lower.contains("vpau") || lower.contains("microphone")
            || lower.contains("record")

        if msg.contains("HALS_IOEngine2::_StartIO") && looksInput {
            return UsageTransition(device: .microphone, active: true,
                                   token: "mic:\(contextID(in: msg))", app: app(from: e), date: date)
        }
        if msg.contains("HALS_IOEngine2::_StopIO") && looksInput {
            return UsageTransition(device: .microphone, active: false,
                                   token: "mic:\(contextID(in: msg))", app: app(from: e), date: date)
        }
        if msg.contains("client starting") && looksInput {
            return UsageTransition(device: .microphone, active: true,
                                   token: "mic:\(streamFallback(msg))", app: app(from: e), date: date)
        }
        if msg.contains("client stopping") && looksInput {
            return UsageTransition(device: .microphone, active: false,
                                   token: "mic:\(streamFallback(msg))", app: app(from: e), date: date)
        }
        return nil
    }

    /// First integer run after `Start (` / `Stop (`, e.g. "90" in
    /// "Stop (streamID 90 89 0)".
    private static func streamID(in s: String, after idx: String.Index) -> String? {
        let tail = s[idx...]
        let digits = tail.drop { !$0.isNumber }.prefix { $0.isNumber }
        return digits.isEmpty ? nil : String(digits)
    }

    /// "Context 273" → "273" for the audio IO engine.
    private static func contextID(in s: String) -> String {
        if let r = s.range(of: "Context ") {
            let d = s[r.upperBound...].prefix { $0.isNumber }
            if !d.isEmpty { return String(d) }
        }
        return streamFallback(s)
    }

    /// Last resort token: a short stable hash of the message sans timestamps.
    private static func streamFallback(_ s: String) -> String {
        let stripped = s.filter { !$0.isNumber }
        return String(UInt(bitPattern: stripped.hashValue) % 100000)
    }

    /// Derive a human app name from the responsible process path. The log
    /// usually names a system daemon, not the real client — return nil there
    /// so the UI honestly shows "unknown" rather than "coreaudiod".
    private static func app(from e: LogEntry) -> String? {
        for path in [e.processImagePath, e.senderImagePath] {
            guard let path, !path.isEmpty else { continue }
            let name = (path as NSString).lastPathComponent
            let systemDaemons: Set<String> = [
                "coreaudiod", "com.apple.cmio.registerassistantservice",
                "cmio_dalassistant", "UVCAssistant", "appleh13camerad",
                "avconferenced", "mediaserverd", "com.apple.audio.SandboxHelper",
            ]
            if systemDaemons.contains(name) { continue }
            if path.contains(".app/") {
                if let r = path.range(of: ".app/") {
                    let appPath = String(path[..<r.lowerBound])
                    return (appPath as NSString).lastPathComponent
                }
            }
            return name
        }
        return nil
    }
}
