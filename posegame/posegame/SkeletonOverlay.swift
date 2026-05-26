import SwiftUI

struct SkeletonOverlay: View {
    let landmarks: [Landmark]
    let hands: [HandLandmark]
    let face: [FaceLandmark]
    let actions: [String]
    let videoSize: CGSize

    var body: some View {
        GeometryReader { geo in
            let viewSize = geo.size
            Canvas { ctx, _ in
                let toScreen = makeTransform(video: videoSize, view: viewSize)
                drawBody(ctx: &ctx, transform: toScreen)
                for hand in hands {
                    drawHand(ctx: &ctx, hand: hand, transform: toScreen)
                }
                drawFace(ctx: &ctx, transform: toScreen)
            }
        }
    }

    /// 计算从 Vision 归一化坐标 -> 屏幕像素坐标的变换，
    /// 补偿 cameraPreview 的 resizeAspectFill 裁剪。
    private func makeTransform(video: CGSize, view: CGSize) -> (CGFloat, CGFloat) -> CGPoint {
        guard video.width > 0, video.height > 0 else {
            return { (x: CGFloat, y: CGFloat) -> CGPoint in
                return CGPoint(x: x * view.width, y: (1 - y) * view.height)
            }
        }
        // resizeAspectFill: 图像缩放到完全填满 view
        let scale = max(view.width / video.width, view.height / video.height)
        let scaledW = video.width * scale
        let scaledH = video.height * scale
        // 裁剪偏移量（居中裁剪）
        let offsetX = (scaledW - view.width) / 2
        let offsetY = (scaledH - view.height) / 2

        return { (nx: CGFloat, ny: CGFloat) -> CGPoint in
            // Vision (0,0)左下 -> 像素坐标
            let px = nx * scaledW - offsetX
            let py = (1 - ny) * scaledH - offsetY
            return CGPoint(x: px, y: py)
        }
    }

    // MARK: - 身体

    private func drawBody(ctx: inout GraphicsContext, transform: (CGFloat, CGFloat) -> CGPoint) {
        let lm = landmarks.filter { $0.confidence > 0.4 }
        for conn in skeletonConnections {
            guard let p1 = lm.first(where: { $0.joint == conn.from }),
                  let p2 = lm.first(where: { $0.joint == conn.to })
            else { continue }
            var path = Path()
            path.move(to: transform(CGFloat(p1.x), CGFloat(p1.y)))
            path.addLine(to: transform(CGFloat(p2.x), CGFloat(p2.y)))
            ctx.stroke(path, with: .color(.green.opacity(0.8)), lineWidth: 3)
        }
        for p in lm {
            let pt = transform(CGFloat(p.x), CGFloat(p.y))
            ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 4, y: pt.y - 4, width: 8, height: 8)),
                     with: .color(.yellow))
        }
    }

    // MARK: - 手部

    private func drawHand(ctx: inout GraphicsContext, hand: HandLandmark, transform: (CGFloat, CGFloat) -> CGPoint) {
        let color: Color = hand.chirality == .left ? .cyan : .orange
        let dict = Dictionary(uniqueKeysWithValues: hand.joints.map { ($0.n, ($0.x, $0.y, $0.c)) })

        for (from, to) in handSkeletonConnections {
            guard let p1 = dict[from], let p2 = dict[to],
                  p1.2 > 0.4, p2.2 > 0.4
            else { continue }
            var path = Path()
            path.move(to: transform(CGFloat(p1.0), CGFloat(p1.1)))
            path.addLine(to: transform(CGFloat(p2.0), CGFloat(p2.1)))
            ctx.stroke(path, with: .color(color.opacity(0.7)), lineWidth: 2)
        }

        for (_, p) in dict where p.2 > 0.4 {
            let pt = transform(CGFloat(p.0), CGFloat(p.1))
            ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 3, y: pt.y - 3, width: 6, height: 6)),
                     with: .color(color))
        }
    }

    // MARK: - 面部

    private func drawFace(ctx: inout GraphicsContext, transform: (CGFloat, CGFloat) -> CGPoint) {
        for f in face where f.c > 0.4 {
            let pt = transform(CGFloat(f.x), CGFloat(f.y))
            ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 3, y: pt.y - 3, width: 6, height: 6)),
                     with: .color(.pink))
        }
    }
}
