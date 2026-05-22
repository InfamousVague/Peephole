import WidgetKit
import PeepholeShared

struct PeepholeEntry: TimelineEntry {
    let date: Date
    let state: SharedPeephole
    var isStale: Bool {
        Date().timeIntervalSince(state.sampledAt) > 30
    }
}

struct PeepholeProvider: TimelineProvider {
    func placeholder(in context: Context) -> PeepholeEntry {
        PeepholeEntry(date: .now, state: SharedPeephole())
    }
    func getSnapshot(in context: Context,
                     completion: @escaping (PeepholeEntry) -> Void)
    {
        completion(PeepholeEntry(
            date: .now, state: SharedPeepholeStore.read()))
    }
    func getTimeline(in context: Context,
                     completion: @escaping (Timeline<PeepholeEntry>) -> Void)
    {
        let entry = PeepholeEntry(
            date: .now, state: SharedPeepholeStore.read())
        // 30s heartbeat — host writes invalidate sooner.
        let next = Date().addingTimeInterval(30)
        completion(Timeline(entries: [entry],
                            policy: .after(next)))
    }
}
