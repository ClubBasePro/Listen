import Foundation
import Observation
import SwiftData

enum GitHubError: LocalizedError {
    case notFound
    case rateLimited(reset: Date?)
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "Repository or branch not found. Check the owner, name and branch in Settings."
        case .rateLimited(let reset):
            let when = reset.map { " Try again \($0.formatted(.relative(presentation: .named)))." } ?? ""
            return "GitHub's hourly limit for anonymous requests was reached.\(when)"
        case .http(let code):
            return "GitHub returned an error (\(code))."
        }
    }
}

enum GitHubAPI {
    private struct TreeResponse: Decodable {
        struct Entry: Decodable {
            let path: String
            let type: String
        }
        let tree: [Entry]
    }

    /// Every file path in the branch, from a single recursive tree request.
    static func filePaths(in repo: RepoConfig) async throws -> [String] {
        var request = URLRequest(url: LibraryParser.treeURL(for: repo))
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as? HTTPURLResponse
        switch http?.statusCode ?? 0 {
        case 200:
            break
        case 404, 409, 422:
            throw GitHubError.notFound
        case 403, 429:
            if http?.value(forHTTPHeaderField: "x-ratelimit-remaining") == "0" {
                let reset = http?.value(forHTTPHeaderField: "x-ratelimit-reset")
                    .flatMap(TimeInterval.init).map(Date.init(timeIntervalSince1970:))
                throw GitHubError.rateLimited(reset: reset)
            }
            throw GitHubError.http(http?.statusCode ?? 0)
        case let code:
            throw GitHubError.http(code)
        }

        return try JSONDecoder().decode(TreeResponse.self, from: data)
            .tree.filter { $0.type == "blob" }.map(\.path)
    }
}

/// Keeps the SwiftData library in step with the repo. SwiftData doubles as the cache,
/// so the API is only hit on launch, on pull-to-refresh, or when the repo changes.
@MainActor
@Observable
final class LibraryStore {
    private(set) var isSyncing = false
    private(set) var lastError: String?
    private(set) var lastSynced: Date?

    func sync(config: RepoConfig, context: ModelContext, protecting activeSourceID: String? = nil) async {
        guard config.isValid, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        do {
            let paths = try await GitHubAPI.filePaths(in: config)
            try apply(LibraryParser.books(from: paths), config: config, context: context,
                      protecting: activeSourceID)
            lastError = nil
            lastSynced = .now
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func apply(_ sources: [BookSource], config: RepoConfig, context: ModelContext,
                       protecting activeSourceID: String?) throws {
        let key = config.key
        let existing = try context.fetch(FetchDescriptor<Book>(predicate: #Predicate<Book> { $0.repoKey == key }))
        var remaining = Dictionary(existing.map { ($0.sourceID, $0) }, uniquingKeysWith: { first, _ in first })
        // New books go on the end of the user's arrangement.
        var nextOrder = (existing.map(\.shelfOrder).max() ?? -1) + 1

        for source in sources {
            let sourceID = "\(key):\(source.id)"
            let urls = source.trackPaths.map { LibraryParser.mediaURL(for: $0, in: config).absoluteString }
            let names = source.trackPaths.enumerated().map { LibraryParser.trackName(for: $1, index: $0) }

            if let book = remaining.removeValue(forKey: sourceID) {
                // Keep the user's title/author/cover edits; only refresh the file list.
                if book.trackURLs != urls {
                    book.trackURLs = urls
                    book.trackNames = names
                    if book.trackIndex >= urls.count {
                        book.trackIndex = 0
                        book.position = 0
                    }
                }
            } else {
                let book = Book(sourceID: sourceID, repoKey: key, title: source.title,
                                author: source.author, trackURLs: urls, trackNames: names)
                book.shelfOrder = nextOrder
                nextOrder += 1
                context.insert(book)
            }
        }

        for (sourceID, book) in remaining where sourceID != activeSourceID {
            context.delete(book)
        }
        try context.save()
    }
}
