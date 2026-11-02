import ARKit
import RealityKit
import SwiftUI
import UIKit

struct ARClassifyView: View {
    @State private var result: ClassificationResult?

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                FruitPalette.background.ignoresSafeArea()

                if ARWorldTrackingConfiguration.isSupported {
                    ARViewContainer { newResult in
                        result = newResult
                    }
                    .ignoresSafeArea()
                    ResultBanner(result: result)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 20)
                } else {
                    VStack(spacing: 14) {
                        Image(systemName: "cube.transparent")
                            .font(.system(size: 48))
                            .foregroundStyle(FruitPalette.accent)
                        Text("AR недоступен")
                            .font(.title3.weight(.semibold))
                        Text("Распознавание в ARView работает на устройстве с поддержкой ARKit.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 28)
                    }
                }
            }
            .navigationTitle("AR")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}

struct ARViewContainer: UIViewRepresentable {
    var onResult: (ClassificationResult) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onResult: onResult)
    }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        arView.automaticallyConfigureSession = false

        let configuration = ARWorldTrackingConfiguration()
        arView.session.delegate = context.coordinator
        arView.session.run(configuration)
        context.coordinator.arView = arView
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.onResult = onResult
    }

    static func dismantleUIView(_ uiView: ARView, coordinator: Coordinator) {
        uiView.session.pause()
    }

    final class Coordinator: NSObject, ARSessionDelegate {
        var onResult: (ClassificationResult) -> Void
        weak var arView: ARView?

        private let classifier = try? FruitVisionClassifier()
        private var isProcessing = false
        private var lastLabel: String?
        private var labelEntity: ModelEntity?

        init(onResult: @escaping (ClassificationResult) -> Void) {
            self.onResult = onResult
        }

        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            guard !isProcessing, let classifier else { return }
            isProcessing = true

            let buffer = frame.capturedImage
            let orientation = CGImagePropertyOrientation.right

            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let result = try? classifier.classify(pixelBuffer: buffer, orientation: orientation)
                DispatchQueue.main.async {
                    guard let self, let result else {
                        self?.isProcessing = false
                        return
                    }
                    self.onResult(result)
                    self.updateAnchor(with: result)
                    self.isProcessing = false
                }
            }
        }

        private func updateAnchor(with result: ClassificationResult) {
            guard let arView, result.isReliable, let top = result.top else { return }
            let label = "\(top.kind?.emoji ?? "") \(top.title) \(top.percent)%"
            guard label != lastLabel else { return }
            lastLabel = label

            if let labelEntity {
                labelEntity.model = Self.makeTextModel(label)
                return
            }

            let entity = ModelEntity(mesh: Self.makeTextMesh(label), materials: [Self.labelMaterial])
            entity.position = SIMD3(-0.18, 0.06, -0.45)
            let anchor = AnchorEntity(.camera)
            anchor.addChild(entity)
            arView.scene.addAnchor(anchor)
            labelEntity = entity
        }

        private static func makeTextModel(_ text: String) -> ModelComponent {
            ModelComponent(mesh: makeTextMesh(text), materials: [labelMaterial])
        }

        private static func makeTextMesh(_ text: String) -> MeshResource {
            .generateText(
                text,
                extrusionDepth: 0.004,
                font: .systemFont(ofSize: 0.04, weight: .bold),
                containerFrame: .zero,
                alignment: .center,
                lineBreakMode: .byWordWrapping
            )
        }

        private static let labelMaterial = UnlitMaterial(color: UIColor(red: 0.96, green: 0.62, blue: 0.22, alpha: 1))
    }
}
