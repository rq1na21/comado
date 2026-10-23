import SwiftUI

/// ルーム一覧。各ルームの窓の今の様子を並べる
struct RoomListView: View {
    @State private var rooms = Store.loadRooms()
    @State private var naming = false
    @State private var newName = ""
    /// 窓から戻ったときにサムネイルを今の状態で描き直す
    @State private var shownAt = Date.now

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 20), GridItem(.flexible(), spacing: 20)],
                          spacing: 24) {
                    ForEach(rooms) { room in
                        NavigationLink(value: room) {
                            RoomCard(room: room, now: shownAt)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("削除", systemImage: "trash", role: .destructive) { delete(room) }
                        }
                    }
                }
                .padding(24)
            }
            .overlay {
                if rooms.isEmpty {
                    Text("右上の ＋ でルームを作ろう").font(.system(size: 15, weight: .light)).foregroundStyle(.secondary)
                }
            }
            .safeAreaInset(edge: .top) {
                HStack {
                    Text("comado").font(.system(size: 22, weight: .light)).foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        newName = ""
                        naming = true
                    } label: {
                        Label("ルームを作る", systemImage: "plus").softButton()
                    }
                    .disabled(rooms.count >= Store.maxRooms)
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
            }
            .background(Color(white: 0.97))
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Room.self) { RoomView(room: $0) }
            .onAppear {
                shownAt = .now
                Store.saveRooms(rooms) // App Group 側の一覧を最新に
            }
            .alert("ルームの名前", isPresented: $naming) {
                TextField("名前", text: $newName)
                Button("作成") { create() }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("あとから変えられません")
            }
        }
    }

    private func create() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, rooms.count < Store.maxRooms else { return }
        rooms.append(Room(name: name))
        Store.saveRooms(rooms)
    }

    private func delete(_ room: Room) {
        rooms.removeAll { $0.id == room.id }
        Store.saveRooms(rooms)
        Store.delete(room)
    }
}

/// すりガラスの縁にはめた小さな窓と、ルーム名
private struct RoomCard: View {
    let room: Room
    let now: Date

    var body: some View {
        VStack(spacing: 10) {
            WindowView(strokes: Store.loadStrokes(room), background: Store.loadBackground(room), now: now)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(8)
                .background {
                    let bezel = RoundedRectangle(cornerRadius: 22, style: .continuous)
                    bezel.fill(.white)
                        .overlay(bezel.strokeBorder(.black.opacity(0.04), lineWidth: 1))
                        .shadow(color: .black.opacity(0.06), radius: 14, y: 6)
                }
            Text(room.name).font(.system(size: 14, weight: .light)).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}

extension View {
    /// silua 風の白い角丸ボタン
    nonisolated func softButton() -> some View {
        labelStyle(.iconOnly)
            .font(.system(size: 17, weight: .light))
            .foregroundStyle(.secondary)
            .frame(width: 52, height: 52)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.white.opacity(0.85))
                    .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
            }
    }
}
