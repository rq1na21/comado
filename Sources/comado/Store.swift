import UIKit

/// ルーム。フェーズ 2 で CloudKit の共有ゾーン 1 つに対応させる
struct Room: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
}

/// 端末内の保存。ルームごとに線と背景を分けて持つ
enum Store {
    static let maxRooms = 5
    private static let dir = URL.documentsDirectory
    private static let roomsURL = dir.appending(path: "rooms.json")

    static func loadRooms() -> [Room] {
        if let data = try? Data(contentsOf: roomsURL), let rooms = try? JSONDecoder().decode([Room].self, from: data) {
            return rooms
        }
        // ルーム導入前の 1 枚だけの窓の背景を、最初のルームに引き継ぐ
        let legacy = dir.appending(path: "background")
        guard FileManager.default.fileExists(atPath: legacy.path()) else { return [] }
        let room = Room(name: "はじめての窓")
        try? FileManager.default.moveItem(at: legacy, to: backgroundURL(room))
        saveRooms([room])
        return [room]
    }

    static func saveRooms(_ rooms: [Room]) {
        guard let data = try? JSONEncoder().encode(rooms) else { return }
        try? data.write(to: roomsURL)
        // ウィジェットの「窓を選ぶ」の候補に出すため App Group にも置く
        if let shared = Snapshots.directory { try? data.write(to: shared.appending(path: "rooms.json")) }
    }

    static func delete(_ room: Room) {
        try? FileManager.default.removeItem(at: strokesURL(room))
        try? FileManager.default.removeItem(at: backgroundURL(room))
        Snapshots.remove(room)
    }

    static func loadStrokes(_ room: Room) -> [Stroke] {
        guard let data = try? Data(contentsOf: strokesURL(room)),
              let strokes = try? JSONDecoder().decode([Stroke].self, from: data) else { return [] }
        return strokes.filter { Date.now.timeIntervalSince($0.date) <= fadeDuration }
    }

    static func saveStrokes(_ strokes: [Stroke], _ room: Room) {
        try? JSONEncoder().encode(strokes).write(to: strokesURL(room))
    }

    static func loadBackground(_ room: Room) -> UIImage? {
        UIImage(contentsOfFile: backgroundURL(room).path())
    }

    static func saveBackground(_ data: Data, _ room: Room) {
        try? data.write(to: backgroundURL(room))
    }

    private static func strokesURL(_ room: Room) -> URL { dir.appending(path: "strokes-\(room.id).json") }
    private static func backgroundURL(_ room: Room) -> URL { dir.appending(path: "background-\(room.id)") }
}
