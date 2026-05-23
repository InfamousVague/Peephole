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
        Group {
            switch family {
            case .systemSmall:  SmallView(entry: entry)
            case .systemMedium: MediumView(entry: entry)
            default:            SmallView(entry: entry)
            }
        }
        // Desktop-widget tap → MattsSoftware launcher's URL
        // handler pops its popover already switched to the
        // Peephole pane. Without this hook tapping the widget
        // launches Peephole's standalone bundle id, SuiteGuard
        // exits in merged mode, and nothing visible happens.
        .widgetURL(URL(string: "mattssoftware://peephole"))
    }
}
