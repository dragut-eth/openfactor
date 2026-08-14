# Handoff

Running state of the project. Updated in every pull request, before the commit. Read this
first when picking the work back up.

**Last updated:** 2026-08-14, end of PR 0.

## Where things stand

PR 0 is complete. The repository skeleton, documentation, and CI exist. There is no Swift
code yet.

| Phase | Status |
| --- | --- |
| PR 0, repository bootstrap | Done |
| PR 1, `OpenFactorCore` and Base32 | Next |
| PR 2 onward | Not started, see [docs/ROADMAP.md](docs/ROADMAP.md) |

## What exists

```
.gitignore          assets/ is excluded, see below
LICENSE             MIT
README.md           What the project is and what it refuses to do
SECURITY.md         Reporting process and the threat model so far
CONTRIBUTING.md     Review rules, including the no dependencies rule
handoff.md          This file
docs/ROADMAP.md     The PR by PR plan, 18 pull requests
docs/ARCHITECTURE.md  Structure and the decisions behind it
docs/UI_SPEC.md     Every screen, copied from the reference and where it is adapted
.github/workflows/ci.yml  Lint and test
```

## Decisions locked in

- iOS 18 and watchOS 11 minimum
- MIT license
- Zero third party dependencies
- Light mode is a v1 requirement, not a later addition
- Sync through iCloud Keychain, not CloudKit
- Squash merges into `main`, Conventional Commits

## Decisions still open

- Whether the `.xcodeproj` is checked in or generated from a spec. Decided in PR 5,
  current lean is to generate
- The encrypted export format. Decided in PR 16

## Notes for whoever works on this next

- `assets/` holds Step Two reference screenshots. It is gitignored on purpose and must
  never be committed. `docs/UI_SPEC.md` captures everything needed from it, so the work
  does not depend on having those files.
- Nothing has been pushed to the remote. Do not push without asking Xavier.
- No em dashes anywhere. CI enforces this.

## Next step

PR 1: create the `OpenFactorCore` package with `Package.swift` and no dependencies, then
implement RFC 4648 Base32 decoding and encoding with the published test vectors. Once
`Package.swift` exists, remove the conditional guard around the test step in
`.github/workflows/ci.yml`.
