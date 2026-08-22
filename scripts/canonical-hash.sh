#!/bin/bash
#
# The hash of a Mach-O's compiled code, excluding everything the linker and Apple vary.
#
# ## What this is for
#
# **A reader cannot check the binary the App Store gave them.** Apple re-signs it, thins it per
# device model, and the main binary on an App Store install is encrypted, so there is nothing to
# hash without a jailbreak. `docs/BUILD_PROVENANCE.md` measures the first half of that: two Release
# builds of identical source, on one machine, minutes apart, and every shipping binary differed.
#
# **What that document also measured is where they differ, and it is small.** The whole of `__TEXT`
# was byte identical except a sixteen byte run, the `LC_UUID` the linker stamps into every Mach-O,
# plus a little `__DATA` and the signature that must change once anything above it does.
#
# **So the compiled code is deterministic even though the container is not**, and this hashes the
# compiled code alone: the `__TEXT,__text` section, which is the instructions and nothing else.
# `LC_UUID` lives in the load commands rather than in that section, so it is excluded by
# construction rather than by subtracting a magic offset that a toolchain update would move.
#
# **What it proves and what it does not.** Anybody who builds the same tag with the same toolchain
# can run this and compare. If it matches, the source they read compiles to the code this project
# says it does. **It says nothing about the binary Apple served to a phone**, and no mechanism
# available on this platform does.
#
#   ./scripts/canonical-hash.sh path/to/Binary
#
set -euo pipefail

BINARY="${1:?usage: canonical-hash.sh <mach-o binary>}"
[ -f "$BINARY" ] || { echo "No such file: $BINARY"; exit 1; }

# Section offset and size, read from the load commands rather than guessed. otool prints them in
# hex for `size` and `offset`; both are needed and both are taken from the same stanza.
# **Every architecture, separately.** A universal binary holds one Mach-O per slice, each with its
# own load commands and its own `__text`, and their file offsets are relative to the whole file.
# The first version of this read the first `__text` stanza and hashed from the fat file's start,
# which for the watch app ran past that slice and into the next one's load commands. It looked
# exactly like nondeterministic compiled code: sixteen bytes differing between builds, which turned
# out to be the second slice's `LC_UUID` being counted as instructions. **The phone app and the
# extension are thin, so the fault was invisible on two binaries out of three.**
for ARCH in $(lipo -archs "$BINARY" 2>/dev/null || echo ""); do
  SLICE=$(mktemp)
  if ! lipo -thin "$ARCH" "$BINARY" -output "$SLICE" 2>/dev/null; then cp "$BINARY" "$SLICE"; fi

  # `size` is printed in hex and `offset` in decimal, which is a trap worth naming: read them the
  # way otool prints them rather than assuming one base for both.
  STANZA=$(otool -l "$SLICE" | grep -A6 "sectname __text" | head -8)
  SIZE_HEX=$(printf '%s\n' "$STANZA" | awk '/^ *size /{print $2; exit}')
  OFFSET=$(printf '%s\n' "$STANZA" | awk '/^ *offset /{print $2; exit}')
  SIZE=$((SIZE_HEX))

  if [ -z "${OFFSET:-}" ] || [ -z "${SIZE:-}" ]; then
    echo "Could not find __TEXT,__text in $BINARY ($ARCH)"; rm -f "$SLICE"; exit 1
  fi

  HASH=$(dd if="$SLICE" bs=1 skip="$OFFSET" count="$SIZE" 2>/dev/null | shasum -a 256 | cut -d' ' -f1)
  printf '%s  %s (%s)  (__TEXT,__text, %s bytes)\n' "$HASH" "$(basename "$BINARY")" "$ARCH" "$SIZE"
  rm -f "$SLICE"
done
