#!/usr/bin/env bash
set -euo pipefail

for key in CERTIFICATE_BASE64 CERTIFICATE_PASSWORD PROFILE_BASE64; do
  if [[ -z "${!key}" ]]; then
    echo "::error::Missing iOS signing secret: $key"
    exit 1
  fi
done

umask 077
printf '%s' "$CERTIFICATE_BASE64" | base64 --decode > "$RUNNER_TEMP/certificate.p12"
printf '%s' "$PROFILE_BASE64" | base64 --decode > "$PROFILE_PATH"
security cms -D -i "$PROFILE_PATH" > "$RUNNER_TEMP/profile.plist"
python3 tool/ios_signing.py

keychain_password="$(openssl rand -hex 32)"
echo "::add-mask::$keychain_password"
security create-keychain -p "$keychain_password" "$KEYCHAIN_PATH"
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
security unlock-keychain -p "$keychain_password" "$KEYCHAIN_PATH"
security import "$RUNNER_TEMP/certificate.p12" -P "$CERTIFICATE_PASSWORD" \
  -A -t cert -f pkcs12 -k "$KEYCHAIN_PATH"
security set-key-partition-list -S apple-tool:,apple: -k "$keychain_password" "$KEYCHAIN_PATH"
security list-keychains -d user -s "$KEYCHAIN_PATH" "$HOME/Library/Keychains/login.keychain-db"

profile_uuid="$(/usr/libexec/PlistBuddy -c 'Print UUID' "$RUNNER_TEMP/profile.plist")"
mkdir -p "$HOME/Library/MobileDevice/Provisioning Profiles"
cp "$PROFILE_PATH" "$HOME/Library/MobileDevice/Provisioning Profiles/$profile_uuid.mobileprovision"
