import SwiftUI
import WidgetKit
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
    var drips: [Drip] = []
}

/// 線から垂れる水滴。拭った筋が下へ伸びていく
struct Drip: Codable {
    var start: CGPoint
    var length: CGFloat       // 画面の高さに対する割合
    var delay: TimeInterval   // stroke.date から垂れ始めるまで
    var duration: TimeInterval
}

struct ContentView: View {
    @State private var strokes = Store.loadStrokes()
    @State private var current: Stroke?
    @State private var background = Store.loadBackground()
    @State private var pickerItem: PhotosPickerItem?
    /// 水滴が垂れ終わる時刻。それまでは滑らかに、以降は曇り直しに足りる 1 秒ごとに描き直す
    @State private var animateUntil = Date.distantPast
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: animateUntil > .now ? 1.0 / 30 : 1)) { timeline in
                WindowView(strokes: current.map { strokes + [$0] } ?? strokes, background: background, now: timeline.date)
            }
            .contentShape(Rectangle())
            .gesture(drawGesture(geo.size))
            // 拭っている手応え。なぞった距離に応じて軽く震える
            .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.4), trigger: (current?.points.count ?? 0) / 8)
        }
        .task(id: animateUntil) {
            // 垂れ終わったら描き直しの頻度を落とす
            guard animateUntil > .now,
                  (try? await Task.sleep(for: .seconds(animateUntil.timeIntervalSinceNow))) != nil else { return }
            animateUntil = .distantPast
        }
        .ignoresSafeArea()
        .overlay(alignment: .bottomTrailing) {
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label("背景の写真を選ぶ", systemImage: "photo")
                    .labelStyle(.iconOnly)
                    .padding()
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { saveSnapshots() }
        }
        .onChange(of: pickerItem) { _, item in
            Task {
                guard let data = try? await item?.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else { return }
                background = image
                Store.saveBackground(data)
            }
        }
    }

    /// ウィジェット用に、今から曇りきるまでの窓を数枚描いておく。
    /// アプリを閉じていてもウィジェットの中で曇り直しが進む
    private func saveSnapshots() {
        guard let dir = Snapshots.directory else { return }
        let fm = FileManager.default
        for old in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        where old.lastPathComponent.hasPrefix("snapshot-") {
            try? fm.removeItem(at: old)
        }
        for step in 0...4 {
            let date = Date.now + fadeDuration * Double(step) / 4
            // ponytail: 画面サイズは固定。ウィジェットは中央を切り抜いて表示するので十分
            let renderer = ImageRenderer(content: WindowView(strokes: strokes, background: background, now: date)
                .frame(width: 390, height: 844))
            guard let data = renderer.uiImage?.jpegData(compressionQuality: 0.8) else { continue }
            try? data.write(to: dir.appending(path: "snapshot-\(Int(date.timeIntervalSince1970)).jpg"))
        }
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
                if var stroke = current {
                    stroke.drips = makeDrips(for: stroke)
                    strokes.append(stroke)
                    if let end = stroke.drips.map({ stroke.date + $0.delay + $0.duration }).max() {
                        animateUntil = max(animateUntil, end)
                    }
                }
                current = nil
                strokes.removeAll { Date.now.timeIntervalSince($0.date) > fadeDuration }
                Store.saveStrokes(strokes)
            }
    }

    /// 長くなぞった線ほど垂れやすい。タップ程度では垂れない
    private func makeDrips(for stroke: Stroke) -> [Drip] {
        let endedAt = Date.now.timeIntervalSince(stroke.date)
        guard stroke.points.count >= 20 else { return [] }
        let count = Int.random(in: 1...2)
        return (0..<count).map { _ in
            Drip(start: stroke.points.randomElement()!,
                 length: .random(in: 0.04...0.2),
                 delay: endedAt + .random(in: 0...3),
                 duration: .random(in: 4...10))
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
                                 style: StrokeStyle(lineWidth: 28, lineCap: .round, lineJoin: .round))
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
                    for offset in [-8.0, -3.5, 2.5, 7.0] {
                        layer.stroke(path.offsetBy(dx: offset * 0.6, dy: offset), with: .color(.black), lineWidth: 1.2)
                    }
                }
            }
            ctx.blendMode = .destinationOut
            // 水滴は細いので、強くぼかすと拭えずに見えなくなる
            ctx.drawLayer { layer in
                layer.addFilter(.blur(radius: 1.5))
                for stroke in all {
                    layer.opacity = clearness(stroke, now: now)
                    for drip in stroke.drips {
                        guard let (top, bottom) = dripSegment(drip, of: stroke, now: now, size: size) else { continue }
                        var trail = Path()
                        trail.move(to: top)
                        trail.addLine(to: bottom)
                        layer.stroke(trail, with: .color(.black), style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        layer.fill(Path(ellipseIn: beadRect(at: bottom)), with: .color(.black))
                    }
                }
            }
        }
    }

    /// 拭った跡の縁にたまった水と、垂れる水滴の先端の水玉
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
                                 style: StrokeStyle(lineWidth: 30, lineCap: .round, lineJoin: .round))
                    layer.blendMode = .destinationOut
                    layer.stroke(path, with: .color(.black),
                                 style: StrokeStyle(lineWidth: 26, lineCap: .round, lineJoin: .round))
                }
            }
            for stroke in strokes {
                let alpha = clearness(stroke, now: now)
                guard alpha > 0 else { continue }
                ctx.opacity = alpha
                for drip in stroke.drips {
                    guard let (_, center) = dripSegment(drip, of: stroke, now: now, size: size) else { continue }
                    drawBead(ctx, in: beadRect(at: center))
                }
            }
        }
        .allowsHitTesting(false)
    }

    /// 水滴の筋の上端と、今の先端の位置。まだ垂れ始めていなければ nil
    private func dripSegment(_ drip: Drip, of stroke: Stroke, now: Date, size: CGSize) -> (CGPoint, CGPoint)? {
        let progress = min((now.timeIntervalSince(stroke.date) - drip.delay) / drip.duration, 1)
        guard progress > 0 else { return nil }
        // 最初は速く、だんだん止まる
        let grown = drip.length * (1 - (1 - progress) * (1 - progress))
        let top = CGPoint(x: drip.start.x * size.width, y: drip.start.y * size.height)
        return (top, CGPoint(x: top.x, y: top.y + grown * size.height))
    }

    /// 重みで少し縦長になった水玉
    private func beadRect(at center: CGPoint) -> CGRect {
        CGRect(x: center.x - 5.5, y: center.y - 6.25, width: 11, height: 12.5)
    }

    /// 拭った跡の透明度。しばらくはクリアなまま、終盤で一気に曇る
    private func clearness(_ stroke: Stroke, now: Date) -> Double {
        let t = now.timeIntervalSince(stroke.date) / fadeDuration
        return 1 - t * t * t
    }
}

enum Store {
    private static let strokesURL = URL.documentsDirectory.appending(path: "strokes.json")
    private static let backgroundURL = URL.documentsDirectory.appending(path: "background")

    static func loadStrokes() -> [Stroke] {
        guard let data = try? Data(contentsOf: strokesURL),
              let strokes = try? JSONDecoder().decode([Stroke].self, from: data) else { return [] }
        return strokes.filter { Date.now.timeIntervalSince($0.date) <= fadeDuration }
    }

    static func saveStrokes(_ strokes: [Stroke]) {
        try? JSONEncoder().encode(strokes).write(to: strokesURL)
    }

    static func loadBackground() -> UIImage? {
        UIImage(contentsOfFile: backgroundURL.path())
    }

    static func saveBackground(_ data: Data) {
        try? data.write(to: backgroundURL)
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

/// アプリとウィジェットで共有する置き場所 (App Group)
enum Snapshots {
    /// xtool は App Group の ID を「group.<書き換え後のアプリの bundle ID>」にするので、自分の bundle ID から組み立てる
    static var directory: URL? {
        guard let appID = Bundle.main.bundleIdentifier else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group." + appID)
    }
}
