import SwiftUI
import WidgetKit
import os
import PhotosUI
import _PhotosUI_SwiftUI // xtool では cross-import overlay が自動で効かないため明示

/// 拭った跡が完全に曇り直すまでの時間（デバッグビルドは確認しやすいよう1分）
#if DEBUG
let fadeDuration: TimeInterval = 60
#else
let fadeDuration: TimeInterval = 60 * 60
#endif

struct Stroke: Codable {
    var points: [CGPoint] // 画面サイズに依存しないよう 0...1 に正規化
    var date: Date
}

/// 1 つのルームの窓。ここで描く
struct RoomView: View {
    let room: Room
    @State private var strokes: [Stroke]
    @State private var current: Stroke?
    @State private var background: UIImage?
    @State private var pickerItem: PhotosPickerItem?
    @Environment(\.scenePhase) private var scenePhase
    @State private var snapshotTask: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss

    init(room: Room) {
        self.room = room
        _strokes = State(initialValue: Store.loadStrokes(room))
        _background = State(initialValue: Store.loadBackground(room))
    }

    var body: some View {
        // 窓は正方形。端末の画面の形が違っても、線の形とウィジェットでの見え方が同じになる
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            WindowView(strokes: current.map { strokes + [$0] } ?? strokes, background: background, now: timeline.date)
        }
        .aspectRatio(1, contentMode: .fit)
        .overlay {
            GeometryReader { geo in
                Color.clear.contentShape(Rectangle()).gesture(drawGesture(geo.size))
            }
        }
        // 拭っている手応え。なぞった距離に応じて軽く震える
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.4), trigger: (current?.points.count ?? 0) / 8)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            // ガラスの縁の細いハイライト
            RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.7), lineWidth: 1)
        }
        .padding(14)
        .background {
            // すりガラスの白い縁に窓をはめ込む
            let bezel = RoundedRectangle(cornerRadius: 34, style: .continuous)
            bezel.fill(.white.opacity(0.45))
                .background(.ultraThinMaterial, in: bezel)
                .overlay(bezel.strokeBorder(.white.opacity(0.9), lineWidth: 1))
                .shadow(color: .black.opacity(0.08), radius: 24, y: 12)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            // 窓のまわりは、同じ景色をぼかして広げる
            Group {
                if let background {
                    Image(uiImage: background).resizable().scaledToFill()
                } else {
                    LinearGradient(colors: [.indigo, .orange], startPoint: .top, endPoint: .bottom)
                }
            }
            .blur(radius: 50, opaque: true)
            .overlay(Color(white: 0.97).opacity(0.6)) // 明るく空気感のあるオフホワイトに寄せる
            .ignoresSafeArea()
        }
        .overlay(alignment: .top) {
            HStack {
                Button { dismiss() } label: {
                    Label("ルーム一覧に戻る", systemImage: "chevron.left").softButton()
                }
                Spacer()
                Text(room.name).font(.system(size: 17, weight: .light)).foregroundStyle(.secondary)
                Spacer()
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label("背景の写真を選ぶ", systemImage: "photo").softButton()
                }
            }
            .padding(24)
        }
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: scenePhase) { _, phase in
            // バックグラウンドに回ってからの更新依頼は iOS に低優先として捨てられるので、見えているうちに
            if phase == .inactive { saveSnapshots() }
        }
        .onChange(of: pickerItem) { _, item in
            Task {
                guard let data = try? await item?.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else { return }
                background = image
                Store.saveBackground(data, room)
            }
        }
    }

    /// ウィジェット用に、今から曇りきるまでの窓を数枚描いておく。
    /// アプリを閉じていてもウィジェットの中で曇り直しが進む
    private func saveSnapshots() {
        guard let dir = Snapshots.directory else {
            Logger().error("comado: App Group が使えないのでスナップショットを書き出せない")
            return
        }
        Snapshots.remove(room)
        for step in 0...4 {
            let date = Date.now + fadeDuration * Double(step) / 4
            let renderer = ImageRenderer(content: WindowView(strokes: strokes, background: background, now: date)
                .frame(width: 360, height: 360))
            renderer.scale = 1.5
            guard let data = renderer.uiImage?.jpegData(compressionQuality: 0.8) else { continue }
            try? data.write(to: dir.appending(path: "snapshot-\(room.id)-\(Int(date.timeIntervalSince1970)).jpg"))
        }
        Logger().info("comado: スナップショットを書き出した \(dir.path(), privacy: .public)")
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func drawGesture(_ size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let point = CGPoint(x: value.location.x / size.width, y: value.location.y / size.height)
                if current == nil { current = Stroke(points: [], date: .now) }
                current?.points.append(point)
            }
            .onEnded { _ in
                if let current { strokes.append(current) }
                current = nil
                // 描き終えて少し落ち着いたらウィジェットにも反映（続けて描く間は待つ）
                snapshotTask?.cancel()
                snapshotTask = Task {
                    guard (try? await Task.sleep(for: .seconds(1))) != nil else { return }
                    saveSnapshots()
                }
                strokes.removeAll { Date.now.timeIntervalSince($0.date) > fadeDuration }
                Store.saveStrokes(strokes, room)
            }
    }
}

/// 窓の見た目。アプリの画面と、ウィジェット用のスナップショットの両方で使う
struct WindowView: View {
    let strokes: [Stroke]
    let background: UIImage?
    let now: Date

    var body: some View {
        GeometryReader { geo in
            ZStack {
                backgroundView(geo.size)
                ZStack {
                    backgroundView(geo.size).blur(radius: 30, opaque: true)
                    Color.white.opacity(0.45)
                    Condensation(seed: 1).equatable()
                }
                .mask { fogMask(now: now) }
                waterOverlay(now: now)
                glass
            }
        }
    }

    @ViewBuilder
    private func backgroundView(_ size: CGSize) -> some View {
        Group {
            if let background {
                Image(uiImage: background).resizable().scaledToFill()
            } else {
                LinearGradient(colors: [.indigo, .orange], startPoint: .top, endPoint: .bottom)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    /// 曇りの層を残す部分が黒。拭った線は新しいほど濃く抜き、時間とともに曇りが戻る
    private func fogMask(now: Date) -> some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
            ctx.blendMode = .destinationOut
            let all = strokes.filter { clearness($0, now: now) > 0 }
            // 指の跡は縁を柔らかく
            ctx.drawLayer { layer in
                layer.addFilter(.blur(radius: 6))
                for stroke in all {
                    var path = Path()
                    path.addLines(stroke.points.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) })
                    layer.opacity = clearness(stroke, now: now)
                    layer.stroke(path, with: .color(.black),
                                 style: StrokeStyle(lineWidth: 22, lineCap: .round, lineJoin: .round))
                }
            }
            // 指の腹で拭っても薄い水の膜が筋状に残る
            ctx.blendMode = .normal
            ctx.drawLayer { layer in
                layer.addFilter(.blur(radius: 0.8))
                for stroke in all {
                    var path = Path()
                    path.addLines(stroke.points.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) })
                    layer.opacity = 0.15 * clearness(stroke, now: now)
                    for offset in [-6.5, -3.0, 2.0, 5.5] {
                        layer.stroke(path.offsetBy(dx: offset * 0.6, dy: offset), with: .color(.black), lineWidth: 1.2)
                    }
                }
            }
        }
    }

    /// 拭った跡の縁にたまった水
    private func waterOverlay(now: Date) -> some View {
        Canvas { ctx, size in
            let all = strokes
            // 後から拭った線が、前の線の縁の水を拭い取る
            ctx.drawLayer { layer in
                layer.addFilter(.blur(radius: 1.5))
                for stroke in all {
                    let alpha = clearness(stroke, now: now)
                    guard alpha > 0 else { continue }
                    var path = Path()
                    path.addLines(stroke.points.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) })
                    layer.opacity = alpha
                    layer.blendMode = .normal
                    layer.stroke(path, with: .color(.white.opacity(0.12)),
                                 style: StrokeStyle(lineWidth: 24, lineCap: .round, lineJoin: .round))
                    layer.blendMode = .destinationOut
                    layer.stroke(path, with: .color(.black),
                                 style: StrokeStyle(lineWidth: 20, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .allowsHitTesting(false)
    }

    /// ガラスの立体感: 枠に沿った奥の影と、斜めに入る光の映り込み
    private var glass: some View {
        ZStack {
            Rectangle()
                .strokeBorder(.black.opacity(0.15), lineWidth: 8)
                .blur(radius: 6)
            LinearGradient(stops: [
                .init(color: .clear, location: 0.22),
                .init(color: .white.opacity(0.22), location: 0.32),
                .init(color: .clear, location: 0.42),
                .init(color: .white.opacity(0.12), location: 0.5),
                .init(color: .clear, location: 0.56),
            ], startPoint: .topLeading, endPoint: .bottomTrailing)
            .blendMode(.screen)
        }
        .clipped()
        .allowsHitTesting(false)
    }

    /// 拭った跡の透明度。しばらくはクリアなまま、終盤で一気に曇る
    private func clearness(_ stroke: Stroke, now: Date) -> Double {
        let t = now.timeIntervalSince(stroke.date) / fadeDuration
        return 1 - t * t * t
    }
}

/// 水玉。縁は屈折で暗く、上に光の反射、下側に集まった光
func drawBead(_ ctx: GraphicsContext, in rect: CGRect) {
    let center = CGPoint(x: rect.midX, y: rect.midY)
    ctx.fill(Path(ellipseIn: rect), with: .radialGradient(
        Gradient(stops: [.init(color: .clear, location: 0.55),
                         .init(color: .black.opacity(0.25), location: 1)]),
        center: center, startRadius: 0, endRadius: rect.height / 2))
    ctx.fill(Path(ellipseIn: rect.insetBy(dx: rect.width * 0.2, dy: rect.height * 0.28)
                                 .offsetBy(dx: 0, dy: rect.height * 0.17)),
             with: .color(.white.opacity(0.25)))
    ctx.fill(Path(ellipseIn: CGRect(x: rect.minX + rect.width * 0.22, y: rect.minY + rect.height * 0.17,
                                    width: rect.width * 0.25, height: rect.height * 0.17)),
             with: .color(.white.opacity(0.9)))
}

/// 曇りの正体の細かい水滴と、ところどころの大きめの水玉。
/// 数千個描くので、Equatable で毎フレームの再描画を避ける
struct Condensation: View, Equatable {
    let seed: UInt64

    var body: some View {
        Canvas { ctx, size in
            var rng = SplitMix64(state: seed)
            // 目に見えないほど細かい粒が密集した、マットなざらつき
            let count = Int(size.width * size.height / 25)
            for _ in 0..<count {
                let r = CGFloat.random(in: 0.3...0.8, using: &rng)
                let p = CGPoint(x: .random(in: 0...size.width, using: &rng),
                                y: .random(in: 0...size.height, using: &rng))
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                         with: .color(.white.opacity(.random(in: 0.05...0.15, using: &rng))))
            }
            for _ in 0..<(count / 600) {
                let r = CGFloat.random(in: 1.5...3.5, using: &rng)
                let p = CGPoint(x: .random(in: 0...size.width, using: &rng),
                                y: .random(in: 0...size.height, using: &rng))
                drawBead(ctx, in: CGRect(x: p.x - r, y: p.y - r * 1.1, width: r * 2, height: r * 2.2))
            }
        }
        .allowsHitTesting(false)
    }
}

/// 起動のたびに水滴の配置が変わらないよう、シード付きの乱数
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// アプリとウィジェットで共有する置き場所 (App Group)。
/// 窓の画像は「snapshot-<ルーム ID>-<UNIX 時刻>.jpg」
enum Snapshots {
    static func remove(_ room: Room) {
        guard let dir = directory else { return }
        let fm = FileManager.default
        for old in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        where old.lastPathComponent.hasPrefix("snapshot-\(room.id)-") {
            try? fm.removeItem(at: old)
        }
    }

    /// xtool は App Group の ID を「group.<書き換え後のアプリの bundle ID>」にするので、自分の bundle ID から組み立てる
    static var directory: URL? {
        guard let appID = Bundle.main.bundleIdentifier else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group." + appID)
    }
}
