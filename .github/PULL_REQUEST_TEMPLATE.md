<!--
Branch prefix conventions (see CONTRIBUTING.md):
  feat/ fix/ perf/ refactor/ docs/ chore/

Keep PRs focused: one logical unit of work each.
-->

## Summary

<!-- 1–3 bullets describing what changes and why. Link the issue if there is one. -->

-
-

## Motivation

<!-- Optional: explain the why if not obvious from the summary. Reviewers care about why more than what. -->

## Test plan

<!-- Bulleted checklist of how to validate. Reviewers will reproduce this. -->

- [ ] `make build-arm` succeeds
- [ ] `cd EngineKit && swift test` passes
- [ ]
- [ ]

## Screenshots / recordings

<!-- For UI changes. Drag and drop into this textarea. -->

## Checklist

- [ ] Branch follows naming conventions (`feat/`, `fix/`, etc.)
- [ ] Commit messages explain the *why*
- [ ] No new warnings introduced
- [ ] Files stay under ~400–500 LOC (split with extensions if needed)
- [ ] Engine code in `EngineKit/` has no SwiftUI / AppKit imports
- [ ] If user-visible: `docs/CHANGELOG.md` updated under the next unreleased version
