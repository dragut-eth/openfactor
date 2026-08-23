# Contributing

**Agents are pointed here by `AGENTS.md`**, which carries the mechanical setup and nothing else.
The rules live in this file only, so there is one copy of each.

The point of this project is that a stranger can read the source and decide to trust it.
Every rule below exists to keep that true.

## The one rule

**Keep changes small enough to actually review.** A pull request that cannot be read in
one sitting will not be read carefully, and unreviewed code in an authenticator is worse
than no code at all. If a change is getting long, split it.

## Before you open a pull request

- [ ] Tests pass locally: `swift test`
- [ ] New behavior in `OpenFactorCore` has tests in the same pull request
- [ ] Documentation affected by the change is updated in the same pull request, never as a
      follow up. That includes `README.md`, `HANDOFF.md`, and anything under `docs/`
- [ ] No new third party dependency, see below
- [ ] No file grew past roughly 300 lines. Split instead

## Code style

- Swift API Design Guidelines. Clarity at the point of use beats brevity.
- One concept per file, named after the concept.
- No abbreviations in names. `secret` not `sec`, `period` not `p`.
- Comments explain why, not what. If a comment is needed to explain what, rename things.
- Anything non obvious in the cryptography carries a comment citing the RFC and section.

## Dependencies

The project has zero third party dependencies and intends to keep it that way. Every
dependency is code a user must trust without having chosen to. A pull request adding one
needs to argue why the functionality cannot come from Apple's frameworks, and that
argument goes in `docs/ARCHITECTURE.md`, not just in the review thread.

## Security sensitive changes

Anything touching `OpenFactorCore`, the Keychain, sync, or export gets extra scrutiny:

- Say in the description what the change means for the threat model. If nothing changes,
  say that.
- Update `SECURITY.md` if any claim in it is now different.
- Never log, print, or put secret material into an error message.
- Never add a network call. There are none, and that is a feature.

Found a vulnerability rather than fixing one? Do not open a pull request. Follow
[SECURITY.md](SECURITY.md).

## Commits

[Conventional Commits](https://www.conventionalcommits.org/): `feat:`, `fix:`, `docs:`,
`test:`, `refactor:`, `chore:`. Branches are short lived and merge into `main` as a squash.

## Writing style

- No em dashes anywhere, in code, comments, documentation, or commit messages. Use a
  comma, a colon, parentheses, or two sentences.
- Plain language. Anything a user reads in the app, especially about security, says what
  actually happens rather than reassuring them.
