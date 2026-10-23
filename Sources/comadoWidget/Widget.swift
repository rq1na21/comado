import WidgetKit
import SwiftUI
import AppIntents
import os

@main struct ComadoWidgetBundle: WidgetBundle {
    var body: some Widget {
        ComadoWidget()
    }
}

struct ComadoWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "ComadoWidget", intent: SelectRoomIntent.self, provider: Provider()) { entry in
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
        .description("窓の様子を表示します。長押し →「ウィジェットを編集」で窓を選べます。")
    }

    struct Entry: TimelineEntry {
        var date = Date()
        var image: UIImage?
    }

    /// アプリが App Group に書き出した「snapshot-<ルーム ID>-<UNIX 時刻>.jpg」を、その時刻のエントリとして並べる
    struct Provider: AppIntentTimelineProvider {
        func placeholder(in context: Context) -> Entry { Entry() }

        func snapshot(for configuration: SelectRoomIntent, in context: Context) async -> Entry {
            entries(for: configuration).last { $0.date <= .now } ?? Entry()
        }

        func timeline(for configuration: SelectRoomIntent, in context: Context) async -> Timeline<Entry> {
            let entries = entries(for: configuration)
            return Timeline(entries: entries.isEmpty ? [Entry()] : entries, policy: .never)
        }

        private func entries(for configuration: SelectRoomIntent) -> [Entry] {
            // 未設定なら一覧の先頭の窓
            guard let dir = Shared.directory,
                  let roomID = configuration.room?.id ?? Shared.rooms().first?.id,
                  let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            else { return [] }
            let prefix = "snapshot-\(roomID)-"
            return files.compactMap { url -> Entry? in
                let name = url.deletingPathExtension().lastPathComponent
                guard name.hasPrefix(prefix), let time = TimeInterval(name.dropFirst(prefix.count)) else { return nil }
                return Entry(date: Date(timeIntervalSince1970: time), image: UIImage(contentsOfFile: url.path()))
            }
            .sorted { $0.date < $1.date }
        }
    }
}

/// 「ウィジェットを編集」で窓（ルーム）を選ぶ
struct SelectRoomIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "窓を選ぶ"

    @Parameter(title: "窓")
    var room: RoomEntity?
}

struct RoomEntity: AppEntity {
    let id: String
    let name: String

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "窓"
    static let defaultQuery = RoomQuery()
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct RoomQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [RoomEntity] {
        Shared.rooms().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [RoomEntity] {
        Shared.rooms()
    }
}

/// アプリと共有する App Group の中身
enum Shared {
    /// アプリ側の Snapshots.directory と同じ場所。ウィジェットの bundle ID はアプリの ID + ".comadoWidget"
    static var directory: URL? {
        guard let id = Bundle.main.bundleIdentifier else { return nil }
        let appID = id.replacingOccurrences(of: ".comadoWidget", with: "")
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group." + appID)
    }

    private struct Room: Decodable {
        let id: UUID
        let name: String
    }

    static func rooms() -> [RoomEntity] {
        guard let url = directory?.appending(path: "rooms.json"),
              let data = try? Data(contentsOf: url),
              let rooms = try? JSONDecoder().decode([Room].self, from: data) else { return [] }
        return rooms.map { RoomEntity(id: $0.id.uuidString, name: $0.name) }
    }
}
