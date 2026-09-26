import CoreImage
import CryptoKit
import UIKit

/// Memory + disk cache for cover art, so covers load instantly after the first view.
final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()

    private let memory = NSCache<NSString, UIImage>()
    private let directory: URL
    private let maxDimension: CGFloat = 1200

    private init() {
        directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Covers", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        memory.countLimit = 200
    }

    func cached(_ url: URL) -> UIImage? {
        memory.object(forKey: url.absoluteString as NSString)
    }

    func image(for url: URL) async -> UIImage? {
        let key = url.absoluteString as NSString
        if let image = memory.object(forKey: key) { return image }

        let file = directory.appendingPathComponent(Self.hash(url.absoluteString))
        if let data = try? Data(contentsOf: file), let image = UIImage(data: data) {
            let prepared = image.preparingForDisplay() ?? image
            memory.setObject(prepared, forKey: key)
            return prepared
        }

        guard let result = try? await URLSession.shared.data(from: url) else { return nil }
        if let http = result.1 as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return nil }
        guard let decoded = UIImage(data: result.0) else { return nil }

        let image = downscaled(decoded)
        if let jpeg = image.jpegData(compressionQuality: 0.9) {
            try? jpeg.write(to: file, options: .atomic)
        }
        memory.setObject(image, forKey: key)
        return image
    }

    private func downscaled(_ image: UIImage) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxDimension else { return image.preparingForDisplay() ?? image }
        let scale = maxDimension / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return image.preparingThumbnail(of: size) ?? image
    }

    private static func hash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

extension UIImage {
    private static let colorContext = CIContext(options: [.workingColorSpace: NSNull()])

    /// Average colour of the image, used to tint the player.
    var averageColor: UIColor? {
        guard let input = CIImage(image: self),
              let filter = CIFilter(name: "CIAreaAverage", parameters: [
                  kCIInputImageKey: input,
                  kCIInputExtentKey: CIVector(cgRect: input.extent),
              ]),
              let output = filter.outputImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        Self.colorContext.render(output, toBitmap: &pixel, rowBytes: 4,
                                 bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                                 format: .RGBA8, colorSpace: nil)
        return UIColor(red: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255,
                       blue: CGFloat(pixel[2]) / 255, alpha: 1)
    }
}

extension UIColor {
    /// A version of the colour rich enough to tint a dark background without washing out.
    var playerTint: UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard getHue(&h, saturation: &s, brightness: &b, alpha: &a) else { return self }
        return UIColor(hue: h, saturation: min(max(s, 0.25) * 1.15, 0.85),
                       brightness: min(max(b, 0.4), 0.7), alpha: 1)
    }
}
