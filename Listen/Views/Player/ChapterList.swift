import SwiftUI

struct ChapterList: View {
    @Environment(AudioPlayer.self) private var player
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    ForEach(player.chapters) { chapter in
                        row(chapter)
                            .id(chapter.id)
                            .listRowBackground(chapter.id == player.currentChapterIndex
                                               ? Color.white.opacity(0.08) : Color.clear)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .onAppear {
                    if let current = player.currentChapterIndex {
                        proxy.scrollTo(current, anchor: .center)
                    }
                }
            }
            .overlay {
                if player.chapters.isEmpty {
                    ContentUnavailableView("No Chapters", systemImage: "list.bullet",
                                           description: Text("This book doesn't include chapter markers."))
                }
            }
            .navigationTitle("Chapters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func row(_ chapter: Chapter) -> some View {
        let isCurrent = chapter.id == player.currentChapterIndex
        return Button {
            player.jump(toChapter: chapter.id)
            dismiss()
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    if isCurrent {
                        Image(systemName: "waveform")
                            .symbolEffect(.variableColor.iterative, isActive: player.isPlaying)
                            .foregroundStyle(Theme.accent)
                    } else {
                        Text("\(chapter.id + 1)")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 30)

                Text(chapter.title)
                    .font(.body.weight(isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? Theme.accent : .primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 8)

                if chapter.end > chapter.start {
                    Text(TimeFormat.clock(chapter.end - chapter.start))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
