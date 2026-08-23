# AGENTS.md

Setup for agents working in this repository.

**Deliberately mechanical.** There are no claims here about the app's security properties and no
argument for any design decision. Those are in `README.md`, `SECURITY.md`, `docs/` and
`docs/audits/`, and you reach them by choosing to rather than by loading this file.

## Read first

`HANDOFF.md` is the running state: what is in progress, what is open, and what was recently
learned the hard way.

## The rules

`CONTRIBUTING.md`. They are not repeated here. Two copies of a rule is how this project has more
than once ended up with two different rules.

## Build and test

    swift test        the OpenFactorCore package, no Xcode project needed

    xcodebuild test -project OpenFactor.xcodeproj -scheme OpenFactor \
      -destination 'platform=iOS Simulator,name=<any available iPhone>'

## What CI will fail you on

`.github/workflows/ci.yml` is the authority. In summary: em dashes anywhere outside
`docs/audits/`, networking symbols in the built binary, project settings that disagree with
`docs/PROJECT.md`, absolute home directory paths in tracked files, published surfaces naming
different security contacts, and shell scripts failing `shellcheck -S info`.

## If you are auditing rather than contributing

The most useful review of this repository so far was run blind. **Its prompt is recorded verbatim**
in `docs/audits/X/X1-codex-blind-audit.md`, so it can be re-run against a later commit or improved
on. In outline it asked the reviewer to read the claimed security properties first, inspect the
implementation, entitlements and tests against them, try to falsify them, and leave `docs/audits/`
until their own findings were written down.

**That is offered rather than asked.** This repository is the subject and is in no position to set
the method of its own audit. Use it, change it, or ignore it.
