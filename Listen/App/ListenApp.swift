import SwiftData
import SwiftUI

@main
struct ListenApp: App {
    private let container: ModelContainer
    @State private var player = AudioPlayer()
    @State private var library = LibraryStore()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        UserDefaults.standard.register(defaults: [
            SettingsKey.branch: "main",
            SettingsKey.skipBack: 15,
            SettingsKey.skipForward: 30,
            SettingsKey.rate: 1.0,
        ])
        do {
            container = try ModelContainer(for: Book.self)
        } catch {
            fatalError("Couldn't open the library database: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(player)
                .environment(library)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .onAppear { player.modelContext = container.mainContext }
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { player.saveProgress() }
        }
    }
}

struct RootView: View {
    @Environment(AudioPlayer.self) private var player
    @Environment(LibraryStore.self) private var library
    @Environment(\.modelContext) private var context

    @AppStorage(SettingsKey.owner) private var owner = ""
    @AppStorage(SettingsKey.repo) private var repo = ""
    @AppStorage(SettingsKey.branch) private var branch = "main"

    @Namespace private var zoom
    @State private var showPlayer = false
    @State private var zoomSource = "mini"
    @State private var showSettings = false

    private var config: RepoConfig { RepoConfig(owner: owner, repo: repo, branch: branch) }

    var body: some View {
        Group {
            if config.isValid {
                ShelfView(config: config, namespace: zoom, openPlayer: openPlayer, showSettings: $showSettings)
                    .safeAreaInset(edge: .bottom) {
                        if player.book != nil {
                            MiniPlayer(namespace: zoom) { openPlayer("mini") }
                                .padding(.horizontal, 12)
                                .padding(.bottom, 4)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .transition(.opacity)
            } else {
                OnboardingView().transition(.opacity)
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: player.book?.sourceID)
        .animation(.easeInOut(duration: 0.4), value: config.isValid)
        .fullScreenCover(isPresented: $showPlayer) {
            PlayerView()
                .navigationTransition(.zoom(sourceID: zoomSource, in: zoom))
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .task(id: config.key) {
            guard config.isValid else { return }
            await library.sync(config: config, context: context, protecting: player.book?.sourceID)
        }
    }

    private func openPlayer(_ source: String) {
        zoomSource = source
        showPlayer = true
    }
}
