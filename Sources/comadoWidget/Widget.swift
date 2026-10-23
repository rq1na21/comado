import WidgetKit
import SwiftUI
import os

@main struct ComadoWidgetBundle: WidgetBundle {
    var body: some Widget {
        ComadoWidget()
    }
}

struct ComadoWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ComadoWidget", provider: Provider()) { entry in
            Group {
                if let image = entry.image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Text("comado を開くと窓が映ります").font(.caption).padding()
                }
            }
            .containerBackground(.fill.tertiary, for: .widget)
        }
        .contentMarginsDisabled()
        .supportedFamilies([.systemSmall, .systemLarge]) // 窓は正方形
        .configurationDisplayName("comado")
        .description("窓の様子を表示します。")
    }

    struct Entry: TimelineEntry {
        var date = Date()
        var image: UIImage?
    }

    /// アプリが App Group に書き出した「snapshot-<UNIX 時刻>.jpg」を、その時刻のエントリとして並べる
    struct Provider: TimelineProvider {
        func placeholder(in context: Context) -> Entry { Entry() }

        func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
            completion(entries().last { $0.date <= .now } ?? Entry())
        }

        func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
            let entries = entries()
            completion(Timeline(entries: entries.isEmpty ? [Entry()] : entries, policy: .never))
        }

        private func entries() -> [Entry] {
            guard let dir = snapshotDirectory,
                  let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            else {
                Logger().error("comado widget: App Group を読めない \(String(describing: snapshotDirectory), privacy: .public)")
                return []
            }
            Logger().info("comado widget: \(files.count) 件 \(dir.path(), privacy: .public)")
            return files.compactMap { url -> Entry? in
                let name = url.deletingPathExtension().lastPathComponent
                guard name.hasPrefix("snapshot-"), let time = TimeInterval(name.dropFirst("snapshot-".count)) else { return nil }
                return Entry(date: Date(timeIntervalSince1970: time), image: UIImage(contentsOfFile: url.path()))
            }
            .sorted { $0.date < $1.date }
        }

        /// アプリ側の Snapshots.directory と同じ場所。ウィジェットの bundle ID はアプリの ID + ".comadoWidget"
        private var snapshotDirectory: URL? {
            guard let id = Bundle.main.bundleIdentifier else { return nil }
            let appID = id.replacingOccurrences(of: ".comadoWidget", with: "")
            return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group." + appID)
        }
    }
}
