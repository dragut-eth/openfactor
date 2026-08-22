# Verifying a build of OpenFactor

**Four things you can check, in order of what they cost you**, and one you cannot check at all.
Every step says what it proves, because a check whose meaning is vague is worse than no check.

**The reasoning behind all of this is in [docs/BUILD_PROVENANCE.md](docs/BUILD_PROVENANCE.md)**,
including where two builds of one commit differ and why. This page is the instructions.

---

## 1. Read the record. No tools.

**Which commit was last reviewed:** the `audit-a4` tag. Gate A4's conclusion is
[docs/audits/A4.md](docs/audits/A4.md) and every gate after it reviews the diff since that tag.

**Which commit a shipped build came from:** [docs/releases/](docs/releases/), one file per upload,
written by the ship script rather than by hand. Each carries the commit, whether the working tree
was clean, the toolchain to its build number, and hashes of what was built.

**What this proves:** nothing on its own. **It is a claim this project made about itself, in
public, before anybody could check it.** Its value is that it can be contradicted later.

## 2. Read the shipped bundle. About a minute.

An `.ipa` is a zip. Unzip it and you have `Payload/OpenFactor.app/`.

**Obtaining one is the awkward part and it is not a supported operation.** Apple removed app
downloads from iTunes, and the tools that still manage it use interfaces Apple does not promise to
keep. **If you cannot get the file, steps 3 and 4 do not need it.**

```bash
unzip -q OpenFactor.ipa -d extracted
cd extracted/Payload/OpenFactor.app
```

**The build number, so you can match it to a release record:**

```bash
plutil -extract CFBundleVersion raw Info.plist
```

**That the share extension was not signed with a Keychain access group**, which CI enforces against
the source and this checks against what shipped. Run it against both, because the contrast is the
evidence:

```bash
codesign -d --entitlements - PlugIns/OpenFactorShare.appex 2>/dev/null
codesign -d --entitlements - . 2>/dev/null
```

The app carries a `keychain-access-groups` array naming `<TEAMID>.dev.openfactor.shared`. **The
extension has no `keychain-access-groups` key at all.** Both carry the same app group and team
identifier, so you are comparing two entitlement sets that differ in exactly one place.

**That is the whole of what this proves, and it is deliberately narrower than it sounds.** An
extension with no access group still gets the default group derived from its application
identifier, so it is not shut out of the Keychain as such, only out of the app's group. And gate E1
established that a Keychain access group is not a confidentiality boundary in the first place:
`SECURITY.md` says so at length, and the vault exists because of it. What you have checked is that
the boundary Apple provides was configured as claimed, not that the boundary is strong.

**That the executable references no networking symbol.** Linked frameworks are the check people
reach for first and they establish much less than they appear to, because `URLSession` lives in
Foundation and every app links Foundation. Run both, and read the second one as the real result:

```bash
otool -L OpenFactor | tail -n +2 | grep -iE "CFNetwork|/Network\.framework|NetworkExtension" || echo "no framework"

nm -u OpenFactor | sed 's/^ *//' | grep -E \
  'OBJC_CLASS_\$_NSURL(Session|Connection)|\$_NSNetService|\$_NSStream|^_+(NS)?URLSession|^_+NSURLConnection|^_+CF(ReadStreamCreate|WriteStreamCreate|Host|NetService|Socket|URLRequest|URLConnection|HTTPMessage)|^_+nw_(connection|endpoint|listener|browser|path_monitor|parameters)|^_(socket|connect|bind|listen|accept|sendto|recvfrom|getaddrinfo|gethostbyname|res_query)$|^_+SSL(CreateContext|Handshake|Write|Read)|swift_FoundationNetworking' \
  | sort -u
```

**Expected from the second command: no output.** The `|| echo` trick does not work on it, because
the pipeline's status is `sort`'s rather than `grep`'s, so silence is the result to read.

That pattern is the one CI runs on every push, character for character. **It was written from what
`nm` actually printed for a deliberately broken build that called `URLSession`**, not from a guess
about symbol shapes, because the first draft of it passed while lying.

**Satisfy yourself the pattern has teeth** before you trust a clean result from it. Point it at
something that certainly makes network requests:

```bash
nm -u /usr/bin/nscurl | sed 's/^ *//' | grep -E '_OBJC_CLASS_\$_NSURLSession|^_nw_connection' | sort -u
```

**The symbol table survives the encryption**, which is why this works on a shipped binary at all:
the encrypted range is inside `__TEXT`, and `nm` reads `__LINKEDIT`. Measured rather than assumed,
on an Apple-distributed build of this app, and the measurement's limit is recorded below.

**What this proves:** two of this project's published claims, **against the bundle Apple
distributed** rather than against a build anybody made for you. The main executable's code is
encrypted, so this reaches the bundle's structure, entitlements and symbol references, and not the
code itself.

## 3. Rebuild the code and compare it. Xcode required.

```bash
git clone https://github.com/dragut-eth/openfactor.git
cd openfactor
git checkout audit-a4        # or the commit named in a release record

xcodebuild build -project OpenFactor.xcodeproj -scheme OpenFactor \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath build/verify

./scripts/canonical-hash.sh \
  build/verify/Build/Products/Release-iphoneos/OpenFactor.app/OpenFactor
```

**Compare the per-section digests to the ones in the release record for that commit.**

**Use the pinned toolchain.** `docs/BUILD_PROVENANCE.md` names it to the build number. A different
Xcode will produce different code and the digests will not match, which is correct rather than a
fault.

**What this proves:** that the source you just read produces the same measured code sections that
were recorded for this release. **"The same" means the equivalence `scripts/canonical-hash.sh`
defines**, which is per-section digests of every section carrying file bytes, per architecture
slice, with the linker's `LC_UUID` and the code signature excluded by construction. That script is
forty lines and reading it is the only way to know what you just compared. **This is the strongest
thing on the page and it needs nothing from us**: you built it, you hashed it, you compared.

## 4. Check that two of your own builds agree. Xcode, twice.

```bash
for i in 1 2; do
  xcodebuild build -project OpenFactor.xcodeproj -scheme OpenFactor \
    -configuration Release -destination 'generic/platform=iOS' \
    -derivedDataPath "build/repro$i"
done

diff \
  <(./scripts/canonical-hash.sh build/repro1/Build/Products/Release-iphoneos/OpenFactor.app/OpenFactor) \
  <(./scripts/canonical-hash.sh build/repro2/Build/Products/Release-iphoneos/OpenFactor.app/OpenFactor)
```

**Expected: no output.** Every section `canonical-hash.sh` measures is identical between two
independent builds.
The whole binaries will differ, because the linker stamps a fresh `LC_UUID` and the signature
changes with it. That difference is measured and explained in `docs/BUILD_PROVENANCE.md`.

**What this proves:** that the digests in step 3 are a property of the source rather than of one
particular build on one particular afternoon.

**And you are not the only one who can do this.** Every push runs the same Release build on
GitHub's macOS runners and **prints the per-section digests into a public, dated log**. That runner
is not our machine, so a reader who repeats step 4 for a simulator can compare against it without
trusting anything of ours. **Those are simulator values**, so they cannot be compared to the device
hashes in a release record.

---

## What none of this establishes

**That the binary Apple served to your phone contains that code.**

The executable in an App Store install is encrypted, and the code signature authenticates the
stored ciphertext rather than the plaintext, so **there is nothing on a stock device to hash.**

**The precise statement, because a looser one would be wrong in both directions:** this
correspondence **cannot be verified on stock iOS through public, supported interfaces.** It is not
impossible in an absolute sense: an auditor with a sufficiently privileged research device can dump
the decrypted executable and compare it. That is specialised, fragile, and unavailable to an
ordinary user.

**The honest way past it is not a hash.** Build the tagged commit and run your own, rather than
trusting a binary you cannot inspect. Steps 3 and 4 are most of what that takes.

**And one limit on the symbol check in step 2, stated because this page is the wrong place to
round a measurement up.** It was run against an Apple-distributed build of this app, 1.0 (5),
carrying `cryptid 1`, and `nm` read 1,403 undefined symbols straight through it. But the encrypted
range on that copy was **4,096 bytes against a `__TEXT` of 1,130,496**, one page rather than the
whole segment. The symbol table lives in `__LINKEDIT` either way, so nothing about a larger
encrypted range should change the result. **Should is not did.** If you run step 2 on a copy whose
`cryptsize` covers the whole segment and `nm` comes back empty, that is a finding and
`SECURITY.md` names where to send it.

## What would change this

An Apple mechanism publishing a signed measurement of the plaintext it distributes, or an
independent audit that dumps and compares a decrypted store binary. **Neither exists for this app
today**, and this page will say so until one does.
