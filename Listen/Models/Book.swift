import Foundation
import SwiftData

/// A book on the shelf, plus its listening progress. Everything here lives on-device.
@Model
final class Book {
    /// `<owner>/<repo>@<branch>:<path>` — stable across syncs.
    @Attribute(.unique) var sourceID: String
    var repoKey: String
    var title: String
    var author: String
    var coverURL: String
    var trackURLs: [String]
    var trackNames: [String]
    var addedAt: Date

    // Progress
    var trackIndex: Int
    var position: Double
    var trackDuration: Double
    var lastPlayed: Date?
    var isFinished: Bool
    var chapterTitle: String

    init(sourceID: String, repoKey: String, title: String, author: String,
         trackURLs: [String], trackNames: [String]) {
        self.sourceID = sourceID
        self.repoKey = repoKey
        self.title = title
        self.author = author
        self.coverURL = ""
        self.trackURLs = trackURLs
        self.trackNames = trackNames
        self.addedAt = .now
        self.trackIndex = 0
        self.position = 0
        self.trackDuration = 0
        self.lastPlayed = nil
        self.isFinished = false
        self.chapterTitle = ""
    }
}

extension Book {
    var isMultiTrack: Bool { trackURLs.count > 1 }
    var hasStarted: Bool { lastPlayed != nil && !isFinished }

    var progress: Double {
        isFinished ? 1 : ProgressMath.fraction(trackIndex: trackIndex, trackCount: trackURLs.count,
                                               position: position, duration: trackDuration)
    }

    var progressCaption: String {
        if isFinished { return "Finished" }
        let percent = "\(Int((progress * 100).rounded()))%"
        if isMultiTrack { return "\(percent) · Part \(trackIndex + 1) of \(trackURLs.count)" }
        if trackDuration > 0 { return "\(percent) · \(TimeFormat.short(trackDuration - position)) left" }
        return percent
    }
}
