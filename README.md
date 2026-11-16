# Dustpan

A free, open-source Mac app that finds the storage your tools left behind and lets you take it back safely.

> Status: early. It runs from source; there is no signed app download yet.

<img width="1119" height="652" alt="Screenshot 2026-11-17 at 12 13 19 AM" src="https://github.com/user-attachments/assets/fe217f78-cc07-4a63-b390-9c685d2406f0" />
<img width="1119" height="652" alt="Screenshot 2026-11-17 at 12 13 29 AM" src="https://github.com/user-attachments/assets/43941c94-5bb1-4820-813f-131cda262417" />


## What it does

- **Developer caches.** Xcode DerivedData, device support, simulator caches, archives, and the caches of SwiftPM, CocoaPods, npm, Yarn, pnpm, Gradle, Homebrew, pub, Cargo and Go.
- **Stale project builds.** Finds `node_modules`, Unity `Library`, `Pods`, Flutter `build`, `.build`, `target` and similar folders inside projects you haven't touched in 30, 90, 180 or 365 days.
- **Unused apps.** Lists apps you haven't opened in a set number of days, with the size of each app and its data. Uninstall the app with its data, or clear only its caches.
- **SDKs and toolchains.** Lists every installed version of Node (nvm, fnm, Volta), Python (pyenv), Ruby (rbenv, RVM), Rust, Flutter (FVM), Go, Java, the Android SDK, Unity editors and Xcode, marks the default and newest, and lets you remove the others. Also lists every Homebrew formula and cask with its version, and finds old formula versions Homebrew left behind.
- **Files and media.** Installers, old screen recordings, large videos and images, old screenshots, duplicate images, unpacked archives and device backups in Downloads, Desktop, Documents, Movies and Pictures.
- **Menu bar.** Free space and a one-click clean of the Safe items.
- **History and undo.** Every clean is logged and can be put back until you empty the Trash.
- **Dry run.** Export the exact list of paths a clean would move, without moving anything.

## How it stays safe

- Nothing is deleted. Items are moved to the Trash.
- Items are tagged **Safe** (rebuilt automatically) or **Review** (might hold something you want). Only Safe items are selected for you.
- A build folder only counts when its project file sits next to it, for example `package.json` beside `node_modules`.
- Projects with uncommitted changes, no Git history, or another version control system are never pre-selected.
- Your own apps and files are never selected for you, and your Photos library is never opened.
- Every path passes one final check (`PathGuard`) before it moves: inside your home folder (or an app directly in `/Applications`), never a top-level folder, never a whole `~/Library` folder.
- No network access, no telemetry.

## Run it

Requires macOS 14 and Xcode 15 or later.

```sh
swift run Dustpan
```

Or open `Package.swift` in Xcode and run the `Dustpan` scheme.

```sh
swift test
```

## Add a rule

Rules are plain JSON in `Sources/DustpanCore/Rules`. Each file is an array:

```json
{
  "id": "npm-cache",
  "name": "npm cache",
  "category": "packages",
  "safety": "safe",
  "summary": "Downloaded npm packages.",
  "afterEffect": "Packages download again on the next install. Needs a connection.",
  "paths": ["~/.npm/_cacache"],
  "mode": "self"
}
```

- `category`: `xcode`, `packages` or `system`
- `safety`: `safe` only if the tool recreates it by itself; otherwise `review`
- `mode`: `self` treats the path as one item; `children` lists each entry inside it
- `minAgeDays` (optional): only include items not modified for that long

You can try a rule without rebuilding by putting a JSON file in `~/Library/Application Support/Dustpan/Rules`. A rule with the same `id` replaces the built-in one.

## Layout

- `Sources/DustpanCore`: scanning, rules, the Trash and history. No UI.
- `Sources/DustpanApp`: the SwiftUI app.
- `Tests/DustpanCoreTests`: tests for the safety check and both scanners.

## Licence

MIT
