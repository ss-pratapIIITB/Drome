import CoreML
import UIKit
import Vision

/// On-device nudity classifier for visible page images.
///
/// The bundled `NSFWClassifier` model is a ViT-base image classifier reduced to
/// int8 weights (~86 MB), with two outputs: `normal` and `nsfw`. Pixels come
/// from a WebView viewport snapshot cropped per image, so cross-origin images
/// work without fetching them a second time and nothing leaves the device.
final class ImageSafetyFilter {
    static let shared = ImageSafetyFilter()

    /// Probability at which an image is treated as unsafe. Tune with the eval
    /// fixtures; start conservative so benign photos are not hidden.
    static let threshold: Float = 0.70

    private let model: VNCoreMLModel?

    private init() {
        guard let url = Bundle.main.url(forResource: "NSFWClassifier", withExtension: "mlmodelc"),
              let coreModel = try? MLModel(contentsOf: url),
              let visionModel = try? VNCoreMLModel(for: coreModel) else {
            model = nil
            return
        }
        model = visionModel
    }

    var isAvailable: Bool { model != nil }

    /// Synchronous prediction. Call off the main thread for batches.
    func isUnsafe(_ image: CGImage) -> Bool {
        guard let model else { return false }

        let request = VNCoreMLRequest(model: model)
        request.imageCropAndScaleOption = .centerCrop

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return false
        }

        let observations = request.results as? [VNClassificationObservation] ?? []
        return observations.contains { observation in
            observation.identifier.lowercased().contains("nsfw")
                && observation.confidence >= Self.threshold
        }
    }
}
