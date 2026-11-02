@preconcurrency import AVFoundation
import UIKit

nonisolated final class CameraSession: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let session = AVCaptureSession()

    var onResult: (@Sendable (ClassificationResult) -> Void)?

    private let queue = DispatchQueue(label: "otus18.camera")
    private let classifier: FruitVisionClassifier?
    private var configured = false
    private var isProcessing = false
    private var lastClassification = Date.distantPast

    override init() {
        classifier = try? FruitVisionClassifier()
        super.init()
    }

    func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        default:
            return false
        }
    }

    func start() {
        queue.async { [self] in
            configureIfNeeded()
            guard !session.isRunning else { return }
            session.startRunning()
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard !isProcessing,
              Date().timeIntervalSince(lastClassification) > 0.2,
              let classifier,
              let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        isProcessing = true
        lastClassification = Date()
        defer { isProcessing = false }

        guard let result = try? classifier.classify(pixelBuffer: buffer, orientation: .up) else {
            return
        }
        onResult?(result)
    }

    private func configureIfNeeded() {
        guard !configured else { return }
        configured = true
        session.beginConfiguration()
        session.sessionPreset = .high

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        output.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(output) {
            session.addOutput(output)
        }
        if let connection = output.connection(with: .video),
           connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        session.commitConfiguration()
    }
}
