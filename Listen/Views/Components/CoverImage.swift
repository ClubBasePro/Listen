import SwiftUI
import UIKit

/// Loads cover art from a URL and fills whatever frame it is given. Art whose shape
/// doesn't match the frame (e.g. square audiobook art on a tall book) is shown whole
/// over a blurred copy of itself, like a dust jacket, instead of being cropped.
struct CoverImage: View {
    let url: String
    let title: String
    let author: String
    /// Delay before fetching, so live previews don't fire a request per keystroke.
    var debounce: Duration = .zero

    @State private var image: UIImage?

    var body: some View {
        GeometryReader { geo in
            if let image {
                art(image, in: geo.size)
            } else {
                GeneratedCover(title: title, author: author)
            }
        }
        .task(id: url) { await load() }
    }

    @ViewBuilder
    private func art(_ image: UIImage, in size: CGSize) -> some View {
        let frameAspect = size.width / max(size.height, 1)
        let imageAspect = image.size.width / max(image.size.height, 1)
        if abs(imageAspect - frameAspect) / frameAspect < 0.12 {
            Image(uiImage: image).resizable().scaledToFill()
                .frame(width: size.width, height: size.height).clipped()
        } else {
            ZStack {
                Image(uiImage: image).resizable().scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .blur(radius: max(size.width / 12, 4)).scaleEffect(1.25)
                    .overlay(Color.black.opacity(0.2))
                Image(uiImage: image).resizable().scaledToFit()
                    .shadow(color: .black.opacity(0.35), radius: size.width / 30, y: size.width / 60)
            }
            .frame(width: size.width, height: size.height).clipped()
        }
    }

    private func load() async {
        guard let link = URL(string: url.trimmingCharacters(in: .whitespaces)),
              link.scheme?.hasPrefix("http") == true else {
            image = nil
            return
        }
        if let cached = ImageCache.shared.cached(link) {
            image = cached
            return
        }
        if debounce > .zero {
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
        }
        let loaded = await ImageCache.shared.image(for: link)
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.25)) { image = loaded }
    }
}

/// A typeset cloth-bound cover used when a book has no artwork.
struct GeneratedCover: View {
    let title: String
    let author: String

    var body: some View {
        let palette = CoverPalette.for(title)
        GeometryReader { geo in
            let w = geo.size.width
            ZStack {
                LinearGradient(colors: [palette.top, palette.bottom], startPoint: .topLeading,
                               endPoint: .bottomTrailing)
                RoundedRectangle(cornerRadius: 1)
                    .strokeBorder(palette.ink.opacity(0.35), lineWidth: max(0.5, w * 0.008))
                    .padding(w * 0.07)
                VStack(spacing: w * 0.06) {
                    Rectangle().fill(palette.ink.opacity(0.6)).frame(width: w * 0.22, height: max(0.5, w * 0.006))
                    Text(title)
                        .font(.system(size: max(w * 0.13, 6), weight: .semibold, design: .serif))
                        .multilineTextAlignment(.center)
                        .lineLimit(5)
                        .minimumScaleFactor(0.4)
                    Rectangle().fill(palette.ink.opacity(0.6)).frame(width: w * 0.22, height: max(0.5, w * 0.006))
                    if !author.isEmpty {
                        Text(author.uppercased())
                            .font(.system(size: max(w * 0.055, 4), weight: .medium))
                            .tracking(w * 0.008)
                            .lineLimit(2)
                            .minimumScaleFactor(0.5)
                            .multilineTextAlignment(.center)
                            .opacity(0.85)
                    }
                }
                .foregroundStyle(palette.ink)
                .padding(w * 0.14)
            }
        }
    }

    @MainActor
    static func render(title: String, author: String) -> UIImage? {
        let renderer = ImageRenderer(content: GeneratedCover(title: title, author: author)
            .frame(width: 400, height: 400))
        renderer.scale = 2
        return renderer.uiImage
    }
}

struct CoverPalette {
    let top: Color
    let bottom: Color
    let ink: Color
    let base: UIColor

    private static let swatches: [(top: UInt32, bottom: UInt32, ink: UInt32)] = [
        (0x1F3A5F, 0x0F1E33, 0xE9DCC0), // navy
        (0x7A1E23, 0x44100F, 0xF1DDB8), // oxblood
        (0x2F5140, 0x162A20, 0xE7DAB6), // forest
        (0xC9962F, 0x8E6418, 0x2A1A08), // mustard
        (0x5A3563, 0x2E1A34, 0xEBD9C9), // plum
        (0x3E4A55, 0x1D252C, 0xE2D6BF), // slate
        (0xB65A3A, 0x7A341C, 0xF6E6CF), // terracotta
        (0x2E6B6C, 0x163B3C, 0xF0E1C4), // teal
        (0xD9CDB4, 0xB5A686, 0x2B2118), // linen
    ]

    static func `for`(_ title: String) -> CoverPalette {
        let seed = title.utf8.reduce(UInt64(5381)) { ($0 << 5) &+ $0 &+ UInt64($1) }
        let s = swatches[Int(seed % UInt64(swatches.count))]
        return CoverPalette(top: Color(hex: s.top), bottom: Color(hex: s.bottom), ink: Color(hex: s.ink),
                            base: UIColor(hex: s.top))
    }
}
