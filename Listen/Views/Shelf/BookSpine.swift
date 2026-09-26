import SwiftUI

/// A single hardback on the shelf: cover art with a bound spine, board thickness,
/// gloss, a progress strip and a bookmark ribbon when it's being listened to.
struct BookView: View {
    let title: String
    let author: String
    let coverURL: String
    var progress: Double = 0
    var isStarted = false
    var isFinished = false
    var showsBadges = true
    var debounce: Duration = .zero

    init(title: String, author: String, coverURL: String, progress: Double = 0,
         isStarted: Bool = false, isFinished: Bool = false, showsBadges: Bool = true,
         debounce: Duration = .zero) {
        self.title = title
        self.author = author
        self.coverURL = coverURL
        self.progress = progress
        self.isStarted = isStarted
        self.isFinished = isFinished
        self.showsBadges = showsBadges
        self.debounce = debounce
    }

    init(book: Book, showsBadges: Bool = true) {
        self.init(title: book.title, author: book.author, coverURL: book.coverURL, progress: book.progress,
                  isStarted: book.hasStarted, isFinished: book.isFinished, showsBadges: showsBadges)
    }

    var body: some View {
        Color.clear
            .aspectRatio(Theme.bookAspect, contentMode: .fit)
            .overlay { CoverImage(url: coverURL, title: title, author: author, debounce: debounce) }
            .overlay(alignment: .leading) { spine }
            .overlay { gloss }
            .overlay(alignment: .bottom) {
                if showsBadges, isStarted, progress > 0 {
                    ProgressBar(value: progress, track: .black.opacity(0.45), fill: Theme.accent)
                        .frame(height: 3)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 7)
                }
            }
            .clipShape(Theme.bookShape)
            .background { boards }
            .overlay(alignment: .bottomTrailing) {
                if showsBadges, isStarted { ribbon }
            }
            .overlay(alignment: .topTrailing) {
                if showsBadges, isFinished {
                    Image(systemName: "checkmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.black, Theme.accent)
                        .font(.system(size: 18))
                        .shadow(radius: 2)
                        .offset(x: 5, y: -5)
                }
            }
            .background(alignment: .bottom) {
                // Contact shadow where the book meets the shelf.
                Ellipse().fill(.black.opacity(0.55)).frame(height: 10).blur(radius: 5).offset(x: 3, y: 4)
            }
            .shadow(color: .black.opacity(0.45), radius: 6, x: 4, y: 3)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(author.isEmpty ? title : "\(title), by \(author)")
    }

    private var spine: some View {
        HStack(spacing: 0) {
            LinearGradient(stops: [
                .init(color: .black.opacity(0.45), location: 0),
                .init(color: .white.opacity(0.18), location: 0.35),
                .init(color: .black.opacity(0.25), location: 0.7),
                .init(color: .black.opacity(0.05), location: 1),
            ], startPoint: .leading, endPoint: .trailing)
            .frame(width: 11)
            Rectangle().fill(.black.opacity(0.18)).frame(width: 0.75)
        }
    }

    private var gloss: some View {
        LinearGradient(colors: [.white.opacity(0.16), .clear, .clear, .black.opacity(0.18)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
            .blendMode(.overlay)
    }

    /// Back board and page block peeking out behind the front cover.
    private var boards: some View {
        ZStack {
            Theme.bookShape.fill(Color(hex: 0x1A120C)).offset(x: 3, y: 1.5)
            Theme.bookShape.fill(
                LinearGradient(colors: [Color(hex: 0xEDE3CC), Color(hex: 0xC9BC9E)],
                               startPoint: .leading, endPoint: .trailing)
            )
            .padding(.vertical, 3)
            .offset(x: 1.8)
        }
    }

    private var ribbon: some View {
        RibbonShape()
            .fill(LinearGradient(colors: [Theme.ribbon, Theme.ribbon.opacity(0.8)],
                                 startPoint: .top, endPoint: .bottom))
            .frame(width: 9, height: 22)
            .shadow(color: .black.opacity(0.4), radius: 1.5, x: 1, y: 1)
            .offset(x: -14, y: 16)
    }
}

/// Bookmark ribbon with a V-notch at the end.
struct RibbonShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - rect.width * 0.55))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Dark walnut-panelled wall with a warm lamp glow from above.
struct WallBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.wallTop, Theme.wallMid, Theme.wallBottom],
                           startPoint: .top, endPoint: .bottom)
            Canvas { context, size in
                var rng = SeededRandom(state: 7)
                // Wood grain
                for _ in 0..<90 {
                    let x = CGFloat.random(in: 0...size.width, using: &rng)
                    let width = CGFloat.random(in: 0.5...2.5, using: &rng)
                    let opacity = Double.random(in: 0.02...0.07, using: &rng)
                    context.fill(Path(CGRect(x: x, y: 0, width: width, height: size.height)),
                                 with: .color(.black.opacity(opacity)))
                }
                // Panel seams
                let panels = 4
                for i in 1..<panels {
                    let x = size.width * CGFloat(i) / CGFloat(panels)
                    context.fill(Path(CGRect(x: x, y: 0, width: 1.5, height: size.height)),
                                 with: .color(.black.opacity(0.35)))
                    context.fill(Path(CGRect(x: x + 1.5, y: 0, width: 0.75, height: size.height)),
                                 with: .color(.white.opacity(0.04)))
                }
            }
            RadialGradient(colors: [Color(hex: 0xFFB36B).opacity(0.22), .clear],
                           center: .init(x: 0.5, y: -0.05), startRadius: 10, endRadius: 520)
        }
    }
}

/// A walnut shelf plank: top surface in perspective, a front edge, and a cast shadow.
struct ShelfPlank: View {
    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [Theme.woodDark, Theme.woodMid, Theme.woodLight],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 12)
            Rectangle().fill(Color.white.opacity(0.22)).frame(height: 1)
            LinearGradient(colors: [Theme.woodMid, Theme.woodDark], startPoint: .top, endPoint: .bottom)
                .frame(height: 16)
                .overlay {
                    Canvas { context, size in
                        var rng = SeededRandom(state: 21)
                        for _ in 0..<14 {
                            let y = CGFloat.random(in: 0...size.height, using: &rng)
                            var path = Path()
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addCurve(to: CGPoint(x: size.width, y: y + .random(in: -3...3, using: &rng)),
                                          control1: CGPoint(x: size.width * 0.3, y: y + .random(in: -4...4, using: &rng)),
                                          control2: CGPoint(x: size.width * 0.7, y: y + .random(in: -4...4, using: &rng)))
                            context.stroke(path, with: .color(.black.opacity(.random(in: 0.08...0.2, using: &rng))),
                                           lineWidth: .random(in: 0.5...1.2, using: &rng))
                        }
                    }
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
        .background(alignment: .top) {
            LinearGradient(colors: [.black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 26)
                .offset(y: 28)
                .blur(radius: 4)
        }
    }
}
