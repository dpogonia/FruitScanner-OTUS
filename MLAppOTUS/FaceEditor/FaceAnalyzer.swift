import CoreImage
import Foundation
import UIKit
import Vision

nonisolated enum FaceShape: String, Sendable {
    case oval
    case round
    case square
    case heart
    case oblong
    case unknown

    var title: String {
        switch self {
        case .oval: "Овальное"
        case .round: "Круглое"
        case .square: "Квадратное"
        case .heart: "Сердцевидное"
        case .oblong: "Вытянутое"
        case .unknown: "Не определено"
        }
    }

    var detail: String {
        switch self {
        case .oval: "Скулы чуть шире челюсти, мягкий контур"
        case .round: "Ширина близка к высоте"
        case .square: "Широкая челюсть, короткая высота"
        case .heart: "Широкий лоб и узкий подбородок"
        case .oblong: "Лицо заметно длиннее ширины"
        case .unknown: "Нужен портрет анфас"
        }
    }
}

nonisolated struct EyeRegion: Sendable {
    let center: CGPoint
    let radius: CGFloat
}

nonisolated struct DetectedFace: Sendable {
    let imageSize: CGSize
    let boundingBox: CGRect
    let shape: FaceShape
    let contour: [CGPoint]
    let leftEye: EyeRegion?
    let rightEye: EyeRegion?
    let leftCheek: CGPoint?
    let rightCheek: CGPoint?
    let chin: CGPoint?
    let overlayPoints: [CGPoint]

    var faceWidth: CGFloat { boundingBox.width }
    var faceHeight: CGFloat { boundingBox.height }
}

nonisolated enum FaceAnalyzer {
    static func prepare(_ image: UIImage, maxSide: CGFloat = 1400) -> UIImage? {
        guard let data = image.jpegData(compressionQuality: 0.95),
              let jpeg = UIImage(data: data),
              jpeg.cgImage != nil else {
            return image.cgImage == nil ? nil : image
        }

        let longest = max(jpeg.size.width * jpeg.scale, jpeg.size.height * jpeg.scale)
        guard longest > maxSide else { return jpeg }

        let factor = maxSide / longest
        let newSize = CGSize(width: jpeg.size.width * factor, height: jpeg.size.height * factor)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let drawn = UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            jpeg.draw(in: CGRect(origin: .zero, size: newSize))
        }
        if let resized = drawn.jpegData(compressionQuality: 0.92).flatMap(UIImage.init(data:)),
           resized.cgImage != nil {
            return resized
        }
        return drawn.cgImage == nil ? jpeg : drawn
    }

    static func detect(in image: UIImage) -> DetectedFace? {
        guard let cgImage = image.cgImage else { return nil }
        let size = CGSize(width: cgImage.width, height: cgImage.height)
        if let face = strongestFace(in: cgImage) {
            return makeDetectedFace(from: face, imageSize: size)
        }
        return detectWithCIDetector(cgImage: cgImage, imageSize: size)
    }

    private static func makeDetectedFace(from face: VNFaceObservation, imageSize size: CGSize) -> DetectedFace {
        let box = CGRect(
            x: face.boundingBox.origin.x * size.width,
            y: face.boundingBox.origin.y * size.height,
            width: face.boundingBox.width * size.width,
            height: face.boundingBox.height * size.height
        )

        func mapped(_ point: CGPoint) -> CGPoint {
            CGPoint(
                x: (face.boundingBox.origin.x + point.x * face.boundingBox.width) * size.width,
                y: (face.boundingBox.origin.y + point.y * face.boundingBox.height) * size.height
            )
        }

        func region(_ landmark: VNFaceLandmarkRegion2D?) -> [CGPoint] {
            landmark?.normalizedPoints.map(mapped) ?? []
        }

        func eye(from landmark: VNFaceLandmarkRegion2D?) -> EyeRegion? {
            let points = region(landmark)
            guard !points.isEmpty else { return nil }
            let center = CGPoint(
                x: points.map(\.x).reduce(0, +) / CGFloat(points.count),
                y: points.map(\.y).reduce(0, +) / CGFloat(points.count)
            )
            let radius = points.map { hypot($0.x - center.x, $0.y - center.y) }.max() ?? 12
            return EyeRegion(center: center, radius: max(radius, box.width * 0.04))
        }

        let contour = region(face.landmarks?.faceContour)
        let leftEye = eye(from: face.landmarks?.leftEye)
        let rightEye = eye(from: face.landmarks?.rightEye)

        let minY = contour.map(\.y).min() ?? box.minY
        let maxY = contour.map(\.y).max() ?? box.maxY
        let midY = box.midY

        let leftCheek = contour
            .filter { $0.y > midY - box.height * 0.15 && $0.y < midY + box.height * 0.2 }
            .min(by: { $0.x < $1.x })
        let rightCheek = contour
            .filter { $0.y > midY - box.height * 0.15 && $0.y < midY + box.height * 0.2 }
            .max(by: { $0.x < $1.x })
        let chin = contour.min(by: { $0.y < $1.y })

        var overlay = contour
        overlay.append(contentsOf: region(face.landmarks?.leftEye))
        overlay.append(contentsOf: region(face.landmarks?.rightEye))
        overlay.append(contentsOf: region(face.landmarks?.leftEyebrow))
        overlay.append(contentsOf: region(face.landmarks?.rightEyebrow))
        overlay.append(contentsOf: region(face.landmarks?.nose))
        overlay.append(contentsOf: region(face.landmarks?.outerLips))

        let shape = classify(
            box: box,
            contour: contour,
            minY: minY,
            maxY: maxY
        )

        return DetectedFace(
            imageSize: size,
            boundingBox: box,
            shape: shape,
            contour: contour,
            leftEye: leftEye ?? estimatedEye(in: box, isLeft: true),
            rightEye: rightEye ?? estimatedEye(in: box, isLeft: false),
            leftCheek: leftCheek ?? CGPoint(x: box.minX + box.width * 0.18, y: box.midY),
            rightCheek: rightCheek ?? CGPoint(x: box.maxX - box.width * 0.18, y: box.midY),
            chin: chin ?? CGPoint(x: box.midX, y: box.minY + box.height * 0.08),
            overlayPoints: overlay
        )
    }

    private static func strongestFace(in cgImage: CGImage) -> VNFaceObservation? {
        if let face = runVision(VNImageRequestHandler(cgImage: cgImage, orientation: .up)) {
            return face
        }
        if let data = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.95),
           let face = runVision(VNImageRequestHandler(data: data, orientation: .up)) {
            return face
        }
        return runVision(VNImageRequestHandler(ciImage: CIImage(cgImage: cgImage), options: [:]))
    }

    private static func runVision(_ handler: VNImageRequestHandler) -> VNFaceObservation? {
        let landmarksRequest = VNDetectFaceLandmarksRequest()
        let rectanglesRequest = VNDetectFaceRectanglesRequest()
        do {
            try handler.perform([landmarksRequest, rectanglesRequest])
        } catch {
            return nil
        }
        return largest(landmarksRequest.results) ?? largest(rectanglesRequest.results)
    }

    private static func largest(_ faces: [VNFaceObservation]?) -> VNFaceObservation? {
        faces?.max(by: {
            $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height
        })
    }

    private static func estimatedEye(in box: CGRect, isLeft: Bool) -> EyeRegion {
        let center = CGPoint(
            x: box.minX + box.width * (isLeft ? 0.32 : 0.68),
            y: box.minY + box.height * 0.64
        )
        return EyeRegion(center: center, radius: box.width * 0.08)
    }

    private static func detectWithCIDetector(cgImage: CGImage, imageSize size: CGSize) -> DetectedFace? {
        let ciImage = CIImage(cgImage: cgImage)
        let detector = CIDetector(
            ofType: CIDetectorTypeFace,
            context: nil,
            options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
        )
        let features = detector?.features(
            in: ciImage,
            options: [CIDetectorImageOrientation: 1]
        ) as? [CIFaceFeature]
        guard let feature = features?.max(by: {
            $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height
        }) else {
            return nil
        }

        let box = feature.bounds
        let leftEye = feature.hasLeftEyePosition
            ? EyeRegion(center: feature.leftEyePosition, radius: box.width * 0.08)
            : estimatedEye(in: box, isLeft: true)
        let rightEye = feature.hasRightEyePosition
            ? EyeRegion(center: feature.rightEyePosition, radius: box.width * 0.08)
            : estimatedEye(in: box, isLeft: false)
        let mouth = feature.hasMouthPosition ? feature.mouthPosition : CGPoint(x: box.midX, y: box.minY + box.height * 0.22)
        let contour = [
            CGPoint(x: box.minX + box.width * 0.15, y: box.maxY - box.height * 0.12),
            CGPoint(x: box.minX, y: box.midY),
            CGPoint(x: box.minX + box.width * 0.2, y: box.minY + box.height * 0.1),
            CGPoint(x: box.midX, y: box.minY),
            CGPoint(x: box.maxX - box.width * 0.2, y: box.minY + box.height * 0.1),
            CGPoint(x: box.maxX, y: box.midY),
            CGPoint(x: box.maxX - box.width * 0.15, y: box.maxY - box.height * 0.12)
        ]

        return DetectedFace(
            imageSize: size,
            boundingBox: box,
            shape: classify(box: box, contour: contour, minY: box.minY, maxY: box.maxY),
            contour: contour,
            leftEye: leftEye,
            rightEye: rightEye,
            leftCheek: CGPoint(x: box.minX + box.width * 0.18, y: box.midY),
            rightCheek: CGPoint(x: box.maxX - box.width * 0.18, y: box.midY),
            chin: mouth,
            overlayPoints: contour + [leftEye.center, rightEye.center, mouth]
        )
    }

    private static func classify(
        box: CGRect,
        contour: [CGPoint],
        minY: CGFloat,
        maxY: CGFloat
    ) -> FaceShape {
        let width = box.width
        let height = max(box.height, 1)
        let ratio = height / width

        guard !contour.isEmpty else {
            if ratio > 1.45 { return .oblong }
            if ratio < 1.12 { return .round }
            return .oval
        }

        let jawBand = minY + height * 0.22
        let browBand = maxY - height * 0.22
        let jaw = contour.filter { $0.y <= jawBand }
        let brow = contour.filter { $0.y >= browBand }

        func span(of points: [CGPoint]) -> CGFloat {
            guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max() else {
                return width
            }
            return max(maxX - minX, 1)
        }

        let jawWidth = span(of: jaw)
        let browWidth = span(of: brow)
        let cheekWidth = width

        if ratio > 1.48 {
            return .oblong
        }
        if browWidth > jawWidth * 1.18 && ratio > 1.15 {
            return .heart
        }
        if ratio < 1.14 && jawWidth / cheekWidth > 0.9 {
            return .round
        }
        if ratio < 1.28 && jawWidth / cheekWidth > 0.93 {
            return .square
        }
        return .oval
    }
}
