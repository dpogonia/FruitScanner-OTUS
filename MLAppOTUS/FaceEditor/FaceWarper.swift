import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

nonisolated enum FaceWarper {
    private static let context = CIContext(options: [.cacheIntermediates: false])

    static func render(
        image: UIImage,
        face: DetectedFace,
        oval: Float,
        eyes: Float
    ) -> UIImage {
        guard let cgImage = image.cgImage else { return image }
        var ciImage = CIImage(cgImage: cgImage)
        let extent = ciImage.extent

        if abs(oval) > 0.01 {
            let cheekScale = -oval * 0.42
            let cheekRadius = face.faceWidth * 0.36
            if let left = face.leftCheek {
                ciImage = bump(ciImage, center: left, radius: cheekRadius, scale: cheekScale)
            }
            if let right = face.rightCheek {
                ciImage = bump(ciImage, center: right, radius: cheekRadius, scale: cheekScale)
            }
            if let chin = face.chin {
                ciImage = bump(
                    ciImage,
                    center: chin,
                    radius: face.faceWidth * 0.26,
                    scale: oval * 0.18
                )
            }
        }

        if abs(eyes) > 0.01 {
            let scale = eyes * 0.52
            if let left = face.leftEye {
                ciImage = bump(ciImage, center: left.center, radius: left.radius * 2.4, scale: scale)
            }
            if let right = face.rightEye {
                ciImage = bump(ciImage, center: right.center, radius: right.radius * 2.4, scale: scale)
            }
        }

        ciImage = ciImage.cropped(to: extent)
        guard let output = context.createCGImage(ciImage, from: extent) else {
            return image
        }
        return UIImage(cgImage: output, scale: image.scale, orientation: .up)
    }

    private static func bump(
        _ input: CIImage,
        center: CGPoint,
        radius: CGFloat,
        scale: Float
    ) -> CIImage {
        let filter = CIFilter.bumpDistortion()
        filter.inputImage = input
        filter.center = center
        filter.radius = Float(max(radius, 8))
        filter.scale = scale
        return filter.outputImage ?? input
    }
}
