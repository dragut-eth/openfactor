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

# **Canonicalisation version 2.** Recorded because every ignored byte range is somewhere content
# could hide, so which ranges are ignored has to be a versioned, checkable statement rather than
# whatever the script happened to do that day. Version 1 hashed `__TEXT,__text` alone.
CANON_VERSION=2

BINARY="${1:?usage: canonical-hash.sh <mach-o binary>}"
[ -f "$BINARY" ] || { echo "No such file: $BINARY"; exit 1; }

echo "# canonicalisation v$CANON_VERSION  $(basename "$BINARY")"

# **Every architecture, separately.** A universal binary holds one Mach-O per slice, each with its
# own load commands and its own sections, and their file offsets are relative to the whole file.
# The first version of this read the first `__text` stanza and hashed from the fat file's start,
# which for the watch app ran past that slice into the next one's load commands. It looked exactly
# like nondeterministic compiled code: sixteen bytes differing between builds, which turned out to
# be the second slice's `LC_UUID` counted as instructions. The phone app and the extension are
# thin, so the fault was invisible on two binaries out of three.
for ARCH in $(lipo -archs "$BINARY" 2>/dev/null || echo "-"); do
  SLICE=$(mktemp)
  if [ "$ARCH" = "-" ] || ! lipo -thin "$ARCH" "$BINARY" -output "$SLICE" 2>/dev/null; then
    cp "$BINARY" "$SLICE"
  fi

  echo "## $ARCH"

  # **Per section, reported separately, never rolled into one opaque number.** A single digest
  # hides which parts matched, and a reader who disagrees with the boundary cannot re-draw it.
  # `size` prints in hex and `offset` in decimal, which is a trap worth naming.
  otool -l "$SLICE" | awk '
    /sectname /   { sect = $2 }
    /segname /    { seg = $2 }
    /^ *size /    { if (sect != "" && size == "") size = $2 }
    /^ *offset /  { if (size != "") { print seg "," sect, size, $2; sect=""; seg=""; size="" } }
  ' | while read -r NAME SIZE_HEX OFFSET; do
    SIZE=$((SIZE_HEX))
    # **Zero-fill sections occupy no file bytes.** `__bss` has offset 0 and would otherwise be
    # "hashed" by reading the Mach-O header, which contains LC_UUID and varies every build. That
    # produced a false nondeterminism finding before it was noticed.
    if [ "$OFFSET" -eq 0 ] || [ "$SIZE" -eq 0 ]; then
      printf '%-64s  %s  (no file bytes)\n' "-" "$NAME"
      continue
    fi
    HASH=$(dd if="$SLICE" bs=1 skip="$OFFSET" count="$SIZE" 2>/dev/null | shasum -a 256 | cut -d' ' -f1)
    printf '%s  %s  (%s bytes)\n' "$HASH" "$NAME" "$SIZE"
  done

  rm -f "$SLICE"
done
