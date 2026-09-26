# Listen

A native SwiftUI audiobook player for iPhone that streams `.m4b` and `.mp3` files from a public GitHub repo (Git LFS), shows them on a wooden bookshelf, and remembers your place on the device.

The app is built on GitHub Actions, so you never need Xcode.

## Your audiobook repo

- Each `.m4b` is one book. Chapter markers inside it are read automatically.
- Each **folder** of `.mp3`/`.m4a` files is one book. Files play in natural order (`2` before `10`), and each file counts as a chapter.
- A file or folder named `Author - Title` is split into author and title. You can edit both in the app.
- Files must be stored with **Git LFS** (`git lfs track "*.m4b" "*.mp3"`). The app streams from `media.githubusercontent.com`, which uses your LFS bandwidth quota.

```
audiobooks/
├── Frank Herbert - Dune.m4b
└── Andy Weir - Project Hail Mary/
    ├── 01 - Chapter 1.mp3
    ├── 02 - Chapter 2.mp3
    └── ...
```

## Build

1. Push this folder to its own GitHub repo. Keeping the repo **public** makes Actions minutes free; macOS minutes on private repos use your quota at 10×.
2. The **Build IPA** workflow runs on every push to `main`. You can also start it by hand from the Actions tab.
3. Download the `Listen-ipa` artifact from the finished run, or run:
   ```sh
   gh run download --name Listen-ipa
   ```

The workflow generates the Xcode project with [XcodeGen](https://github.com/yonaskolb/XcodeGen) from `project.yml`, runs the unit tests on a simulator, and builds an unsigned `Listen.ipa`.

## Install on your iPhone (free Apple ID)

1. Install [Sideloadly](https://sideloadly.io) or [AltStore](https://altstore.io) on your Mac.
2. Connect your iPhone, drag in `Listen.ipa`, and sign in with your Apple ID.
3. On the iPhone:
   - Go to **Settings → General → VPN & Device Management** and trust your Apple ID.
   - Turn on **Settings → Privacy & Security → Developer Mode**.
4. Free Apple ID apps expire after **7 days**. Reinstall to renew, or let AltStore refresh it automatically over Wi‑Fi. Your progress survives a reinstall of the same build.

Requires iOS 18 or later.

## Using the app

- **First launch:** paste your repo link, e.g. `github.com/you/audiobooks`.
- **Tap a book** to start or resume it. You rewind 3 seconds so you hear the last few words again.
- **Long-press a book** to edit its title, author or **cover image URL**, or to mark it finished or not started.
- **Pull down on the shelf** to pick up new books from the repo.
- **In the player:**
  - chapter-aware scrubber
  - skip back and forward (intervals set in Settings)
  - speed from 0.75× to 3×
  - sleep timer, which fades out, or stops at the end of the chapter
  - AirPlay
  - chapter list
- **Lock screen and Control Centre** controls work. Progress is saved every 5 seconds, when you pause, and when you leave the app.

## Project layout

```
project.yml                   XcodeGen spec
.github/workflows/build.yml   CI → Listen.ipa
Listen/App                    App entry + root view
Listen/Models                 SwiftData Book (metadata + progress)
Listen/Services               GitHub sync, streaming player, Now Playing, image cache
Listen/Views                  Shelf, Player, Edit, Settings, Onboarding
ListenTests                   Parser / progress unit tests
scripts/make-icon.swift       Regenerates the app icon: swift scripts/make-icon.swift <png>
```
