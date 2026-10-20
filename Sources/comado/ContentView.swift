import SwiftUI
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

struct ContentView: View {
    @State private var strokes = Store.loadStrokes()
    @State private var current: Stroke?
    @State private var background = Store.loadBackground()
    @State private var pickerItem: PhotosPickerItem?

    var body: some View {
        GeometryReader { geo in
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                ZStack {
                    backgroundView(geo.size)
                    backgroundView(geo.size)
                        .blur(radius: 20, opaque: true)
                        .overlay(Color.white.opacity(0.35))
                        .mask { fogMask(now: timeline.date) }
                }
            }
            .contentShape(Rectangle())
            .gesture(drawGesture(geo.size))
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
        .onChange(of: pickerItem) { _, item in
            Task {
                guard let data = try? await item?.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else { return }
                background = image
                Store.saveBackground(data)
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
            ctx.addFilter(.blur(radius: 6))
            let all = current.map { strokes + [$0] } ?? strokes
            for stroke in all {
                // ponytail: 線形に曇り直す。本物っぽさが足りなければ easing を入れる
                let alpha = 1 - now.timeIntervalSince(stroke.date) / fadeDuration
                guard alpha > 0 else { continue }
                var path = Path()
                path.addLines(stroke.points.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) })
                ctx.opacity = alpha
                ctx.stroke(path, with: .color(.black),
                           style: StrokeStyle(lineWidth: 28, lineCap: .round, lineJoin: .round))
            }
        }
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
                strokes.removeAll { Date.now.timeIntervalSince($0.date) > fadeDuration }
                Store.saveStrokes(strokes)
            }
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
