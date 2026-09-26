import SwiftUI

struct BookEditView: View {
    let book: Book

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AudioPlayer.self) private var player
    @State private var title: String
    @State private var author: String
    @State private var coverURL: String

    init(book: Book) {
        self.book = book
        _title = State(initialValue: book.title)
        _author = State(initialValue: book.author)
        _coverURL = State(initialValue: book.coverURL)
    }

    private var trimmedCover: String { coverURL.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    BookView(title: title.isEmpty ? book.title : title, author: author, coverURL: trimmedCover,
                             showsBadges: false, debounce: .milliseconds(400))
                        .frame(width: 150)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .listRowBackground(Color.clear)
                }

                Section("Details") {
                    TextField("Title", text: $title)
                    TextField("Author", text: $author)
                        .textContentType(.name)
                }

                Section {
                    TextField("https://example.com/cover.jpg", text: $coverURL, axis: .vertical)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .lineLimit(1...3)
                    HStack {
                        PasteButton(payloadType: String.self) { strings in
                            guard let text = strings.first else { return }
                            Task { @MainActor in coverURL = text.trimmingCharacters(in: .whitespacesAndNewlines) }
                        }
                        .buttonBorderShape(.capsule)
                        .labelStyle(.titleAndIcon)
                        Spacer()
                        if !coverURL.isEmpty {
                            Button("Clear", role: .destructive) { coverURL = "" }
                                .buttonStyle(.borderless)
                        }
                    }
                } header: {
                    Text("Cover Image")
                } footer: {
                    Text("A direct link to a .jpg or .png. Square audiobook art and tall book covers both look right on the shelf.")
                }

                Section("Progress") {
                    LabeledContent("Status", value: book.isFinished ? "Finished"
                                   : book.hasStarted ? book.progressCaption : "Not started")
                    if !book.isFinished {
                        Button("Mark as Finished") {
                            player.markFinished(book)
                            dismiss()
                        }
                    }
                    if book.hasStarted || book.isFinished {
                        Button("Reset Progress", role: .destructive) {
                            player.resetProgress(book)
                            dismiss()
                        }
                    }
                }

                Section("Source") {
                    LabeledContent("Files", value: "\(book.trackURLs.count)")
                    Text(book.sourceID.split(separator: ":", maxSplits: 1).last.map(String.init) ?? book.sourceID)
                        .font(.footnote.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .navigationTitle("Edit Book")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).fontWeight(.semibold)
                }
            }
        }
    }

    private func save() {
        let newTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let coverChanged = trimmedCover != book.coverURL
        book.title = newTitle.isEmpty ? book.title : newTitle
        book.author = author.trimmingCharacters(in: .whitespacesAndNewlines)
        book.coverURL = trimmedCover
        try? context.save()
        if player.book?.sourceID == book.sourceID {
            player.refreshArtwork()
            if !coverChanged { player.updateNowPlaying() }
        }
        dismiss()
    }
}
