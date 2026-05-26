import SwiftUI
import PhotosUI

enum OverlayMode { case skeleton, facemask, foreground }

struct ContentView: View {
    @EnvironmentObject var camera: CameraManager
    @State private var showFacemask = false
    @State private var showForeground = false
    @State private var showSettings = false

    @State private var maskImages: [UIImage] = []
    @State private var maskIndex = 0
    @State private var maskScale: CGFloat = 1.0

    @State private var fgImages: [UIImage] = []
    @State private var fgIndex = 0
    @State private var fgScale: CGFloat = 1.0
    @State private var fgOffset: CGSize = .zero
    @State private var fgRotation: Angle = .zero

    @State private var noseOffsets: [Double] = []
    private let shakeWindow = 18
    private let triggerMinDelta: Double = 0.12
    private let shakeCooldownFrames = 15
    @State private var cooldownCounter = 0

    @State private var showMaskPicker = false
    @State private var showFgPicker = false
    @State private var showControls = false
    @State private var hideTask: Task<Void, Never>?

    @GestureState private var fgGestureScale: CGFloat = 1.0
    @State private var maskActiveScale: CGFloat = 1.0

    var body: some View {
        ZStack {
            CameraPreview(session: camera.session)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()

            SkeletonOverlay(landmarks: camera.landmarks, hands: camera.handLandmarks,
                            face: camera.faceLandmarks, actions: camera.activeActions,
                            videoSize: camera.videoSize)

            if showFacemask, !maskImages.isEmpty {
                GeometryReader { geo in
                    if let params = maskParams(viewSize: geo.size) {
                        Image(uiImage: maskImages[maskIndex])
                            .resizable().scaledToFit()
                            .frame(width: params.maskSize, height: params.maskSize)
                            .scaleEffect(maskScale * maskActiveScale)
                            .position(x: params.anchor.x, y: params.anchor.y)
                            .rotationEffect(params.rotation)
                            .gesture(
                                MagnificationGesture()
                                    .onChanged { v in
                                        maskActiveScale = v
                                        showControlsTemporarily()
                                    }
                                    .onEnded { v in
                                        maskScale = max(0.3, min(3.0, maskScale * v))
                                        maskActiveScale = 1.0
                                    }
                                    .simultaneously(with:
                                        TapGesture()
                                            .onEnded { maskIndex = (maskIndex + 1) % maskImages.count }
                                    )
                            )
                    }
                }
            } else if showForeground, !fgImages.isEmpty {
                GeometryReader { geo in
                    let base = min(geo.size.width, geo.size.height) * 0.4
                    Image(uiImage: fgImages[fgIndex])
                        .resizable().scaledToFit()
                        .frame(width: base, height: base)
                        .scaleEffect(fgScale * fgGestureScale)
                        .position(x: geo.size.width / 2 + fgOffset.width,
                                  y: geo.size.height / 2 + fgOffset.height)
                        .rotationEffect(fgRotation)
                        .gesture(
                            MagnificationGesture()
                                .updating($fgGestureScale) { v, s, _ in s = v }
                                .onEnded { v in fgScale *= v }
                                .simultaneously(with:
                                    RotationGesture()
                                        .onChanged { a in fgRotation = a; showControlsTemporarily() }
                                )
                                .simultaneously(with:
                                    DragGesture()
                                        .onChanged { v in fgOffset = v.translation; showControlsTemporarily() }
                                )
                                .simultaneously(with:
                                    TapGesture()
                                        .onEnded { fgIndex = (fgIndex + 1) % fgImages.count }
                                )
                        )
                }
            }

            VStack {
                HStack(spacing: 10) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(camera.activeActions, id: \.self) { a in
                                Text(a).font(.caption.bold())
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(.green.opacity(0.7)).cornerRadius(6)
                            }
                        }
                    }
                    .opacity(camera.activeActions.isEmpty ? 0 : 1)
                    .frame(maxWidth: 120)

                    if showFacemask {
                        if maskImages.isEmpty {
                            Button(action: { showMaskPicker = true }) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.body).foregroundColor(.white)
                            }
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                            .sheet(isPresented: $showMaskPicker) {
                                ImagePicker(images: $maskImages, currentIndex: $maskIndex)
                            }
                        } else {
                            HStack(spacing: 6) {
                                Button(action: { showMaskPicker = true }) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.caption).foregroundColor(.white)
                                }
                                .sheet(isPresented: $showMaskPicker) {
                                    ImagePicker(images: $maskImages, currentIndex: $maskIndex)
                                }
                                if showControls {
                                    Button(action: { deleteCurrent(mode: .facemask) }) {
                                        Image(systemName: "trash")
                                            .font(.caption).foregroundColor(.white)
                                    }
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(.ultraThinMaterial).clipShape(Capsule())
                                }
                            }
                        }
                    }
                    if showForeground {
                        if fgImages.isEmpty {
                            Button(action: { showFgPicker = true }) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.body).foregroundColor(.white)
                            }
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                            .sheet(isPresented: $showFgPicker) {
                                ImagePicker(images: $fgImages, currentIndex: $fgIndex)
                            }
                        } else {
                            HStack(spacing: 6) {
                                Button(action: { showFgPicker = true }) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.caption).foregroundColor(.white)
                                }
                                .sheet(isPresented: $showFgPicker) {
                                    ImagePicker(images: $fgImages, currentIndex: $fgIndex)
                                }
                                if showControls {
                                    Button(action: { deleteCurrent(mode: .foreground) }) {
                                        Image(systemName: "trash")
                                            .font(.caption).foregroundColor(.white)
                                    }
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(.ultraThinMaterial).clipShape(Capsule())
                                }
                            }
                        }
                    }

                    Spacer()

                    Button(action: { showSettings = true }) {
                        Image(systemName: "gearshape")
                            .font(.body).foregroundColor(.white.opacity(0.6))
                    }
                    .frame(width: 44, height: 44).contentShape(Rectangle())

                    Button(action: {
                        if showFacemask { showFacemask = false }
                        else { showFacemask = true; if maskImages.isEmpty { showMaskPicker = true } }
                    }) {
                        Image(systemName: "face.smiling")
                            .font(.body).foregroundColor(showFacemask ? .yellow : .white)
                    }
                    .frame(width: 44, height: 44).contentShape(Rectangle())

                    Button(action: {
                        if showForeground { showForeground = false }
                        else { showForeground = true; if fgImages.isEmpty { showFgPicker = true } }
                    }) {
                        Image(systemName: "rectangle.on.rectangle")
                            .font(.body).foregroundColor(showForeground ? .yellow : .white)
                    }
                    .frame(width: 44, height: 44).contentShape(Rectangle())

                    Button(action: { camera.toggleCamera() }) {
                        Image(systemName: "camera.rotate.fill")
                            .font(.body).foregroundColor(.white)
                    }
                    .frame(width: 44, height: 44).contentShape(Rectangle())
                    Circle()
                        .fill(camera.sender.isConnected ? Color.green : Color.red)
                        .frame(width: 10, height: 10)
                }
                .padding(.horizontal, 12)
                .padding(.top, 60)

                Spacer()
            }
        }
        .fullScreenCover(isPresented: $showSettings) {
            SettingsViewWrapper(camera: camera)
        }
        .onAppear { camera.requestAndStart() }
        .onChange(of: showSettings) { _, showing in
            if showing { camera.pauseTracking() }
            else { camera.resumeTracking() }
        }
        .onChange(of: camera.faceBoundingBox) { _, bbox in
            detectShake(bbox: bbox, face: camera.faceLandmarks)
        }
    }

    // MARK: - 脸谱位置

    private struct MaskParams {
        let anchor: CGPoint
        let rotation: Angle
        let maskSize: CGFloat
    }

    private func maskParams(viewSize: CGSize) -> MaskParams? {
        let face = camera.faceLandmarks
        let bbox = camera.faceBoundingBox
        guard let nose = face.first(where: { $0.n == .noseTip && $0.c > 0.4 }),
              bbox.width > 0.01 else { return nil }
        let video = camera.videoSize
        let transform: (CGFloat, CGFloat) -> CGPoint
        if video.width > 0, video.height > 0 {
            let s = max(viewSize.width / video.width, viewSize.height / video.height)
            let sw = video.width * s; let sh = video.height * s
            let ox = (sw - viewSize.width) / 2; let oy = (sh - viewSize.height) / 2
            transform = { CGPoint(x: $0 * sw - ox, y: (1 - $1) * sh - oy) }
        } else {
            transform = { CGPoint(x: $0 * viewSize.width, y: (1 - $1) * viewSize.height) }
        }
        let anchor = transform(CGFloat(nose.x), CGFloat(nose.y))
        var rotation: Angle = .zero
        if let l = face.first(where: { $0.n == .leftEye && $0.c > 0.4 }),
           let r = face.first(where: { $0.n == .rightEye && $0.c > 0.4 }) {
            let lp = transform(CGFloat(l.x), CGFloat(l.y))
            let rp = transform(CGFloat(r.x), CGFloat(r.y))
            rotation = Angle(radians: Double(atan2(rp.y - lp.y, rp.x - lp.x)))
        }
        let bboxW = CGFloat(bbox.width) * viewSize.width * (video.width > 0
            ? max(viewSize.width / video.width, viewSize.height / video.height) : 1.0)
        return MaskParams(anchor: anchor, rotation: rotation, maskSize: bboxW * 1.1)
    }

    // MARK: - 甩头

    private func detectShake(bbox: CGRect, face: [FaceLandmark]) {
        guard showFacemask, !maskImages.isEmpty, bbox.width > 0.01, cooldownCounter <= 0 else {
            if cooldownCounter > 0 { cooldownCounter -= 1 }; return
        }
        guard let nose = face.first(where: { $0.n == .noseTip && $0.c > 0.4 }) else {
            noseOffsets.removeAll(); return
        }
        let noseInFace = (nose.x - bbox.minX) / bbox.width
        noseOffsets.append(noseInFace)
        if noseOffsets.count > shakeWindow { noseOffsets.removeFirst() }
        guard noseOffsets.count >= shakeWindow else { return }
        let delta = (noseOffsets.max() ?? 0.5) - (noseOffsets.min() ?? 0.5)
        if delta > triggerMinDelta {
            maskIndex = (maskIndex + 1) % maskImages.count
            noseOffsets.removeAll()
            cooldownCounter = shakeCooldownFrames
        }
    }

    private func showControlsTemporarily() {
        showControls = true
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run { showControls = false }
        }
    }

    private func deleteCurrent(mode: OverlayMode) {
        switch mode {
        case .facemask:
            guard !maskImages.isEmpty else { return }
            maskImages.remove(at: maskIndex)
            if maskImages.isEmpty { maskIndex = 0; showFacemask = false }
            else { maskIndex = min(maskIndex, maskImages.count - 1) }
        case .foreground:
            guard !fgImages.isEmpty else { return }
            fgImages.remove(at: fgIndex)
            if fgImages.isEmpty { fgIndex = 0; showForeground = false }
            else { fgIndex = min(fgIndex, fgImages.count - 1) }
        case .skeleton: break
        }
    }
}

// MARK: - 设置页包装

struct SettingsViewWrapper: View {
    let camera: CameraManager
    @Environment(\.dismiss) var dismiss

    var body: some View {
        SettingsView()
            .environmentObject(camera)
    }
}

// MARK: - UIKit 图片选择器

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var images: [UIImage]
    @Binding var currentIndex: Int

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.selectionLimit = 20
        config.filter = .images
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: ImagePicker
        init(_ parent: ImagePicker) { self.parent = parent }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard !results.isEmpty else { return }
            var loaded: [UIImage] = []
            let group = DispatchGroup()
            for result in results {
                group.enter()
                result.itemProvider.loadObject(ofClass: UIImage.self) { obj, _ in
                    if let img = obj as? UIImage { loaded.append(img) }
                    group.leave()
                }
            }
            group.notify(queue: .main) {
                self.parent.images = loaded
                self.parent.currentIndex = 0
            }
        }
    }
}
