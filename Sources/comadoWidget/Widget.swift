import WidgetKit
import SwiftUI

@main struct ComadoWidgetBundle: WidgetBundle {
    var body: some Widget {
        ComadoWidget()
    }
}

struct ComadoWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ComadoWidget", provider: Provider()) { entry in
            Text(entry.date, style: .time)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("comado")
        .description("窓の様子を表示します。")
    }

    struct Entry: TimelineEntry {
        var date = Date()
    }

    struct Provider: TimelineProvider {
        func placeholder(in context: Context) -> Entry { Entry() }

        func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
            completion(Entry())
        }

        // ponytail: 固定で15分ごと。中身(窓の状態)の共有はフェーズ2で App Group 経由に
        func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
            completion(Timeline(entries: [Entry()], policy: .after(.now + 15 * 60)))
        }
    }
}
