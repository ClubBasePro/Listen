import SwiftUI

/// First-run screen: connect a GitHub repo.
struct OnboardingView: View {
    @AppStorage(SettingsKey.owner) private var owner = ""
    @AppStorage(SettingsKey.repo) private var repo = ""
    @AppStorage(SettingsKey.branch) private var branch = "main"

    @State private var link = ""
    @State private var branchInput = "main"
    @State private var appeared = false
    @FocusState private var focused: Bool

    private var parsed: RepoConfig? { RepoConfig.parse(link, defaultBranch: branchInput) }

    var body: some View {
        ZStack {
            WallBackground().ignoresSafeArea()

            ScrollView {
                VStack(spacing: 30) {
                    decorativeShelf
                        .padding(.top, 50)

                    VStack(spacing: 10) {
                        Text("Listen")
                            .font(.system(size: 54, weight: .bold, design: .serif))
                            .foregroundStyle(Color(hex: 0xF3E6D0))
                        Text("Your audiobooks, streamed from GitHub\nand shelved beautifully.")
                            .font(.body)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white.opacity(0.65))
                    }

                    VStack(spacing: 12) {
                        field(icon: "link", placeholder: "github.com/you/audiobooks", text: $link)
                            .keyboardType(.URL)
                            .submitLabel(.go)
                            .onSubmit(connect)
                        field(icon: "arrow.triangle.branch", placeholder: "Branch", text: $branchInput)

                        Button(action: connect) {
                            Text("Open My Library")
                                .font(.headline)
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Capsule().fill(Theme.accent.opacity(parsed == nil ? 0.4 : 1)))
                        }
                        .buttonStyle(PressableStyle(scale: 0.97))
                        .disabled(parsed == nil)
                        .padding(.top, 6)
                    }
                    .padding(20)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .padding(.horizontal, 20)

                    Text("Works with public repos that store .m4b files, or folders of .mp3s, in Git LFS. Nothing is downloaded — books stream, and your place is saved on this iPhone.")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.45))
                        .padding(.horizontal, 36)
                }
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .onAppear { withAnimation(.spring(response: 0.8, dampingFraction: 0.7).delay(0.1)) { appeared = true } }
    }

    private func field(icon: String, placeholder: String, text: Binding<String>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(.white.opacity(0.5)).frame(width: 20)
            TextField(placeholder, text: text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.black.opacity(0.25)))
    }

    private var decorativeShelf: some View {
        let samples = [("The Long Way Home", "A. Reader"), ("Night Stories", ""), ("Chapter One", "")]
        return VStack(spacing: -7) {
            HStack(alignment: .bottom, spacing: 18) {
                ForEach(Array(samples.enumerated()), id: \.offset) { index, sample in
                    BookView(title: sample.0, author: sample.1, coverURL: "", showsBadges: false)
                        .frame(width: index == 1 ? 96 : 84)
                        .rotationEffect(.degrees(index == 2 && appeared ? 8 : 0), anchor: .bottomLeading)
                        .offset(y: appeared ? 0 : -30)
                        .opacity(appeared ? 1 : 0)
                        .animation(.spring(response: 0.7, dampingFraction: 0.6).delay(Double(index) * 0.08),
                                   value: appeared)
                }
            }
            .zIndex(1)
            ShelfPlank().frame(width: 330)
        }
    }

    private func connect() {
        guard let config = parsed else { return }
        owner = config.owner
        repo = config.repo
        branch = config.branch
    }
}
