# AGENTS.md

Setup for agents working in this repository.

**Deliberately mechanical.** There are no claims here about the app's security properties and no
argument for any design decision. Those are in `README.md`, `SECURITY.md`, `docs/` and
`docs/audits/`, and you reach them by choosing to rather than by loading this file.

## Read first

`HANDOFF.md` is the running state. Read its first section, **Where things stand**, and its last,
**Notes for whoever works on this next**. Working only on the website, read **The website:
working on it cold**, the section after the first, which is self-contained. The other sections
are dated history: consult one when a task touches it.

## The rules

`CONTRIBUTING.md`. They are not repeated here. Two copies of a rule is how this project has more
than once ended up with two different rules.

## Build and test

    swift test        the OpenFactorCore package, no Xcode project needed

    xcodebuild test -project OpenFactor.xcodeproj -scheme OpenFactor \
      -destination 'platform=iOS Simulator,name=<any available iPhone>'

## What CI will fail you on

`.github/workflows/ci.yml` is the authority, and each step's name says what it refuses:

    grep -E '^\s+- name:' .github/workflows/ci.yml

## If you are auditing rather than contributing

`SECURITY.md` has the section on it: where to send a report, what makes one useful, and what gets
published. The prompt used for the blind audits X1 to X4, unchanged across four reviewers, is
recorded in `docs/audits/X/X1-codex-blind-audit.md`.

**Both are offered rather than asked.** This repository is the subject and is in no position to set
the method of its own audit. Use them, change them, or ignore them.
