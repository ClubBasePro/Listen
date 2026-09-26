import Foundation

enum ProgressMath {
    /// How far to rewind when resuming, so you hear the last few words again.
    static let resumeRewind: Double = 3

    static func resumePosition(from position: Double) -> Double {
        guard position.isFinite else { return 0 }
        return max(0, position - resumeRewind)
    }

    /// Book-level progress. Multi-track books count each track as an equal share,
    /// because we don't know the lengths of tracks that haven't been streamed yet.
    static func fraction(trackIndex: Int, trackCount: Int, position: Double, duration: Double) -> Double {
        guard trackCount > 0 else { return 0 }
        let withinTrack = duration > 0 ? min(max(position / duration, 0), 1) : 0
        return min(max((Double(trackIndex) + withinTrack) / Double(trackCount), 0), 1)
    }
}

enum TimeFormat {
    /// 1:02:03 or 2:03
    static func clock(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "--:--" }
        let total = Int(max(0, seconds).rounded(.down))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// 3h 12m  /  14m
    static func short(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "–" }
        let total = Int(max(0, seconds))
        let h = total / 3600, m = (total % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(max(m, 1))m"
    }

    static func rate(_ rate: Float) -> String {
        let text = String(format: "%.2f", rate)
            .replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
        return text + "×"
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
