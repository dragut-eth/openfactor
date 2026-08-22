#!/bin/bash
#
# Archive, export, validate and upload a build to TestFlight.
#
# Run from the repository root. Takes no arguments and asks no questions, which is the
# point: the whole cycle is shell commands once the credentials exist, so it can be run
# unattended rather than clicked through Xcode's Organizer.
#
#   ./scripts/ship-testflight.sh
#
# ## What a human has to set up once, and an agent cannot
#
# **Two different credentials solve two different problems, and conflating them wastes an
# afternoon.** The API key authenticates the *upload*. It cannot sign anything, cannot
# create certificates, and `-allowProvisioningUpdates` will not conjure one out of it.
# Signing comes entirely from the login keychain and the provisioning profiles.
#
# 1. An App Store Connect API key with the App Manager role, from Users and Access,
#    Integrations. The .p8 downloads exactly once. Put it where the tools look for it:
#
#        ~/.appstoreconnect/private_keys/AuthKey_<KEYID>.p8
#        ~/.appstoreconnect/issuer_id     <- the issuer UUID, one line, no newline fuss
#
#    In that path the key contents never appear on a command line or in shell history.
#
# 2. A distribution certificate and its private key in the login keychain. Check with
#    `security find-identity -v -p codesigning`; you want "Apple Distribution". Creating
#    these is account level and quota limited, and can offer to revoke the certificate
#    another machine depends on, which is why it stays a human's job.
#
# ## The trap that cost the sibling project an hour
#
# A wrong `teamID` in the export options produces:
#
#     error: exportArchive No signing certificate "iOS Distribution" found
#
# That reads as a missing certificate and invites you to create one. Usually nothing is
# missing and the team is simply wrong. An app can be developed under one team and
# distributed under another, and the development certificate in your keychain is not
# authority for which team ships. The profiles are:
#
#     ls ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles/
#     security cms -D -i <file>.mobileprovision | plutil -extract TeamIdentifier.0 raw -
#
# If someone says "but it worked from this machine before", believe them and go find what
# changed rather than concluding something is absent.

set -euo pipefail

# **A dirty tree fails the ship, before anything is built.**
#
# The provenance record's whole job is tying a build number to a commit. Built from uncommitted
# work, there is no commit to tie it to, and the record can only say so after the fact: the upload
# has already happened and the build number is already spent. **Recording the problem is not the
# same as preventing it**, which a reviewer pointed out about the version of this that only wrote
# it down.
#
# **No override flag**, deliberately. An escape hatch on a rule like this is how the rule becomes
# advisory. Commit it or stash it.
if [ -n "$(git status --porcelain)" ]; then
  echo "The working tree is not clean, so this build would belong to no commit."
  echo
  git status --short
  echo
  echo "Commit or stash first. docs/releases/ exists to tie a build number to a commit,"
  echo "and it cannot do that for a build made from uncommitted work."
  exit 1
fi

SCHEME="OpenFactor"
WORK="$(mktemp -d)"

trap 'rm -rf "$WORK"' EXIT

# **Nothing identifying anyone's account is written down here.** This repository is public.
# The key identifier, the issuer identifier and the key itself all live outside it, in the
# maintainer's home directory, and are read at run time. A key identifier is not the key,
# but publishing one is free exposure for no benefit.
#
# The team identifier is the exception, and deliberately so: it is already in the project
# file and ships inside every binary Apple distributes, which `docs/PROJECT.md` explains.
# It is read from the project rather than repeated, so there is one place it is written.
ISSUER_FILE="$HOME/.appstoreconnect/issuer_id"
KEYS_DIR="$HOME/.appstoreconnect/private_keys"

[ -f "$ISSUER_FILE" ] || { echo "Missing $ISSUER_FILE. See the comment at the top."; exit 1; }

# The key identifier is part of the file name Apple gives the key, so it never has to be
# stored separately or typed.
KEY_FILE="$(ls "$KEYS_DIR"/AuthKey_*.p8 2>/dev/null | head -1)"
[ -n "$KEY_FILE" ] || { echo "No AuthKey_*.p8 in $KEYS_DIR. See the comment at the top."; exit 1; }

KEY_ID="$(basename "$KEY_FILE" .p8)"
KEY_ID="${KEY_ID#AuthKey_}"

TEAM_ID="$(grep -m1 "DEVELOPMENT_TEAM = " OpenFactor.xcodeproj/project.pbxproj \
  | sed 's/.*DEVELOPMENT_TEAM = \([A-Z0-9]*\);.*/\1/')"
[ -n "$TEAM_ID" ] || { echo "Could not read DEVELOPMENT_TEAM from the project file."; exit 1; }

security find-identity -v -p codesigning | grep -q "Apple Distribution" || {
  echo "No Apple Distribution identity in the keychain. A human has to create it in Xcode."
  exit 1
}

cat > "$WORK/exportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key><string>app-store-connect</string>
	<key>signingStyle</key><string>automatic</string>
	<key>teamID</key><string>${TEAM_ID}</string>
	<key>uploadSymbols</key><true/>
	<key>destination</key><string>export</string>
</dict>
</plist>
PLIST

echo "==> Archiving Release"
xcodebuild archive \
  -project OpenFactor.xcodeproj -scheme "$SCHEME" -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$WORK/app.xcarchive" -derivedDataPath "$WORK/dd" \
  -allowProvisioningUpdates DEVELOPMENT_TEAM="$TEAM_ID" > "$WORK/archive.log" 2>&1 \
  || { tail -30 "$WORK/archive.log"; exit 1; }

# The watch app reaches a wrist only by riding inside the phone app's bundle. It was a
# sibling target for three pull requests and nothing local noticed, because Xcode installs
# each target it builds. Distribution is the only path that cares, so this is checked here
# as well as in CI.
[ -d "$WORK/app.xcarchive/Products/Applications/OpenFactor.app/Watch" ] || {
  echo "The watch app is not embedded in the archive. See docs/PROJECT.md."
  exit 1
}

echo "==> Exporting for the App Store"
xcodebuild -exportArchive \
  -archivePath "$WORK/app.xcarchive" \
  -exportOptionsPlist "$WORK/exportOptions.plist" \
  -exportPath "$WORK/export" \
  -allowProvisioningUpdates > "$WORK/export.log" 2>&1 \
  || { tail -30 "$WORK/export.log"; exit 1; }

# Validation is free and an upload is not: a rejected upload still spends the build number,
# and build numbers cannot be reused for a version.
echo "==> Validating"
xcrun altool --validate-app -f "$WORK/export/OpenFactor.ipa" -t ios \
  --apiKey "$KEY_ID" --apiIssuer "$(cat "$ISSUER_FILE")"

echo "==> Uploading"
xcrun altool --upload-app -f "$WORK/export/OpenFactor.ipa" -t ios \
  --apiKey "$KEY_ID" --apiIssuer "$(cat "$ISSUER_FILE")"

# ---- Provenance, recorded rather than remembered ------------------------------------
#
# `docs/BUILD_PROVENANCE.md` measures exactly what a reader can check about a shipped
# binary. The one thing it names as still missing is a hash recorded against the commit
# that produced it, so this writes one on every successful upload.
#
# **It does not let anybody verify their download**, and the document says so at length:
# Apple re-signs what it distributes, so no locally computed hash can match what lands on a
# device. What it does is tie a build number to a commit and a toolchain at the moment of
# shipping, which is what gate A5 needs to audit a release diff, and which is a claim made
# before the fact rather than reconstructed from memory afterwards.
#
# **After the upload rather than before it.** A record of a build that failed validation
# and never shipped would be worse than no record.
# **The record cannot fail the ship.** Everything below runs after a successful upload, so a
# failure here loses no build, but under `set -euo pipefail` it would still exit non-zero and
# read as a failed release. You would then be debugging a hash tool at the exact moment you
# wanted to be finished. Recorded on a best effort, and loudly if it does not work.
echo "==> Recording provenance"
set +e
(
ARCHIVE_PLIST="$WORK/app.xcarchive/Info.plist"
SHORT_VERSION="$(plutil -extract ApplicationProperties.CFBundleShortVersionString raw -o - "$ARCHIVE_PLIST")"
BUILD_VERSION="$(plutil -extract ApplicationProperties.CFBundleVersion raw -o - "$ARCHIVE_PLIST")"
COMMIT="$(git rev-parse HEAD)"
# Clean by construction: the check at the top of this script refuses to build otherwise. Recorded
# anyway, because a record that states its preconditions is readable years later by somebody who
# does not have this script in front of them.
TREE_STATE="clean, enforced before the build"

mkdir -p docs/releases
RECORD="docs/releases/$SHORT_VERSION-$BUILD_VERSION.md"
{
  echo "# $SHORT_VERSION ($BUILD_VERSION)"
  echo
  echo "Uploaded $(date -u '+%Y-%m-%d %H:%M UTC')."
  echo
  echo "| | |"
  echo "| --- | --- |"
  echo "| Commit | \`$COMMIT\` |"
  echo "| Working tree | $TREE_STATE |"
  echo "| Toolchain | $(xcodebuild -version | tr '\n' ' ' | sed 's/  */ /g') |"
  echo
  echo "## Hashes of what was built"
  echo
  echo "SHA-256, computed locally. **Apple re-signs what it distributes, so none of these"
  echo "will match a binary on a device.** See \`docs/BUILD_PROVENANCE.md\` for what that"
  echo "does and does not leave a reader able to check."
  echo
  echo '```'
  shasum -a 256 "$WORK/export/OpenFactor.ipa" | sed "s|$WORK/export/||"
  # **Named rather than discovered.** A find that walks the bundle looking for Mach-O files
  # would quietly record four binaries instead of five the day a target stops being
  # embedded, which is the exact failure the watch check above exists for. These are the
  # five docs/BUILD_PROVENANCE.md measured, and a missing one is said out loud.
  APPS="$WORK/app.xcarchive/Products/Applications"
  for binary in \
    "OpenFactor.app/OpenFactor" \
    "OpenFactor.app/PlugIns/OpenFactorShare.appex/OpenFactorShare" \
    "OpenFactor.app/Watch/OpenFactorWatch.app/OpenFactorWatch" \
    "OpenFactor.app/Watch/OpenFactorWatch.app/PlugIns/OpenFactorComplication.appex/OpenFactorComplication"
  do
    if [ -f "$APPS/$binary" ]; then
      printf '%s  %s\n' "$(shasum -a 256 "$APPS/$binary" | cut -d' ' -f1)" "$binary"
    else
      printf '%-64s  %s\n' "MISSING" "$binary"
    fi
  done
  echo '```'
  echo
  echo "## Canonical hashes"
  echo
  echo "The compiled code, per architecture slice, with the linker's UUID and the signature"
  echo "excluded by construction. **Reproducible**: anybody who builds this commit with the"
  echo "toolchain above can run \`scripts/canonical-hash.sh\` and get these values. See"
  echo "\`docs/BUILD_PROVENANCE.md\` for what that does and does not establish, and for the"
  echo "part no mechanism on this platform reaches."
  echo
  echo '```'
  for binary in \
    "OpenFactor.app/OpenFactor" \
    "OpenFactor.app/PlugIns/OpenFactorShare.appex/OpenFactorShare" \
    "OpenFactor.app/Watch/OpenFactorWatch.app/OpenFactorWatch" \
    "OpenFactor.app/Watch/OpenFactorWatch.app/PlugIns/OpenFactorComplication.appex/OpenFactorComplication"
  do
    if [ -f "$APPS/$binary" ]; then
      ./scripts/canonical-hash.sh "$APPS/$binary"
    else
      printf '%-64s  %s\n' "MISSING" "$binary"
    fi
  done
  echo '```'
} > "$RECORD"
)
PROVENANCE_STATUS=$?
set -e

if [ "$PROVENANCE_STATUS" -ne 0 ]; then
  echo
  echo "The provenance record could not be written. THE UPLOAD SUCCEEDED ANYWAY."
  echo "Nothing is lost except the record, and $RECORD may be incomplete."
  echo "Fix it and write the record by hand before the next release: without it nothing"
  echo "ties this build number to a commit, which is what docs/releases/ exists for."
else
  echo "Wrote $RECORD. Commit it: it is the only thing tying this build to a commit."
fi

echo
echo "Uploaded. Processing takes five to fifteen minutes, then in App Store Connect:"
echo "  1. clear the export compliance question on the build"
echo "  2. add the build to the internal testing group"
echo
echo "Bump CURRENT_PROJECT_VERSION before the next run. A build number cannot be reused."
