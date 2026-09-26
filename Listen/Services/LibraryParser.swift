import Foundation

/// Which GitHub repo + branch the library is read from.
struct RepoConfig: Equatable, Sendable {
    var owner: String
    var repo: String
    var branch: String

    var isValid: Bool { !owner.isEmpty && !repo.isEmpty && !branch.isEmpty }
    var key: String { "\(owner)/\(repo)@\(branch)" }

    /// Accepts `owner/repo`, `github.com/owner/repo`, full URLs, `.git` suffixes
    /// and `/tree/<branch>` links. Returns nil if no owner/repo can be found.
    static func parse(_ input: String, defaultBranch: String = "main") -> RepoConfig? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["https://", "http://", "www.", "github.com/"] where text.lowercased().hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count))
        }
        if text.hasSuffix(".git") { text = String(text.dropLast(4)) }
        let parts = text.split(separator: "/").map(String.init)
        guard parts.count >= 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
        var branch = defaultBranch.trimmingCharacters(in: .whitespaces)
        if parts.count > 3, parts[2] == "tree" {
            branch = parts[3...].joined(separator: "/")
        }
        if branch.isEmpty { branch = "main" }
        return RepoConfig(owner: parts[0], repo: parts[1], branch: branch)
    }
}

/// A book discovered in the repo, before it is stored.
struct BookSource: Equatable, Sendable {
    /// Repo path of the .m4b file, or the folder path (with trailing slash) for multi-file books.
    var id: String
    var title: String
    var author: String
    var trackPaths: [String]
}

enum LibraryParser {
    static let singleFileExtensions: Set<String> = ["m4b"]
    static let trackExtensions: Set<String> = ["mp3", "m4a"]

    /// Groups repo file paths into books: every .m4b is its own book, every folder
    /// of .mp3/.m4a files is one book whose tracks are in natural filename order.
    static func books(from paths: [String]) -> [BookSource] {
        var books: [BookSource] = []
        var folders: [String: [String]] = [:]

        for path in paths {
            let file = path as NSString
            let name = file.lastPathComponent
            guard !name.hasPrefix(".") else { continue }
            let ext = file.pathExtension.lowercased()
            let folder = file.deletingLastPathComponent

            if singleFileExtensions.contains(ext) || (trackExtensions.contains(ext) && folder.isEmpty) {
                books.append(makeBook(id: path, name: (name as NSString).deletingPathExtension, tracks: [path]))
            } else if trackExtensions.contains(ext) {
                folders[folder, default: []].append(path)
            }
        }

        for (folder, tracks) in folders {
            let name = (folder as NSString).lastPathComponent
            books.append(makeBook(id: folder + "/", name: name, tracks: tracks.sorted(by: naturalOrder)))
        }

        return books.sorted { naturalOrder($0.title, $1.title) }
    }

    static func naturalOrder(_ a: String, _ b: String) -> Bool {
        a.localizedStandardCompare(b) == .orderedAscending
    }

    private static func makeBook(id: String, name: String, tracks: [String]) -> BookSource {
        let parsed = titleAndAuthor(from: name)
        return BookSource(id: id, title: parsed.title, author: parsed.author, trackPaths: tracks)
    }

    /// "Author - Title" → (Title, Author). Anything else is treated as just a title.
    static func titleAndAuthor(from name: String) -> (title: String, author: String) {
        let cleaned = clean(name)
        if let range = cleaned.range(of: " - ") {
            let author = cleaned[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
            let title = cleaned[range.upperBound...].trimmingCharacters(in: .whitespaces)
            if !author.isEmpty, !title.isEmpty { return (title, author) }
        }
        return (cleaned, "")
    }

    /// Friendly chapter name for a track file: "03 - The Road.mp3" → "The Road".
    static func trackName(for path: String, index: Int) -> String {
        let base = clean(((path as NSString).lastPathComponent as NSString).deletingPathExtension)
        if let match = base.range(of: #"^\d{1,3}(\s*[-._)]\s*|\s+)"#, options: .regularExpression) {
            let rest = base[match.upperBound...].trimmingCharacters(in: .whitespaces)
            if !rest.isEmpty { return rest }
        }
        if base.isEmpty || (base.count <= 3 && base.allSatisfy(\.isNumber)) { return "Part \(index + 1)" }
        return base
    }

    private static func clean(_ text: String) -> String {
        text.replacingOccurrences(of: "_", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    // MARK: URLs

    /// Git LFS content URL. raw.githubusercontent.com would return the LFS pointer file,
    /// media.githubusercontent.com returns the real audio and supports range requests.
    static func mediaURL(for path: String, in repo: RepoConfig) -> URL {
        let parts = [repo.owner, repo.repo] + repo.branch.split(separator: "/").map(String.init)
            + path.split(separator: "/").map(String.init)
        return URL(string: "https://media.githubusercontent.com/media/" + parts.map(encode).joined(separator: "/"))!
    }

    static func treeURL(for repo: RepoConfig) -> URL {
        let parts = [repo.owner, repo.repo].map(encode).joined(separator: "/")
        return URL(string: "https://api.github.com/repos/\(parts)/git/trees/\(encode(repo.branch))?recursive=1")!
    }

    private static let segmentAllowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))

    private static func encode(_ segment: String) -> String {
        segment.addingPercentEncoding(withAllowedCharacters: segmentAllowed) ?? segment
    }
}
