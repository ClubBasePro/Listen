import MediaPlayer
import UIKit

/// Lock screen, Control Centre, AirPods and CarPlay-style remote controls.
extension AudioPlayer {
    func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.resume() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.togglePlayPause() }
            return .success
        }
        center.skipBackwardCommand.addTarget { [weak self] event in
            let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? 15
            MainActor.assumeIsolated { self?.skip(by: -interval) }
            return .success
        }
        center.skipForwardCommand.addTarget { [weak self] event in
            let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? 30
            MainActor.assumeIsolated { self?.skip(by: interval) }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = event.positionTime
            MainActor.assumeIsolated {
                guard let self else { return }
                self.seek(to: self.chapterRange.lowerBound + position)
            }
            return .success
        }
        center.changePlaybackRateCommand.supportedPlaybackRates = Self.rates.map { NSNumber(value: $0) }
        center.changePlaybackRateCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackRateCommandEvent else { return .commandFailed }
            let rate = event.playbackRate
            MainActor.assumeIsolated { self?.setRate(rate) }
            return .success
        }

        // Skip buttons instead of next/previous track on the lock screen.
        center.nextTrackCommand.isEnabled = false
        center.previousTrackCommand.isEnabled = false
        updateSkipIntervals()
    }

    func updateSkipIntervals() {
        let center = MPRemoteCommandCenter.shared()
        center.skipBackwardCommand.preferredIntervals = [NSNumber(value: skipBackInterval)]
        center.skipForwardCommand.preferredIntervals = [NSNumber(value: skipForwardInterval)]
    }

    func updateNowPlaying() {
        guard let book else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        let range = chapterRange
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: chapters.count > 1 ? chapterTitle : book.title,
            MPMediaItemPropertyArtist: book.author.isEmpty ? book.title : book.author,
            MPMediaItemPropertyAlbumTitle: book.title,
            MPMediaItemPropertyPlaybackDuration: max(0, range.upperBound - range.lowerBound),
            MPNowPlayingInfoPropertyElapsedPlaybackTime: max(0, currentTime - range.lowerBound),
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(rate) : 0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: Double(rate),
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if let index = currentChapterIndex {
            info[MPNowPlayingInfoPropertyChapterNumber] = index
            info[MPNowPlayingInfoPropertyChapterCount] = chapters.count
        }
        if let artwork {
            info[MPMediaItemPropertyArtwork] = Self.makeArtwork(artwork)
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// Nonisolated so the image closure isn't bound to the main actor; iOS calls it on a background queue.
    nonisolated private static func makeArtwork(_ image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }
}
