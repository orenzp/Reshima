#if canImport(UIKit)
import UIKit

enum ImageResizer {
    /// Downscales a picked photo and re-encodes it as JPEG so uploads stay small (roughly 100-300 KB).
    static func jpegData(from data: Data, maxDimension: CGFloat = 1280, quality: CGFloat = 0.7) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let longestSide = max(image.size.width, image.size.height)
        guard longestSide > 0 else { return nil }
        let scale = min(1, maxDimension / longestSide)
        let targetSize = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let resized = UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return resized.jpegData(compressionQuality: quality)
    }
}
#endif
