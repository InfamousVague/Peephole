import WidgetKit
import SwiftUI
import PeepholeShared

/// Peephole status widget — read-only "is anything watching/listening?"
/// surface. No buttons (toggling devices requires privileged access
/// that the sandboxed widget extension doesn't have).
struct PeepholeStatusWidget: Widget {
    let kind: String = "PeepholeStatusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PeepholeProvider()) {
            entry in
            PeepholeWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Peephole Status")
        .description("Camera + microphone activity at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

struct PeepholeWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PeepholeEntry

    var body: some View {
        switch family {
        case .systemSmall:  SmallView(entry: entry)
        case .systemMedium: MediumView(entry: entry)
        default:            SmallView(entry: entry)
        }
    }
}
