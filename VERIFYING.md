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

**That the share extension cannot reach the Keychain**, which `SECURITY.md` claims and CI enforces
internally. It should print one entitlement, the app group, and nothing else:

```bash
codesign -d --entitlements - PlugIns/OpenFactorShare.appex 2>/dev/null
```

**That nothing links a networking framework**, which is the strongest form of the no-network claim
because it runs against the artifact rather than the source:

```bash
otool -L OpenFactor | grep -iE "Network|CFNetwork|Socket" || echo "none"
```

**What this proves:** three of this project's published claims, **against the bundle Apple
distributed** rather than against a build anybody made for you. The main executable is encrypted,
so this reaches everything except the code itself.

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

**What this proves:** that the source you just read compiles to exactly the code this project
publishes. **This is the strongest thing on the page and it needs nothing from us**: you built it,
you hashed it, you compared.

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

**Expected: no output.** Every section with file bytes is identical between two independent builds.
The whole binaries will differ, because the linker stamps a fresh `LC_UUID` and the signature
changes with it. That difference is measured and explained in `docs/BUILD_PROVENANCE.md`.

**What this proves:** that the digests in step 3 are a property of the source rather than of one
particular build on one particular afternoon.

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

## What would change this

An Apple mechanism publishing a signed measurement of the plaintext it distributes, or an
independent audit that dumps and compares a decrypted store binary. **Neither exists for this app
today**, and this page will say so until one does.
