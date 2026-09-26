import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(LibraryStore.self) private var library
    @Environment(AudioPlayer.self) private var player

    @AppStorage(SettingsKey.owner) private var owner = ""
    @AppStorage(SettingsKey.repo) private var repo = ""
    @AppStorage(SettingsKey.branch) private var branch = "main"
    @AppStorage(SettingsKey.skipBack) private var skipBack = 15
    @AppStorage(SettingsKey.skipForward) private var skipForward = 30

    @State private var draftOwner = ""
    @State private var draftRepo = ""
    @State private var draftBranch = ""

    private let intervals = [10, 15, 30, 45, 60]

    private var draft: RepoConfig {
        RepoConfig(owner: draftOwner.trimmingCharacters(in: .whitespaces),
                   repo: draftRepo.trimmingCharacters(in: .whitespaces),
                   branch: draftBranch.trimmingCharacters(in: .whitespaces))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Owner", text: $draftOwner)
                    TextField("Repository", text: $draftRepo)
                    TextField("Branch", text: $draftBranch)
                    PasteButton(payloadType: String.self) { strings in
                        guard let text = strings.first else { return }
                        Task { @MainActor in
                            if let parsed = RepoConfig.parse(text, defaultBranch: draftBranch) {
                                draftOwner = parsed.owner
                                draftRepo = parsed.repo
                                draftBranch = parsed.branch
                            }
                        }
                    }
                    .buttonBorderShape(.capsule)
                    .labelStyle(.titleAndIcon)
                } header: {
                    Text("GitHub Repository")
                } footer: {
                    Text("Public repo with .m4b files or folders of .mp3s stored in Git LFS. Paste a GitHub link to fill these in.")
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

                Section("Playback") {
                    Picker("Skip Back", selection: $skipBack) {
                        ForEach(intervals, id: \.self) { Text("\($0) seconds").tag($0) }
                    }
                    Picker("Skip Forward", selection: $skipForward) {
                        ForEach(intervals, id: \.self) { Text("\($0) seconds").tag($0) }
                    }
                }

                Section {
                    Button {
                        Task {
                            await library.sync(config: RepoConfig(owner: owner, repo: repo, branch: branch),
                                               context: context, protecting: player.book?.sourceID)
                        }
                    } label: {
                        HStack {
                            Text("Refresh Library")
                            Spacer()
                            if library.isSyncing { ProgressView() }
                        }
                    }
                    .disabled(library.isSyncing)
                    if let synced = library.lastSynced {
                        LabeledContent("Last Refreshed") {
                            Text(synced, format: .relative(presentation: .named))
                        }
                    }
                    if let error = library.lastError {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                } header: {
                    Text("Library")
                } footer: {
                    Text("Streaming uses your GitHub LFS bandwidth quota. You can check it under GitHub → Settings → Billing.")
                }

                Section {
                    Button("Disconnect Repository", role: .destructive) {
                        player.stop()
                        owner = ""
                        repo = ""
                        dismiss()
                    }
                } footer: {
                    Text("Listen \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 12)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: save)
                        .fontWeight(.semibold)
                        .disabled(!draft.isValid)
                }
            }
            .onAppear {
                draftOwner = owner
                draftRepo = repo
                draftBranch = branch
            }
            .onChange(of: skipBack) { player.updateSkipIntervals() }
            .onChange(of: skipForward) { player.updateSkipIntervals() }
        }
    }

    private func save() {
        owner = draft.owner
        repo = draft.repo
        branch = draft.branch
        dismiss()
    }
}
