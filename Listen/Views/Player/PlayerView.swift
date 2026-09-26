import AVKit
import SwiftUI

struct PlayerView: View {
    @Environment(AudioPlayer.self) private var player
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.skipBack) private var skipBack = 15
    @AppStorage(SettingsKey.skipForward) private var skipForward = 30
    @State private var showChapters = false
    @State private var editingBook: Book?

    var body: some View {
        ZStack {
            PlayerBackground(image: player.artwork, tint: player.tint)

            if let book = player.book {
                VStack(spacing: 0) {
                    topBar(book)
                    Spacer(minLength: 12)
                    cover(book)
                    Spacer(minLength: 20)
                    titles(book)
                    if let error = player.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(Color(hex: 0xFFB4A8))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 8)
                    }
                    Scrubber(range: player.chapterRange, time: player.currentTime,
                             caption: player.chapterCaption) { player.seek(to: $0) }
                        .padding(.top, 18)
                    transport.padding(.top, 14)
                    Spacer(minLength: 18)
                    accessories
                }
                .padding(.horizontal, 26)
                .padding(.bottom, 6)
                .foregroundStyle(.white)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "books.vertical").font(.largeTitle)
                    Text("Nothing playing").font(.headline)
                    Button("Close") { dismiss() }.buttonStyle(.bordered)
                }
                .foregroundStyle(.white)
            }
        }
        .sheet(isPresented: $showChapters) {
            ChapterList()
                .presentationDetents([.medium, .large])
                .presentationBackground(.thinMaterial)
                .presentationCornerRadius(28)
        }
        .sheet(item: $editingBook) { BookEditView(book: $0) }
        .onChange(of: player.book == nil) { _, isEmpty in
            if isEmpty { dismiss() }
        }
    }

    // MARK: Sections

    private func topBar(_ book: Book) -> some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 18, weight: .bold))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Close player")
            Spacer()
            VStack(spacing: 2) {
                Text("PLAYING FROM YOUR SHELF")
                    .font(.caption2.weight(.bold))
                    .tracking(1.2)
                    .opacity(0.6)
                Text(book.title).font(.footnote.weight(.semibold)).lineLimit(1)
            }
            Spacer()
            Menu {
                Button("Chapters", systemImage: "list.bullet") { showChapters = true }
                Button("Edit Details", systemImage: "pencil") { editingBook = book }
                Divider()
                Button("Mark as Finished", systemImage: "checkmark.circle") { player.markFinished(book) }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .bold))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("More")
        }
        .buttonStyle(PressableStyle())
    }

    private func cover(_ book: Book) -> some View {
        let active = player.wantsToPlay
        return CoverImage(url: book.coverURL, title: book.title, author: book.author)
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.08)))
            .shadow(color: .black.opacity(active ? 0.5 : 0.3), radius: active ? 34 : 14, y: active ? 22 : 8)
            .scaleEffect(active ? 1 : 0.82)
            .animation(.spring(response: 0.5, dampingFraction: 0.72), value: active)
            .frame(maxWidth: .infinity)
    }

    private func titles(_ book: Book) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if player.chapters.count > 1 {
                Button { showChapters = true } label: {
                    HStack(spacing: 4) {
                        Text(player.chapterTitle).lineLimit(1)
                        Image(systemName: "chevron.right").font(.caption2.weight(.bold))
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
                }
            }
            Text(book.title)
                .font(.system(.title2, design: .serif).weight(.bold))
                .lineLimit(2)
            if !book.author.isEmpty {
                Text(book.author).font(.body).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var transport: some View {
        HStack {
            Button { player.previousChapter() } label: {
                Image(systemName: "backward.end.fill").font(.system(size: 22))
            }
            .accessibilityLabel("Previous chapter")
            Spacer()
            Button { player.skip(by: -Double(skipBack)) } label: {
                Image(systemName: "gobackward.\(skipBack)").font(.system(size: 30, weight: .medium))
            }
            .accessibilityLabel("Back \(skipBack) seconds")
            Spacer()
            playButton
            Spacer()
            Button { player.skip(by: Double(skipForward)) } label: {
                Image(systemName: "goforward.\(skipForward)").font(.system(size: 30, weight: .medium))
            }
            .accessibilityLabel("Forward \(skipForward) seconds")
            Spacer()
            Button { player.nextChapter() } label: {
                Image(systemName: "forward.end.fill").font(.system(size: 22))
            }
            .accessibilityLabel("Next chapter")
        }
        .buttonStyle(PressableStyle(scale: 0.85))
    }

    private var playButton: some View {
        Button { player.togglePlayPause() } label: {
            ZStack {
                Circle().fill(.white)
                    .shadow(color: player.tint.opacity(0.6), radius: 20)
                Image(systemName: player.wantsToPlay ? "pause.fill" : "play.fill")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.black)
                    .contentTransition(.symbolEffect(.replace.downUp))
                    .offset(x: player.wantsToPlay ? 0 : 2)
                if player.isLoading || player.isBuffering {
                    SpinnerRing().frame(width: 88, height: 88)
                }
            }
            .frame(width: 76, height: 76)
        }
        .accessibilityLabel(player.wantsToPlay ? "Pause" : "Play")
        .sensoryFeedback(.impact(weight: .medium), trigger: player.wantsToPlay)
    }

    private var accessories: some View {
        HStack {
            Menu {
                ForEach(AudioPlayer.rates.reversed(), id: \.self) { rate in
                    Button {
                        player.setRate(rate)
                    } label: {
                        if rate == player.rate {
                            Label(TimeFormat.rate(rate), systemImage: "checkmark")
                        } else {
                            Text(TimeFormat.rate(rate))
                        }
                    }
                }
            } label: {
                AccessoryLabel(active: player.rate != 1) {
                    Text(TimeFormat.rate(player.rate)).font(.system(size: 15, weight: .bold).monospacedDigit())
                }
            }
            .accessibilityLabel("Playback speed")

            Spacer()

            Menu {
                sleepOption("Off", .off)
                sleepOption("End of Chapter", .endOfChapter)
                Divider()
                ForEach([5, 10, 15, 30, 45, 60, 90], id: \.self) { minutes in
                    sleepOption("\(minutes) minutes", .minutes(minutes))
                }
            } label: {
                AccessoryLabel(active: player.sleepTimer != .off) { sleepLabel }
            }
            .accessibilityLabel("Sleep timer")

            Spacer()

            AirPlayButton().frame(width: 44, height: 44)

            Spacer()

            Button { showChapters = true } label: {
                AccessoryLabel(active: false) { Image(systemName: "list.bullet").font(.system(size: 17, weight: .semibold)) }
            }
            .accessibilityLabel("Chapters")
        }
        .buttonStyle(PressableStyle())
    }

    private func sleepOption(_ title: String, _ timer: SleepTimer) -> some View {
        Button {
            player.setSleepTimer(timer)
        } label: {
            if player.sleepTimer == timer {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    @ViewBuilder
    private var sleepLabel: some View {
        switch player.sleepTimer {
        case .off:
            Image(systemName: "moon.zzz").font(.system(size: 17, weight: .semibold))
        case .endOfChapter:
            HStack(spacing: 4) {
                Image(systemName: "moon.zzz.fill")
                Text("Chapter")
            }
            .font(.system(size: 14, weight: .semibold))
        case .minutes:
            HStack(spacing: 4) {
                Image(systemName: "moon.zzz.fill")
                if let deadline = player.sleepDeadline, deadline > .now {
                    Text(timerInterval: Date.now...deadline, countsDown: true)
                        .monospacedDigit()
                }
            }
            .font(.system(size: 14, weight: .semibold))
        }
    }
}

// MARK: - Pieces

struct AccessoryLabel<Content: View>: View {
    let active: Bool
    @ViewBuilder let content: Content

    var body: some View {
        content
            .foregroundStyle(active ? Color.black : .white.opacity(0.85))
            .padding(.horizontal, 12)
            .frame(minWidth: 44, minHeight: 34)
            .background(Capsule().fill(active ? Theme.accent : .white.opacity(0.12)))
            .animation(.snappy, value: active)
    }
}

struct PlayerBackground: View {
    let image: UIImage?
    let tint: Color

    var body: some View {
        Color.black
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .blur(radius: 70)
                        .scaleEffect(1.4)
                        .opacity(0.8)
                }
            }
            .overlay {
                LinearGradient(colors: [tint.opacity(0.55), tint.opacity(0.2), .black.opacity(0.85)],
                               startPoint: .top, endPoint: .bottom)
            }
            .clipped()
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.6), value: image)
    }
}

struct Scrubber: View {
    let range: ClosedRange<Double>
    let time: Double
    let caption: String?
    let onSeek: (Double) -> Void

    @State private var dragTime: Double?

    var body: some View {
        let length = max(range.upperBound - range.lowerBound, 0.001)
        let shown = min(max(dragTime ?? time, range.lowerBound), range.upperBound)
        let fraction = (shown - range.lowerBound) / length
        let dragging = dragTime != nil

        VStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.22))
                    Capsule().fill(.white).frame(width: max(geo.size.width * fraction, dragging ? 12 : 7))
                }
                .frame(height: dragging ? 12 : 7)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let f = min(max(value.location.x / max(geo.size.width, 1), 0), 1)
                            dragTime = range.lowerBound + f * length
                        }
                        .onEnded { _ in
                            if let dragTime { onSeek(dragTime) }
                            dragTime = nil
                        }
                )
            }
            .frame(height: 26)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: dragging)

            HStack {
                Text(TimeFormat.clock(shown - range.lowerBound))
                Spacer()
                if let caption { Text(caption) }
                Spacer()
                Text("-" + TimeFormat.clock(range.upperBound - shown))
            }
            .font(.caption.weight(.medium).monospacedDigit())
            .foregroundStyle(.white.opacity(dragging ? 0.95 : 0.6))
        }
        .sensoryFeedback(.selection, trigger: dragging)
        .accessibilityElement()
        .accessibilityLabel("Position")
        .accessibilityValue("\(TimeFormat.clock(shown - range.lowerBound)) of \(TimeFormat.clock(length))")
        .accessibilityAdjustableAction { direction in
            onSeek(time + (direction == .increment ? 30 : -15))
        }
    }
}

struct SpinnerRing: View {
    var body: some View {
        TimelineView(.animation) { context in
            let angle = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1) * 360
            Circle()
                .trim(from: 0, to: 0.28)
                .stroke(.white.opacity(0.85), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(angle))
        }
    }
}

struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = UIColor.white.withAlphaComponent(0.85)
        view.activeTintColor = UIColor(Theme.accent)
        view.prioritizesVideoDevices = false
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
