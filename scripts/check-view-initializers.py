#!/usr/bin/env python3
"""Refuses SwiftUI views whose initializers do work on an object they have just built.

**Why this exists.** SwiftUI calls a view's initializer every time the view is rebuilt, and a sheet
presented over the account list is rebuilt once a second, because the list redraws for its codes.
Two defects came from forgetting that, both shipped, both passed every test and four audits:

- The add screen loop, fixed on 2026-10-02. `AddAccountView` built a session in its initializer,
  decoded a shared image into it, and held it as `@Bindable`, which is not storage. Each rebuild
  replaced the session and decoded again, so canceling a transfer preview reopened it forever.
- Audit X5, S3. `ImportView` read, parsed and classified a file in its initializer. SwiftUI kept
  the first model and threw the rest away, so the screen looked right while every stored secret was
  decrypted once a second.

The rule that prevents both: **an initializer may assign, and nothing else.** Work belongs in
`onAppear` or `.task`, behind a flag kept in `@State`, which survive rebuilds.

**What this flags, in any `struct ...: View` in the app and watch targets:**

1. A method called on an object built in the same initializer, as in `model.read(url)` after
   `let model = ImportViewModel(...)`. Setting a property on it is allowed; that is configuration.
2. A newly built object stored into a property declared `@Bindable` or `@ObservedObject`, directly
   or through a local. Those wrappers do not own what they hold, so every rebuild replaces it.

**What it is not.** A grep with brackets counted, not a Swift parser. It reads the shapes this
project has actually written. A clever enough initializer can hide work from it, and a review is
still the real defense; this catches the plain version of a mistake that has already cost two
releases.

Run from the repository root. Exits non-zero, naming file and line, when it finds anything.
"""

import re
import subprocess
import sys

TARGETS = ["OpenFactor", "OpenFactorWatch Watch App", "OpenFactorShare"]
NON_OWNING = re.compile(r"@(Bindable|ObservedObject)\b[^\n]*?\bvar\s+(\w+)")
VIEW_STRUCT = re.compile(r"\bstruct\s+(\w+)\s*(?:<[^>]*>)?\s*:\s*[^{]*\bView\b[^{]*\{")
BUILT_LOCAL = re.compile(r"^\s*(?:let|var)\s+(\w+)\s*=\s*([A-Z]\w*)\s*\(")
INIT_START = re.compile(r"^\s*(?:public\s+|private\s+|fileprivate\s+|internal\s+)?init\s*\(")


def block_end(text, open_index):
    """Index just past the brace matching the one at open_index. Strings and comments are rare
    enough in initializers that counting braces is adequate for this project's code."""
    depth = 0
    for i in range(open_index, len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return i + 1
    return len(text)


def initializers(body):
    """Yields (offset, text) for each init body directly inside a struct body."""
    lines = body.split("\n")
    offset = 0
    i = 0
    starts = []
    for line in lines:
        starts.append(offset)
        offset += len(line) + 1
    while i < len(lines):
        if INIT_START.match(lines[i]):
            # The signature may span lines and contain closures, so find the brace that opens the
            # body by matching parentheses first.
            j = starts[i] + lines[i].index("init")
            paren = body.index("(", j)
            depth = 0
            k = paren
            while k < len(body):
                if body[k] == "(":
                    depth += 1
                elif body[k] == ")":
                    depth -= 1
                    if depth == 0:
                        break
                k += 1
            brace = body.index("{", k)
            end = block_end(body, brace)
            yield brace, body[brace + 1:end - 1]
            while i < len(lines) and starts[i] < end:
                i += 1
            continue
        i += 1


def check_file(path):
    text = open(path, encoding="utf-8").read()
    problems = []
    for match in VIEW_STRUCT.finditer(text):
        struct_open = match.end() - 1
        struct_end = block_end(text, struct_open)
        body = text[struct_open + 1:struct_end - 1]
        non_owning = {m.group(2) for m in NON_OWNING.finditer(body)}

        for init_offset, init_body in initializers(body):
            built = {}
            for number, line in enumerate(init_body.split("\n")):
                stripped = line.strip()
                if stripped.startswith("//"):
                    continue
                absolute = text.count("\n", 0, struct_open + 1 + init_offset + 1) + number + 1

                local = BUILT_LOCAL.match(line)
                if local:
                    built[local.group(1)] = local.group(2)
                    continue

                for name in built:
                    # A call on the freshly built object, possibly through a property: `x.f(` or
                    # `x.scan.f(`. Plain assignment to one of its properties is allowed.
                    if re.search(rf"\b{name}(?:\.\w+)*\.\w+\s*\(", stripped) and not re.search(
                        rf"\b{name}(?:\.\w+)+\s*=[^=]", stripped
                    ):
                        problems.append(
                            f"{path}:{absolute}: {match.group(1)}.init calls a method on "
                            f"'{name}', a {built[name]} it just built. Initializers run on every "
                            f"rebuild; do the work in onAppear behind a @State flag."
                        )

                for prop in non_owning:
                    stored = re.search(rf"\bself\.{prop}\s*=\s*(\w+)", stripped)
                    if stored and (stored.group(1) in built or stored.group(1)[:1].isupper()):
                        problems.append(
                            f"{path}:{absolute}: {match.group(1)}.init stores a newly built object "
                            f"in '{prop}', which is @Bindable or @ObservedObject and does not own "
                            f"it. Every rebuild replaces it; hold it in @State instead."
                        )
    return problems


def main():
    files = subprocess.run(
        ["git", "ls-files", "--", *[f"{t}/*.swift" for t in TARGETS]],
        capture_output=True, text=True, check=True,
    ).stdout.split("\n")
    problems = [p for f in files if f for p in check_file(f)]
    for problem in problems:
        print(problem)
    if problems:
        print(f"\n{len(problems)} view initializer(s) doing work. See scripts/check-view-initializers.py.")
        return 1
    print("No view initializer does work on an object it builds.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
