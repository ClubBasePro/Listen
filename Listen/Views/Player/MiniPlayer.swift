import SwiftUI

/// Floating glass bar above the shelf. Tap or swipe up to open the full player.
struct MiniPlayer: View {
    let namespace: Namespace.ID
    let onOpen: () -> Void

    @Environment(AudioPlayer.self) private var player
    @AppStorage(SettingsKey.skipForward) private var skipForward = 30

    var body: some View {
        if let book = player.book {
            let range = player.chapterRange
            let length = max(range.upperBound - range.lowerBound, 0.001)
            HStack(spacing: 12) {
                CoverImage(url: book.coverURL, title: book.title, author: book.author)
                    .frame(width: 46, height: 46)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .matchedTransitionSource(id: "mini", in: namespace)
                    .shadow(color: .black.opacity(0.3), radius: 4, y: 2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(book.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text(player.chapterTitle == book.title ? book.author : player.chapterTitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
                Spacer(minLength: 6)

                Button { player.togglePlayPause() } label: {
                    Image(systemName: player.wantsToPlay ? "pause.fill" : "play.fill")
                        .font(.system(size: 22, weight: .bold))
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 40, height: 40)
                }
                .accessibilityLabel(player.wantsToPlay ? "Pause" : "Play")

                Button { player.skip(by: Double(skipForward)) } label: {
                    Image(systemName: "goforward.\(skipForward)")
                        .font(.system(size: 20, weight: .semibold))
                        .frame(width: 40, height: 40)
                }
                .accessibilityLabel("Forward \(skipForward) seconds")
            }
            .buttonStyle(PressableStyle(scale: 0.85))
            .foregroundStyle(.white)
            .padding(.leading, 8)
            .padding(.trailing, 10)
            .padding(.vertical, 8)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 22, style: .continuous).fill(player.tint.opacity(0.28))
                }
            }
            .overlay(alignment: .bottom) {
                ProgressBar(value: (player.currentTime - range.lowerBound) / length,
                            track: .white.opacity(0.1), fill: .white.opacity(0.8))
                    .frame(height: 2)
                    .padding(.horizontal, 22)
                    .padding(.bottom, 1)
            }
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.1)))
            .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .onTapGesture(perform: onOpen)
            .gesture(DragGesture(minimumDistance: 16).onEnded { value in
                if value.translation.height < -24 { onOpen() }
            })
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: "Open player", onOpen)
        }
    }
}
