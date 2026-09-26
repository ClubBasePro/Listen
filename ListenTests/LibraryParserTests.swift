import XCTest
@testable import Listen

final class LibraryParserTests: XCTestCase {
    func testGroupsFoldersAndSingleFiles() {
        let books = LibraryParser.books(from: [
            "README.md",
            "Books/Frank Herbert - Dune.m4b",
            "Books/Project Hail Mary/10 - Ten.mp3",
            "Books/Project Hail Mary/2 - Two.mp3",
            "Books/Project Hail Mary/1 - One.mp3",
            "Books/Project Hail Mary/cover.jpg",
            "Books/.hidden.mp3",
        ])
        XCTAssertEqual(books.map(\.title), ["Dune", "Project Hail Mary"])
        XCTAssertEqual(books[0].author, "Frank Herbert")
        XCTAssertEqual(books[0].trackPaths, ["Books/Frank Herbert - Dune.m4b"])
        XCTAssertEqual(books[1].id, "Books/Project Hail Mary/")
        XCTAssertEqual(books[1].trackPaths.map { ($0 as NSString).lastPathComponent },
                       ["1 - One.mp3", "2 - Two.mp3", "10 - Ten.mp3"])
    }

    func testRootLevelMp3IsItsOwnBook() {
        let books = LibraryParser.books(from: ["Short_Story.mp3"])
        XCTAssertEqual(books.count, 1)
        XCTAssertEqual(books[0].title, "Short Story")
    }

    func testTrackNames() {
        XCTAssertEqual(LibraryParser.trackName(for: "a/03 - The Road.mp3", index: 2), "The Road")
        XCTAssertEqual(LibraryParser.trackName(for: "a/01.mp3", index: 0), "Part 1")
        XCTAssertEqual(LibraryParser.trackName(for: "a/1984.mp3", index: 0), "1984")
        XCTAssertEqual(LibraryParser.trackName(for: "a/Chapter_5.mp3", index: 4), "Chapter 5")
    }

    func testMediaURLEncodesEachSegment() {
        let repo = RepoConfig(owner: "me", repo: "books", branch: "main")
        let url = LibraryParser.mediaURL(for: "Sci Fi/Dune #1.m4b", in: repo)
        XCTAssertEqual(url.absoluteString,
                       "https://media.githubusercontent.com/media/me/books/main/Sci%20Fi/Dune%20%231.m4b")
    }

    func testRepoConfigParsing() {
        XCTAssertEqual(RepoConfig.parse("me/books"), RepoConfig(owner: "me", repo: "books", branch: "main"))
        XCTAssertEqual(RepoConfig.parse("https://github.com/me/books.git"),
                       RepoConfig(owner: "me", repo: "books", branch: "main"))
        XCTAssertEqual(RepoConfig.parse("github.com/me/books/tree/audio/v2"),
                       RepoConfig(owner: "me", repo: "books", branch: "audio/v2"))
        XCTAssertNil(RepoConfig.parse("books"))
    }

    func testProgressAndResume() {
        XCTAssertEqual(ProgressMath.resumePosition(from: 100), 97)
        XCTAssertEqual(ProgressMath.resumePosition(from: 1), 0)
        XCTAssertEqual(ProgressMath.fraction(trackIndex: 0, trackCount: 1, position: 50, duration: 200), 0.25)
        XCTAssertEqual(ProgressMath.fraction(trackIndex: 1, trackCount: 4, position: 30, duration: 60), 0.375)
        XCTAssertEqual(ProgressMath.fraction(trackIndex: 2, trackCount: 4, position: 10, duration: 0), 0.5)
    }

    func testTimeFormatting() {
        XCTAssertEqual(TimeFormat.clock(3723), "1:02:03")
        XCTAssertEqual(TimeFormat.clock(65), "1:05")
        XCTAssertEqual(TimeFormat.rate(1), "1×")
        XCTAssertEqual(TimeFormat.rate(1.25), "1.25×")
        XCTAssertEqual(TimeFormat.rate(1.5), "1.5×")
    }
}
