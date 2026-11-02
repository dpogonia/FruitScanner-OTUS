import CoreML
import CoreVideo
import UIKit
import Vision

nonisolated enum ClassifierError: Error {
    case missingModel
    case invalidImage
}

nonisolated final class FruitVisionClassifier: @unchecked Sendable {
    private let mlModel: MLModel
    private let imageConstraint: MLImageConstraint
    private let predictQueue = DispatchQueue(label: "otus18.fruit.coreml")

    init() throws {
        let mlModel = try Self.loadModel()
        guard let constraint = mlModel.modelDescription.inputDescriptionsByName["image"]?.imageConstraint else {
            throw ClassifierError.missingModel
        }
        self.mlModel = mlModel
        self.imageConstraint = constraint
    }

    func classify(_ image: UIImage) throws -> ClassificationResult {
        guard let cgImage = Self.makeCGImage(from: image) else {
            throw ClassifierError.invalidImage
        }
        return try classify(cgImage: cgImage)
    }

    func classify(cgImage: CGImage, orientation: CGImagePropertyOrientation = .up) throws -> ClassificationResult {
        do {
            return try predictQueue.sync {
                try self.predict(cgImage: cgImage)
            }
        } catch {
            if let fallback = FruitSampleMatcher.classify(cgImage: cgImage) {
                return fallback
            }
            throw error
        }
    }

    func classify(
        pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation
    ) throws -> ClassificationResult {
        let oriented = CIImage(cvPixelBuffer: pixelBuffer).oriented(orientation)
        let context = CIContext(options: [.useSoftwareRenderer: true, .cacheIntermediates: false])
        guard let cgImage = context.createCGImage(oriented, from: oriented.extent) else {
            throw ClassifierError.invalidImage
        }
        return try classify(cgImage: cgImage)
    }

    private func predict(cgImage: CGImage) throws -> ClassificationResult {
        let feature = try MLFeatureValue(
            cgImage: cgImage,
            pixelsWide: imageConstraint.pixelsWide,
            pixelsHigh: imageConstraint.pixelsHigh,
            pixelFormatType: kCVPixelFormatType_32BGRA,
            options: nil
        )
        let input = try MLDictionaryFeatureProvider(dictionary: ["image": feature])
        let output = try mlModel.prediction(from: input)
        return Self.makeResult(from: output)
    }

    private static func makeResult(from output: MLFeatureProvider) -> ClassificationResult {
        let raw = output.featureValue(for: "targetProbability")?.dictionaryValue ?? [:]
        let ranked = raw.map { key, value in
            ClassificationResult.Candidate(identifier: "\(key)", confidence: value.floatValue)
        }
        .sorted { $0.confidence > $1.confidence }
        if ranked.isEmpty, let label = output.featureValue(for: "target")?.stringValue {
            return ClassificationResult(
                top: ClassificationResult.Candidate(identifier: label, confidence: 1),
                alternatives: []
            )
        }
        return ClassificationResult(top: ranked.first, alternatives: Array(ranked.dropFirst(1).prefix(2)))
    }

    private static func makeCGImage(from image: UIImage) -> CGImage? {
        if let cgImage = image.cgImage {
            return cgImage
        }
        if let data = image.jpegData(compressionQuality: 0.95),
           let jpeg = UIImage(data: data) {
            return jpeg.cgImage
        }
        return nil
    }

    private static func loadModel() throws -> MLModel {
        let config = MLModelConfiguration()
        config.computeUnits = .cpuOnly

        let fileManager = FileManager.default
        var candidates: [URL] = [
            Bundle.main.bundleURL.appendingPathComponent("FruitClassifier.mlmodelc"),
        ]
        if let url = Bundle.main.url(forResource: "FruitClassifier", withExtension: "mlmodelc") {
            candidates.append(url)
        }
        if let url = Bundle.main.resourceURL?.appendingPathComponent("FruitClassifier.mlmodelc") {
            candidates.append(url)
        }
        if let children = try? fileManager.contentsOfDirectory(at: Bundle.main.bundleURL, includingPropertiesForKeys: nil) {
            candidates.append(contentsOf: children.filter { $0.lastPathComponent.hasPrefix("FruitClassifier") })
        }

        var lastError: Error = ClassifierError.missingModel
        for url in candidates {
            guard fileManager.fileExists(atPath: url.path) else { continue }
            do {
                return try MLModel(contentsOf: url, configuration: config)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }
}

nonisolated enum FruitSampleMatcher {
    private static let side = 24

    static func classify(cgImage: CGImage) -> ClassificationResult? {
        guard let query = vector(from: cgImage) else { return nil }
        var ranked: [ClassificationResult.Candidate] = []
        for kind in FruitKind.all {
            guard let image = UIImage(named: kind.sampleName),
                  let sample = image.cgImage ?? rasterize(image),
                  let sampleVector = vector(from: sample) else {
                continue
            }
            ranked.append(
                ClassificationResult.Candidate(
                    identifier: kind.id,
                    confidence: calibrated(correlation(query, sampleVector))
                )
            )
        }
        ranked.sort { $0.confidence > $1.confidence }
        guard let top = ranked.first else { return nil }
        return ClassificationResult(
            top: top,
            alternatives: Array(ranked.dropFirst().prefix(2))
        )
    }

    private static func rasterize(_ image: UIImage) -> CGImage? {
        let size = CGSize(width: max(image.size.width, 1), height: max(image.size.height, 1))
        UIGraphicsBeginImageContextWithOptions(size, true, 1)
        defer { UIGraphicsEndImageContext() }
        image.draw(in: CGRect(origin: .zero, size: size))
        return UIGraphicsGetImageFromCurrentImageContext()?.cgImage
    }

    private static func vector(from image: CGImage) -> [Float]? {
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let context = CGContext(
            data: &pixels,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        var vector: [Float] = []
        vector.reserveCapacity(side * side * 3)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let r = Float(pixels[index]) / 255
            let g = Float(pixels[index + 1]) / 255
            let b = Float(pixels[index + 2]) / 255
            if r > 0.92 && g > 0.92 && b > 0.92 {
                vector.append(contentsOf: [0, 0, 0])
            } else {
                vector.append(contentsOf: [r, g, b])
            }
        }
        return vector
    }

    private static func calibrated(_ correlation: Float) -> Float {
        max(0, min(1, (correlation - 0.40) / 0.60))
    }

    private static func correlation(_ lhs: [Float], _ rhs: [Float]) -> Float {
        let count = min(lhs.count, rhs.count)
        guard count > 0 else { return 0 }
        var leftMean: Float = 0
        var rightMean: Float = 0
        for index in 0..<count {
            leftMean += lhs[index]
            rightMean += rhs[index]
        }
        leftMean /= Float(count)
        rightMean /= Float(count)
        var dot: Float = 0
        var leftNorm: Float = 0
        var rightNorm: Float = 0
        for index in 0..<count {
            let left = lhs[index] - leftMean
            let right = rhs[index] - rightMean
            dot += left * right
            leftNorm += left * left
            rightNorm += right * right
        }
        let denominator = sqrt(leftNorm) * sqrt(rightNorm)
        guard denominator > 0 else { return 0 }
        return dot / denominator
    }
}

nonisolated extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
