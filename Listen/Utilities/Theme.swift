import SwiftUI
import UIKit

enum SettingsKey {
    static let owner = "repoOwner"
    static let repo = "repoName"
    static let branch = "repoBranch"
    static let skipBack = "skipBack"
    static let skipForward = "skipForward"
    static let rate = "playbackRate"
}

enum Theme {
    static let accent = Color(hex: 0xEBA75C)
    static let ribbon = Color(hex: 0xB3262E)

    static let wallTop = Color(hex: 0x2E1F16)
    static let wallMid = Color(hex: 0x1B120D)
    static let wallBottom = Color(hex: 0x0E0907)

    static let woodLight = Color(hex: 0x9A6238)
    static let woodMid = Color(hex: 0x6E4122)
    static let woodDark = Color(hex: 0x3F2413)

    /// Width / height of a book on the shelf.
    static let bookAspect: CGFloat = 0.68
    static let bookShape = UnevenRoundedRectangle(topLeadingRadius: 2, bottomLeadingRadius: 2,
                                                  bottomTrailingRadius: 6, topTrailingRadius: 6,
                                                  style: .continuous)
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

/// Deterministic RNG so procedural textures look identical on every render.
struct SeededRandom: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Buttons that sink slightly when pressed.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.94

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// Books tilt out towards you when pressed, like pulling one off the shelf.
struct BookPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .rotation3DEffect(.degrees(configuration.isPressed ? -14 : 0), axis: (x: 0, y: 1, z: 0),
                              anchor: .leading, perspective: 0.5)
            .scaleEffect(configuration.isPressed ? 1.04 : 1, anchor: .bottom)
            .animation(.spring(response: 0.3, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

struct ProgressBar: View {
    let value: Double
    var track: Color = .white.opacity(0.15)
    var fill: Color = Theme.accent

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(fill).frame(width: geo.size.width * min(max(value, 0), 1))
            }
        }
    }
}
