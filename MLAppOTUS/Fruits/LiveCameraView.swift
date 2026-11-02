import AVFoundation
import SwiftUI

struct LiveCameraView: View {
    @State private var model = LiveCameraViewModel()

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                FruitPalette.background.ignoresSafeArea()

                if model.cameraUnavailable {
                    unavailable(
                        symbol: "camera.fill",
                        title: "Камера недоступна",
                        text: "Живое распознавание работает на устройстве. В симуляторе откройте вкладку «Фото»."
                    )
                } else if model.permissionDenied {
                    unavailable(
                        symbol: "lock.fill",
                        title: "Нет доступа к камере",
                        text: "Разрешите камеру в Настройках, чтобы классифицировать фрукты в реальном времени."
                    )
                } else {
                    CameraPreview(session: model.session.session)
                        .ignoresSafeArea()
                    ResultBanner(result: model.result)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 20)
                }
            }
            .navigationTitle("Камера")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .task {
                await model.start()
            }
            .onDisappear {
                model.stop()
            }
        }
    }

    private func unavailable(symbol: String, title: String, text: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 48))
                .foregroundStyle(FruitPalette.accent)
            Text(title)
                .font(.title3.weight(.semibold))
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
        }
    }
}

@Observable
final class LiveCameraViewModel {
    var result: ClassificationResult?
    var permissionDenied = false
    var cameraUnavailable = false

    let session = CameraSession()

    func start() async {
        #if targetEnvironment(simulator)
        cameraUnavailable = true
        #else
        let allowed = await session.requestPermission()
        guard allowed else {
            permissionDenied = true
            return
        }
        session.onResult = { result in
            Task { @MainActor [weak self] in
                self?.result = result
            }
        }
        session.start()
        #endif
    }

    func stop() {
        session.stop()
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.previewLayer.session = session
    }
}

final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}
