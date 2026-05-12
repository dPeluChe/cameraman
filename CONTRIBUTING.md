# Contributing to Cameraman

Thanks for your interest in contributing! Cameraman is a macOS local-first screen recorder and video editor, written in Swift. This document describes how to get the project building, the patterns we follow, and how to submit changes.

## Quick start

```bash
# Clone
git clone https://github.com/dPeluChe/labs-cameraman.git
cd labs-cameraman

# Open in Xcode and run the CameramanApp scheme
open CameramanApp/CameramanApp.xcodeproj

# Or build EngineKit (the engine package) from the CLI
cd EngineKit && swift build && swift test
```

Requirements:

- macOS 13 (Ventura) or later — macOS 14+ for development is recommended
- Xcode 15+
- Swift 5.9+

## Project layout

```
labs-cameraman/
├── App/                       # SwiftUI app sources (CameramanApp scheme)
├── CameramanApp/              # Xcode project, entitlements, assets
├── EngineKit/                 # Pure Swift package — capture, edit, export, transcribe
├── docs/                      # CHANGELOG, PRD, TECH_SPEC, DEV_ONBOARDING, TASK_*
├── scripts/build-dmg.sh       # Packaging script
├── Makefile                   # build / verify / dmg / release targets
├── README.md                  # Quick overview
├── CLAUDE.md                  # Guidance for AI assistants working on the repo
└── LICENSE                    # MIT
```

See [`docs/DEV_ONBOARDING.md`](docs/DEV_ONBOARDING.md) for architecture and key patterns. See [`docs/TASK_TODO.md`](docs/TASK_TODO.md) for the current backlog.

## Building and testing

| Command | What it does |
|---------|-------------|
| `make build` | Universal Release build (arm64 + x86_64) |
| `make build-arm` | Native arm64-only Release build (faster, dev only) |
| `make verify` | Confirm the binary is universal |
| `make dmg` | Repackage the existing build into a `.dmg` |
| `make release` | Full beta pipeline: build + verify + dmg |
| `make clean` | Remove `dist/` and `CameramanApp/build/` |
| `make help` | List all targets |

EngineKit tests run separately:

```bash
cd EngineKit
swift test                         # all tests
swift test --filter ZoomPlanGenerator   # one suite
swift test --parallel              # parallel
```

## Code conventions

- **Engine code is UI-free.** `EngineKit` must not depend on SwiftUI or AppKit. The UI layer in `App/` is replaceable.
- **Use `async/await` for I/O.** Avoid GCD and completion handlers for new code.
- **Actors for shared mutable state.** See `CaptureEngine`, `CameraEngine`, `PreviewEngine`, `ThumbnailCache` for the pattern.
- **Non-destructive editing.** All edits live in `project.json` metadata; source media files are never modified.
- **Errors carry context.** Use `EngineKitError` with file paths, timestamps, or drift amounts as relevant — distinguish recoverable from fatal.
- **Files cap at ~400–500 LOC.** Split with extensions (`File+Feature.swift`) when growing.
- **Don't write multi-line comments to explain what code does.** Comments document the *why* — invariants, non-obvious constraints, or workarounds.

Naming and style follow the standard Swift API design guidelines. We don't use SwiftLint at the moment but we keep the codebase warning-clean.

## Submitting changes

1. Fork the repo and create a branch from `main`. Use a prefix:
   - `feat/` for new features
   - `fix/` for bug fixes
   - `perf/` for performance work
   - `refactor/` for non-behavioral changes
   - `docs/` for documentation
   - `chore/` for tooling / packaging

2. Make your change. Keep PRs focused: one logical unit of work each.

3. Write a clear commit message. We use [Conventional Commits](https://www.conventionalcommits.org/) loosely:

   ```
   feat(editor): horizontal ProjectAssetsBar, fixed-width inspector

   Body explains why. Mention what was tried, what didn't work, and any
   trade-offs the reviewer should know about.
   ```

4. Run `make build-arm` and `swift test` (from `EngineKit/`). PRs that fail CI will not be merged.

5. Open the PR against `main`. Fill in the PR template — the test plan section is the most important part. Reviewers will reproduce it.

6. Address review feedback by pushing new commits to the same branch. Don't force-push unless asked — it makes review threads hard to follow.

## Reporting bugs

Open an issue using the **Bug report** template. The more concrete the reproduction the faster we can land a fix:

- macOS version (`sw_vers -productVersion`)
- Cameraman version (Cameraman → About)
- Steps that trigger the bug
- A snippet of `~/Library/Logs/Cameraman/` or the Console.app output if relevant

For security-sensitive issues (privilege escalation, sandbox escape, credentials exposure) please email `antonio@iteris.tech` instead of filing a public issue.

## Suggesting features

Open an issue using the **Feature request** template. Describe the problem first, then your idea. If it might significantly change the UI or architecture, link to a sketch or write a short design note.

The backlog lives in [`docs/TASK_TODO.md`](docs/TASK_TODO.md). Picking something from there is a great place to start.

## Code of Conduct

This project follows the [Contributor Covenant 2.1](CODE_OF_CONDUCT.md). Be respectful; abusive or harassing behavior gets you removed.

## License

By contributing, you agree that your contributions will be licensed under the MIT License (see [`LICENSE`](LICENSE)).
