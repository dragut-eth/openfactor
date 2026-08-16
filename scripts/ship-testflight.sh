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

TEAM_ID="HST4KH9P2X"
KEY_ID="PVPR4GTMF6"
SCHEME="OpenFactor"
WORK="$(mktemp -d)"

trap 'rm -rf "$WORK"' EXIT

ISSUER_FILE="$HOME/.appstoreconnect/issuer_id"
KEY_FILE="$HOME/.appstoreconnect/private_keys/AuthKey_${KEY_ID}.p8"

[ -f "$ISSUER_FILE" ] || { echo "Missing $ISSUER_FILE. See the comment at the top."; exit 1; }
[ -f "$KEY_FILE" ] || { echo "Missing $KEY_FILE. See the comment at the top."; exit 1; }

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

echo
echo "Uploaded. Processing takes five to fifteen minutes, then in App Store Connect:"
echo "  1. clear the export compliance question on the build"
echo "  2. add the build to the internal testing group"
echo
echo "Bump CURRENT_PROJECT_VERSION before the next run. A build number cannot be reused."
