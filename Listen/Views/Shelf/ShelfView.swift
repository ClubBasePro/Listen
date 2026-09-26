import SwiftData
import SwiftUI

enum ShelfFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case listening = "Listening"
    case unread = "Not Started"
    case finished = "Finished"

    var id: Self { self }

    func includes(_ book: Book) -> Bool {
        switch self {
        case .all: true
        case .listening: book.hasStarted
        case .unread: book.lastPlayed == nil && !book.isFinished
        case .finished: book.isFinished
        }
    }
}

enum ShelfSort: String, CaseIterable, Identifiable {
    case custom = "My Order"
    case title = "Title"
    case author = "Author"
    case recent = "Recently Played"
    case added = "Recently Added"

    var id: Self { self }

    var icon: String {
        switch self {
        case .custom: "hand.draw"
        case .title: "textformat"
        case .author: "person"
        case .recent: "clock"
        case .added: "sparkles"
        }
    }

    func sorted(_ books: [Book]) -> [Book] {
        let byTitle: (Book, Book) -> Bool = { LibraryParser.naturalOrder($0.title, $1.title) }
        switch self {
        case .custom:
            return books.sorted { $0.shelfOrder != $1.shelfOrder ? $0.shelfOrder < $1.shelfOrder : byTitle($0, $1) }
        case .title:
            return books.sorted(by: byTitle)
        case .author:
            return books.sorted {
                if $0.author.isEmpty != $1.author.isEmpty { return !$0.author.isEmpty }
                if $0.author != $1.author { return LibraryParser.naturalOrder($0.author, $1.author) }
                return byTitle($0, $1)
            }
        case .recent:
            return books.sorted {
                let a = $0.lastPlayed ?? .distantPast, b = $1.lastPlayed ?? .distantPast
                return a != b ? a > b : byTitle($0, $1)
            }
        case .added:
            return books.sorted { $0.addedAt != $1.addedAt ? $0.addedAt > $1.addedAt : byTitle($0, $1) }
        }
    }
}

struct ShelfView: View {
    let config: RepoConfig
    let namespace: Namespace.ID
    let openPlayer: (_ zoomSource: String) -> Void
    @Binding var showSettings: Bool

    @Environment(AudioPlayer.self) private var player
    @Environment(LibraryStore.self) private var library
    @Environment(\.modelContext) private var context
    @Query(sort: \Book.title) private var allBooks: [Book]
    @State private var filter: ShelfFilter = .all
    @State private var editingBook: Book?
    @State private var tapCount = 0
    @AppStorage("shelfSort") private var sortRaw = ShelfSort.custom.rawValue
    @State private var isArranging = false
    @State private var dropTargetID: String?
    @State private var reorderCount = 0

    private let perShelf = 3

    private var sort: ShelfSort { ShelfSort(rawValue: sortRaw) ?? .custom }
    private var books: [Book] { sort.sorted(allBooks.filter { $0.repoKey == config.key }) }
    private var visibleBooks: [Book] { books.filter(filter.includes) }

    private var continueBook: Book? {
        if let current = player.book, current.repoKey == config.key, !current.isFinished { return current }
        return books.filter(\.hasStarted).max { ($0.lastPlayed ?? .distantPast) < ($1.lastPlayed ?? .distantPast) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                if let error = library.lastError {
                    errorCard(error).padding(.horizontal, 16).padding(.top, 16)
                }

                if isArranging {
                    arrangeHint.padding(.horizontal, 16).padding(.top, 20)
                } else if let book = continueBook {
                    ContinueCard(book: book, namespace: namespace) { start(book, zoomSource: "hero") }
                        .padding(.horizontal, 16)
                        .padding(.top, 20)
                }

                if !books.isEmpty {
                    filterBar.padding(.top, 24)
                }

                shelves.padding(.top, 28)
            }
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(WallBackground().ignoresSafeArea())
        .refreshable {
            await library.sync(config: config, context: context, protecting: player.book?.sourceID)
        }
        .sensoryFeedback(.impact(flexibility: .soft), trigger: tapCount)
        .sensoryFeedback(.impact(weight: .medium), trigger: reorderCount)
        .sensoryFeedback(.selection, trigger: dropTargetID)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isArranging)
        .sheet(item: $editingBook) { BookEditView(book: $0) }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Library")
                    .font(.system(size: 38, weight: .bold, design: .serif))
                    .foregroundStyle(Color(hex: 0xF3E6D0))
                Text("\(config.owner)/\(config.repo) · \(books.count) \(books.count == 1 ? "book" : "books")")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }
            Spacer()
            if library.isSyncing {
                ProgressView().tint(.white.opacity(0.7)).padding(.trailing, 6)
            }
            if isArranging {
                Button { isArranging = false } label: {
                    Text("Done")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 18)
                        .frame(height: 40)
                        .background(Capsule().fill(Theme.accent))
                }
                .buttonStyle(PressableStyle())
                .transition(.scale.combined(with: .opacity))
            } else {
                sortMenu.transition(.scale.combined(with: .opacity))
            }
            Button { showSettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Settings")
        }
    }

    private var sortMenu: some View {
        Menu {
            Section("Sort By") {
                ForEach(ShelfSort.allCases) { option in
                    Button {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { sortRaw = option.rawValue }
                    } label: {
                        if option == sort {
                            Label(option.rawValue, systemImage: "checkmark")
                        } else {
                            Label(option.rawValue, systemImage: option.icon)
                        }
                    }
                }
            }
            Section {
                Button("Arrange Shelf", systemImage: "square.grid.3x3.middle.filled") { isArranging = true }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 40, height: 40)
                .background(.ultraThinMaterial, in: Circle())
        }
        .accessibilityLabel("Sort and arrange")
    }

    private var arrangeHint: some View {
        HStack(spacing: 12) {
            Image(systemName: "hand.draw.fill")
                .font(.title2)
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Arrange your shelf").font(.headline).foregroundStyle(.white)
                Text("Press and hold a book, then drag it onto another book or an empty space.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.65))
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func errorCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.accent)
            Text(message).font(.footnote).foregroundStyle(.white.opacity(0.85))
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var filterBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(ShelfFilter.allCases) { option in
                    Button {
                        withAnimation(.snappy) { filter = option }
                    } label: {
                        Text(option.rawValue)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .foregroundStyle(filter == option ? Color.black : .white.opacity(0.8))
                            .background(Capsule().fill(filter == option ? Theme.accent : .white.opacity(0.08)))
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            .padding(.horizontal, 16)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: Shelves

    @ViewBuilder
    private var shelves: some View {
        if books.isEmpty, library.isSyncing {
            VStack(spacing: 34) {
                ForEach(0..<3, id: \.self) { _ in
                    shelfRow(slots: Array(repeating: nil, count: perShelf), placeholder: true)
                }
            }
        } else {
            let rows = visibleBooks.chunked(into: perShelf)
            let emptyRows = max(0, 3 - rows.count)
            VStack(spacing: 34) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    shelfRow(slots: row.map(Optional.some) + Array(repeating: nil, count: perShelf - row.count))
                }
                ForEach(0..<emptyRows, id: \.self) { index in
                    shelfRow(slots: Array(repeating: nil, count: perShelf))
                        .overlay {
                            if index == 0, rows.isEmpty { emptyMessage }
                        }
                }
            }
        }
    }

    private func shelfRow(slots: [Book?], placeholder: Bool = false) -> some View {
        VStack(spacing: -7) {
            HStack(alignment: .bottom, spacing: 20) {
                ForEach(Array(slots.enumerated()), id: \.offset) { _, book in
                    if let book {
                        bookButton(book)
                    } else if placeholder {
                        Theme.bookShape.fill(.white.opacity(0.06))
                            .aspectRatio(Theme.bookAspect, contentMode: .fit)
                            .frame(maxWidth: .infinity)
                            .phaseAnimator([0.4, 1]) { view, phase in view.opacity(phase) } animation: { _ in
                                .easeInOut(duration: 0.9)
                            }
                    } else {
                        Color.clear
                            .aspectRatio(Theme.bookAspect, contentMode: .fit)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(.horizontal, 30)
            .zIndex(1)

            ShelfPlank().padding(.horizontal, 12)
        }
        // Dropping on a shelf's empty space puts the book at the end of that shelf.
        .dropDestination(for: String.self) { ids, _ in
            guard let id = ids.first else { return false }
            if let last = slots.compactMap({ $0 }).last {
                move(id, onto: last, placeAfter: true)
            } else {
                move(id, onto: nil)
            }
            return true
        }
    }

    @ViewBuilder
    private func bookButton(_ book: Book) -> some View {
        if isArranging {
            arrangeableBook(book)
        } else {
            playableBook(book)
        }
    }

    private func arrangeableBook(_ book: Book) -> some View {
        let isTarget = dropTargetID == book.sourceID
        return BookView(book: book)
            .modifier(Jiggle(seed: book.sourceID))
            .scaleEffect(isTarget ? 0.9 : 1)
            .opacity(isTarget ? 0.55 : 1)
            .overlay {
                if isTarget {
                    Theme.bookShape
                        .stroke(Theme.accent, lineWidth: 3)
                        .shadow(color: Theme.accent.opacity(0.8), radius: 8)
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isTarget)
            .frame(maxWidth: .infinity)
            .draggable(book.sourceID) {
                BookView(book: book, showsBadges: false)
                    .frame(width: 96)
            }
            .dropDestination(for: String.self) { ids, _ in
                guard let id = ids.first, id != book.sourceID else { return false }
                move(id, onto: book)
                return true
            } isTargeted: { targeted in
                if targeted {
                    dropTargetID = book.sourceID
                } else if dropTargetID == book.sourceID {
                    dropTargetID = nil
                }
            }
            .accessibilityHint("Drag to move this book")
    }

    private func playableBook(_ book: Book) -> some View {
        Button { start(book, zoomSource: book.sourceID) } label: {
            BookView(book: book)
                .matchedTransitionSource(id: book.sourceID, in: namespace)
        }
        .buttonStyle(BookPressStyle())
        .frame(maxWidth: .infinity)
        .contextMenu {
            Button("Play", systemImage: "play.fill") { start(book, zoomSource: book.sourceID) }
            Button("Edit Details", systemImage: "pencil") { editingBook = book }
            Button("Arrange Shelf", systemImage: "square.grid.3x3.middle.filled") { isArranging = true }
            Divider()
            if book.isFinished || book.hasStarted {
                Button("Mark as Not Started", systemImage: "arrow.counterclockwise") { player.resetProgress(book) }
            }
            if !book.isFinished {
                Button("Mark as Finished", systemImage: "checkmark.circle") { player.markFinished(book) }
            }
        } preview: {
            VStack(alignment: .leading, spacing: 10) {
                BookView(book: book, showsBadges: false).frame(width: 200)
                VStack(alignment: .leading, spacing: 2) {
                    Text(book.title).font(.headline)
                    if !book.author.isEmpty { Text(book.author).font(.subheadline).foregroundStyle(.secondary) }
                    Text(book.hasStarted || book.isFinished ? book.progressCaption : "Not started")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
    }

    private var emptyMessage: some View {
        VStack(spacing: 6) {
            Image(systemName: filter == .all ? "books.vertical" : "line.3.horizontal.decrease.circle")
                .font(.title)
            Text(filter == .all ? "No audiobooks found" : "Nothing here yet")
                .font(.headline)
            Text(filter == .all
                 ? "Add .m4b files or folders of .mp3s to \(config.repo), then pull down to refresh."
                 : "Books you \(filter == .finished ? "finish" : "start") will appear here.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.6))
        }
        .foregroundStyle(.white.opacity(0.85))
        .padding(.horizontal, 40)
        .offset(y: -10)
    }

    /// Moves a book to where it was dropped and saves the result as "My Order".
    /// Dropping on a later book takes its place (the target shifts back); dropping on an
    /// earlier book goes in front of it. With `target == nil` the book goes to the end.
    private func move(_ id: String, onto target: Book?, placeAfter: Bool? = nil) {
        var ordered = books
        guard let from = ordered.firstIndex(where: { $0.sourceID == id }) else { return }
        let targetIndex = target.flatMap { t in ordered.firstIndex { $0.sourceID == t.sourceID } }
        let after = placeAfter ?? (targetIndex.map { from < $0 } ?? true)

        let book = ordered.remove(at: from)
        var index = ordered.count
        if let target, let t = ordered.firstIndex(where: { $0.sourceID == target.sourceID }) {
            index = after ? t + 1 : t
        }
        ordered.insert(book, at: index)
        dropTargetID = nil
        guard index != from || sort != .custom else { return }

        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
            for (position, item) in ordered.enumerated() where item.shelfOrder != position {
                item.shelfOrder = position
            }
            sortRaw = ShelfSort.custom.rawValue
        }
        try? context.save()
        reorderCount += 1
    }

    private func start(_ book: Book, zoomSource: String) {
        tapCount += 1
        player.play(book)
        openPlayer(zoomSource)
    }
}

/// Large "pick up where you left off" card above the shelves.
struct ContinueCard: View {
    let book: Book
    let namespace: Namespace.ID
    let action: () -> Void

    @Environment(AudioPlayer.self) private var player

    private var isCurrent: Bool { player.book?.sourceID == book.sourceID }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                BookView(book: book, showsBadges: false)
                    .frame(width: 78)
                    .matchedTransitionSource(id: "hero", in: namespace)

                VStack(alignment: .leading, spacing: 5) {
                    Text(isCurrent && player.wantsToPlay ? "NOW PLAYING" : "CONTINUE LISTENING")
                        .font(.caption2.weight(.bold))
                        .tracking(1.4)
                        .foregroundStyle(Theme.accent)
                    Text(book.title)
                        .font(.system(.title3, design: .serif).weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    let subtitle = isCurrent ? player.chapterTitle : (book.chapterTitle.isEmpty ? book.author : book.chapterTitle)
                    if !subtitle.isEmpty, subtitle != book.title {
                        Text(subtitle).font(.footnote).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
                    }
                    ProgressBar(value: book.progress).frame(height: 4).padding(.top, 6)
                    Text(book.progressCaption).font(.caption2.weight(.medium)).foregroundStyle(.white.opacity(0.55))
                }
                Spacer(minLength: 0)

                ZStack {
                    Circle().fill(Theme.accent)
                    Image(systemName: isCurrent && player.wantsToPlay ? "waveform" : "play.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.black)
                        .symbolEffect(.variableColor.iterative, isActive: isCurrent && player.isPlaying)
                        .contentTransition(.symbolEffect(.replace))
                }
                .frame(width: 46, height: 46)
            }
            .padding(16)
            .background {
                ZStack {
                    CoverImage(url: book.coverURL, title: book.title, author: book.author)
                        .blur(radius: 40)
                        .scaleEffect(1.4)
                    Color.black.opacity(0.45)
                }
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(.white.opacity(0.1)))
            .shadow(color: .black.opacity(0.4), radius: 18, y: 10)
        }
        .buttonStyle(PressableStyle(scale: 0.97))
    }
}
