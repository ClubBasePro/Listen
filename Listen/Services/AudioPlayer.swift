import AVFoundation
import Observation
import SwiftData
import SwiftUI

struct Chapter: Identifiable, Equatable {
    let id: Int
    let title: String
    /// Seconds within the track. Zero for per-file chapters of multi-track books.
    let start: Double
    let end: Double
}

enum SleepTimer: Equatable {
    case off
    case minutes(Int)
    case endOfChapter
}

/// Streams one book at a time, tracks chapters, and writes progress back to the `Book`.
@MainActor
@Observable
final class AudioPlayer {
    static let rates: [Float] = [0.75, 1, 1.1, 1.2, 1.25, 1.5, 1.75, 2, 2.5, 3]

    private(set) var book: Book?
    private(set) var trackIndex = 0
    private(set) var currentTime: Double = 0
    private(set) var trackDuration: Double = 0
    private(set) var isPlaying = false
    private(set) var isBuffering = false
    /// True between choosing a book and the stream being ready to play.
    private(set) var isLoading = false
    private(set) var rate: Float = 1
    private(set) var embeddedChapters: [Chapter] = []
    private(set) var artwork: UIImage?
    private(set) var tint: Color = Theme.accent
    private(set) var sleepTimer: SleepTimer = .off
    private(set) var sleepDeadline: Date?
    private(set) var errorMessage: String?

    @ObservationIgnored var modelContext: ModelContext?
    let player = AVPlayer()
    @ObservationIgnored private var pendingSeek: Double?
    @ObservationIgnored private var autoplayWhenReady = false
    @ObservationIgnored private var lastSave = Date.distantPast
    @ObservationIgnored private var lastChapterIndex: Int?
    @ObservationIgnored private var sleepChapterIndex: Int?
    @ObservationIgnored private var sleepTask: Task<Void, Never>?
    @ObservationIgnored private var metadataTask: Task<Void, Never>?
    @ObservationIgnored private var artworkTask: Task<Void, Never>?
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var itemObservation: NSKeyValueObservation?
    @ObservationIgnored private var itemEndObserver: NSObjectProtocol?
    @ObservationIgnored private var tokens: [Any] = []

    init() {
        let saved = Float(UserDefaults.standard.double(forKey: SettingsKey.rate))
        rate = saved > 0 ? saved : 1
        player.defaultRate = rate
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, policy: .longFormAudio)
        observePlayer()
        setupRemoteCommands()
    }

    // MARK: - Derived state

    var isMultiTrack: Bool { (book?.trackURLs.count ?? 0) > 1 }

    /// True when the user has asked to play, even if audio is still buffering.
    var wantsToPlay: Bool { isPlaying || isLoading }

    var chapters: [Chapter] {
        guard let book else { return [] }
        if book.isMultiTrack {
            return book.trackNames.enumerated().map { Chapter(id: $0, title: $1, start: 0, end: 0) }
        }
        return embeddedChapters
    }

    var currentChapterIndex: Int? {
        if isMultiTrack { return trackIndex }
        guard !embeddedChapters.isEmpty else { return nil }
        return embeddedChapters.lastIndex { $0.start <= currentTime + 0.25 } ?? 0
    }

    /// The part of the current track the scrubber covers: the chapter, or the whole track.
    var chapterRange: ClosedRange<Double> {
        guard !isMultiTrack, let index = currentChapterIndex else { return 0...max(trackDuration, 0) }
        let chapter = embeddedChapters[index]
        let end = chapter.end > chapter.start ? chapter.end : trackDuration
        return chapter.start...max(end, chapter.start)
    }

    var chapterTitle: String {
        if let index = currentChapterIndex, chapters.indices.contains(index) { return chapters[index].title }
        return book?.title ?? ""
    }

    var chapterCaption: String? {
        guard let index = currentChapterIndex, chapters.count > 1 else { return nil }
        return "\(index + 1) of \(chapters.count)"
    }

    var skipBackInterval: Double { interval(SettingsKey.skipBack, fallback: 15) }
    var skipForwardInterval: Double { interval(SettingsKey.skipForward, fallback: 30) }

    private func interval(_ key: String, fallback: Double) -> Double {
        let value = UserDefaults.standard.double(forKey: key)
        return value > 0 ? value : fallback
    }

    // MARK: - Transport

    /// Starts (or resumes) a book from its saved position.
    func play(_ book: Book) {
        if self.book?.sourceID == book.sourceID {
            resume()
            return
        }
        saveProgress()
        setSleepTimer(.off)
        self.book = book
        errorMessage = nil
        embeddedChapters = []
        lastChapterIndex = nil
        if book.isFinished {
            book.isFinished = false
            book.trackIndex = 0
            book.position = 0
        }
        let index = book.trackURLs.indices.contains(book.trackIndex) ? book.trackIndex : 0
        load(track: index, at: ProgressMath.resumePosition(from: book.position),
             knownDuration: book.trackDuration, autoplay: true)
        refreshArtwork()
    }

    func resume() {
        guard let book, player.currentItem != nil else { return }
        if book.isFinished { book.isFinished = false }
        try? AVAudioSession.sharedInstance().setActive(true)
        if pendingSeek != nil {
            autoplayWhenReady = true
            isLoading = true
            return
        }
        player.defaultRate = rate
        player.play()
    }

    func pause() {
        autoplayWhenReady = false
        isLoading = false
        player.pause()
        saveProgress()
    }

    func togglePlayPause() {
        wantsToPlay ? pause() : resume()
    }

    /// Unloads the current book without saving (used after marking finished / resetting).
    func stop() {
        setSleepTimer(.off)
        player.pause()
        player.replaceCurrentItem(with: nil)
        book = nil
        isLoading = false
        embeddedChapters = []
        artwork = nil
        updateNowPlaying()
    }

    func seek(to time: Double) {
        let upper = trackDuration > 1 ? trackDuration - 1 : max(time, 0)
        let target = min(max(time, 0), upper)
        currentTime = target
        if pendingSeek != nil {
            pendingSeek = target
            return
        }
        let tolerance = CMTime(seconds: 0.5, preferredTimescale: 600)
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600),
                    toleranceBefore: tolerance, toleranceAfter: tolerance) { [weak self] _ in
            Task { @MainActor in self?.updateNowPlaying() }
        }
        saveProgress()
    }

    func skip(by delta: Double) {
        guard let book else { return }
        let target = currentTime + delta
        if trackDuration > 0, target >= trackDuration, trackIndex + 1 < book.trackURLs.count {
            load(track: trackIndex + 1, at: target - trackDuration, knownDuration: 0, autoplay: wantsToPlay)
            return
        }
        seek(to: target)
    }

    func jump(toChapter index: Int) {
        if isMultiTrack {
            guard let book, book.trackURLs.indices.contains(index) else { return }
            load(track: index, at: 0, knownDuration: 0, autoplay: true)
        } else if embeddedChapters.indices.contains(index) {
            seek(to: embeddedChapters[index].start + 0.05)
            resume()
        }
        saveProgress()
    }

    func nextChapter() {
        guard let index = currentChapterIndex else {
            skip(by: skipForwardInterval)
            return
        }
        if index + 1 < chapters.count { jump(toChapter: index + 1) }
    }

    func previousChapter() {
        guard let index = currentChapterIndex else {
            seek(to: 0)
            return
        }
        if currentTime - chapterRange.lowerBound > 3 || index == 0 {
            jump(toChapter: index)
        } else {
            jump(toChapter: index - 1)
        }
    }

    func setRate(_ newRate: Float) {
        rate = newRate
        UserDefaults.standard.set(Double(newRate), forKey: SettingsKey.rate)
        player.defaultRate = newRate
        if isPlaying { player.rate = newRate }
        updateNowPlaying()
    }

    // MARK: - Sleep timer

    func setSleepTimer(_ timer: SleepTimer) {
        sleepTask?.cancel()
        sleepTask = nil
        sleepTimer = timer
        sleepDeadline = nil
        sleepChapterIndex = nil
        player.volume = 1

        switch timer {
        case .off:
            break
        case .minutes(let minutes):
            let seconds = minutes * 60
            sleepDeadline = Date().addingTimeInterval(TimeInterval(seconds))
            sleepTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(max(0, seconds - 10)))
                guard !Task.isCancelled else { return }
                await self?.fadeOutAndPause()
            }
        case .endOfChapter:
            sleepChapterIndex = currentChapterIndex
        }
    }

    /// Fades out over ten seconds rather than cutting off mid-sentence.
    private func fadeOutAndPause() async {
        for step in stride(from: 1.0, through: 0.0, by: -0.05) {
            guard !Task.isCancelled else { return }
            player.volume = Float(step)
            try? await Task.sleep(for: .milliseconds(500))
        }
        guard !Task.isCancelled else { return }
        pause()
        setSleepTimer(.off)
    }

    // MARK: - Library actions

    func markFinished(_ target: Book) {
        if target.sourceID == book?.sourceID {
            pause()
            stop()
        }
        target.isFinished = true
        target.trackIndex = 0
        target.position = 0
        target.lastPlayed = target.lastPlayed ?? .now
        try? modelContext?.save()
    }

    func resetProgress(_ target: Book) {
        if target.sourceID == book?.sourceID { stop() }
        target.isFinished = false
        target.trackIndex = 0
        target.position = 0
        target.lastPlayed = nil
        target.chapterTitle = ""
        try? modelContext?.save()
    }

    func saveProgress() {
        guard let book, !book.isFinished, player.currentItem != nil else { return }
        book.trackIndex = trackIndex
        book.position = currentTime
        if trackDuration > 0 { book.trackDuration = trackDuration }
        book.lastPlayed = .now
        book.chapterTitle = chapters.count > 1 ? chapterTitle : ""
        try? modelContext?.save()
        lastSave = .now
    }

    func refreshArtwork() {
        guard let book else { return }
        artworkTask?.cancel()
        let title = book.title, author = book.author, cover = book.coverURL
        artworkTask = Task { [weak self] in
            var image: UIImage?
            if let url = URL(string: cover.trimmingCharacters(in: .whitespaces)), url.scheme?.hasPrefix("http") == true {
                image = await ImageCache.shared.image(for: url)
            }
            guard !Task.isCancelled, let self else { return }
            let tintSource = image?.averageColor ?? CoverPalette.for(title).base
            withAnimation(.easeInOut(duration: 0.6)) {
                self.artwork = image ?? GeneratedCover.render(title: title, author: author)
                self.tint = Color(uiColor: tintSource.playerTint)
            }
            self.updateNowPlaying()
        }
    }

    // MARK: - Loading

    private func load(track index: Int, at time: Double, knownDuration: Double, autoplay: Bool) {
        guard let book, book.trackURLs.indices.contains(index),
              let url = URL(string: book.trackURLs[index]) else { return }

        trackIndex = index
        currentTime = time
        trackDuration = knownDuration
        errorMessage = nil
        pendingSeek = time > 0 ? time : nil
        autoplayWhenReady = autoplay
        isLoading = autoplay

        // GitHub serves LFS files as application/octet-stream, so tell AVFoundation what they are.
        let mime = url.pathExtension.lowercased() == "mp3" ? "audio/mpeg" : "audio/mp4"
        let asset = AVURLAsset(url: url, options: [AVURLAssetOverrideMIMETypeKey: mime])
        let item = AVPlayerItem(asset: asset)
        item.audioTimePitchAlgorithm = .spectral
        observe(item)
        player.replaceCurrentItem(with: item)

        metadataTask?.cancel()
        metadataTask = Task { [weak self] in await self?.loadMetadata(asset, index: index) }
        updateNowPlaying()
    }

    private func loadMetadata(_ asset: AVURLAsset, index: Int) async {
        if let duration = try? await asset.load(.duration), duration.seconds.isFinite, duration.seconds > 0,
           index == trackIndex {
            trackDuration = duration.seconds
        }
        guard !Task.isCancelled, book?.isMultiTrack == false else { return }

        guard let groups = try? await asset.loadChapterMetadataGroups(
            bestMatchingPreferredLanguages: Locale.preferredLanguages), !Task.isCancelled else { return }

        var result: [Chapter] = []
        for (i, group) in groups.enumerated() {
            var title: String?
            if let item = AVMetadataItem.metadataItems(from: group.items,
                                                       filteredByIdentifier: .commonIdentifierTitle).first {
                title = try? await item.load(.stringValue)
            }
            let start = group.timeRange.start.seconds
            let end = group.timeRange.end.seconds
            result.append(Chapter(id: i, title: title?.isEmpty == false ? title! : "Chapter \(i + 1)",
                                  start: start.isFinite ? start : 0, end: end.isFinite ? end : 0))
        }
        guard !Task.isCancelled else { return }
        embeddedChapters = result
        updateNowPlaying()
    }

    // MARK: - Observation

    private func observe(_ item: AVPlayerItem) {
        if let itemEndObserver { NotificationCenter.default.removeObserver(itemEndObserver) }
        itemEndObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.itemDidEnd() }
        }
        itemObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            let status = item.status
            let message = item.error?.localizedDescription
            Task { @MainActor in self?.itemStatusChanged(status, error: message) }
        }
    }

    private func itemStatusChanged(_ status: AVPlayerItem.Status, error: String?) {
        switch status {
        case .readyToPlay:
            if let duration = player.currentItem?.duration.seconds, duration.isFinite, duration > 0 {
                trackDuration = duration
            }
            let autoplay = autoplayWhenReady
            autoplayWhenReady = false
            if let target = pendingSeek {
                let tolerance = CMTime(seconds: 0.5, preferredTimescale: 600)
                player.seek(to: CMTime(seconds: currentTime > 0 ? currentTime : target, preferredTimescale: 600),
                            toleranceBefore: tolerance, toleranceAfter: tolerance) { [weak self] _ in
                    Task { @MainActor in
                        guard let self else { return }
                        self.pendingSeek = nil
                        if autoplay || self.autoplayWhenReady { self.resume() } else { self.isLoading = false }
                    }
                }
            } else if autoplay {
                resume()
            } else {
                isLoading = false
            }
        case .failed:
            pendingSeek = nil
            isLoading = false
            errorMessage = "Couldn't stream this file. Check your connection and that it's stored with Git LFS."
                + (error.map { "\n\($0)" } ?? "")
        default:
            break
        }
    }

    private func itemDidEnd() {
        guard let book else { return }
        if trackIndex + 1 < book.trackURLs.count {
            let stopHere = sleepTimer == .endOfChapter
            if stopHere { setSleepTimer(.off) }
            load(track: trackIndex + 1, at: 0, knownDuration: 0, autoplay: !stopHere)
            saveProgress()
        } else {
            setSleepTimer(.off)
            book.isFinished = true
            book.trackIndex = 0
            book.position = 0
            book.lastPlayed = .now
            try? modelContext?.save()
            updateNowPlaying()
        }
    }

    private func observePlayer() {
        statusObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            let status = player.timeControlStatus
            Task { @MainActor in self?.timeControlChanged(status) }
        }

        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        tokens.append(player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.tick(time.seconds) }
        })

        let center = NotificationCenter.default
        tokens.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil,
                                         queue: .main) { [weak self] note in
            let info = note.userInfo ?? [:]
            let type = (info[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap { AVAudioSession.InterruptionType(rawValue: $0) }
            let options = AVAudioSession.InterruptionOptions(rawValue: info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
            MainActor.assumeIsolated {
                if type == .began {
                    self?.saveProgress()
                } else if type == .ended, options.contains(.shouldResume) {
                    self?.resume()
                }
            }
        })
        tokens.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil,
                                         queue: .main) { [weak self] note in
            let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt)
                .flatMap { AVAudioSession.RouteChangeReason(rawValue: $0) }
            guard reason == .oldDeviceUnavailable else { return }
            MainActor.assumeIsolated { self?.pause() }  // headphones unplugged
        })
    }

    private func timeControlChanged(_ status: AVPlayer.TimeControlStatus) {
        let wasPlaying = isPlaying
        isPlaying = status != .paused
        isBuffering = status == .waitingToPlayAtSpecifiedRate
        if status == .playing { isLoading = false }
        if wasPlaying, !isPlaying { saveProgress() }
        updateNowPlaying()
    }

    private func tick(_ seconds: Double) {
        guard seconds.isFinite, pendingSeek == nil, player.currentItem != nil else { return }
        currentTime = seconds
        if let duration = player.currentItem?.duration.seconds, duration.isFinite, duration > 0 {
            trackDuration = duration
        }

        let chapter = currentChapterIndex
        if chapter != lastChapterIndex {
            lastChapterIndex = chapter
            updateNowPlaying()
            if sleepTimer == .endOfChapter, let stopAt = sleepChapterIndex, chapter != stopAt, isPlaying {
                pause()
                setSleepTimer(.off)
            }
        }

        if isPlaying, Date().timeIntervalSince(lastSave) >= 5 { saveProgress() }
    }
}
