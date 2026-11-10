#!/usr/bin/env bash
# Sign real CI artifacts with an isolated temporary key for end-to-end tests.
set -euo pipefail
debs=$1
out=$2
root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'gpgconf --homedir "$work" --kill gpg-agent >/dev/null 2>&1 || true; rm -rf -- "$work"' EXIT
chmod 0700 "$work"
export GNUPGHOME="$work"
gpg --batch --pinentry-mode loopback --passphrase test-passphrase \
  --quick-gen-key 'APT test <apt-test@example.invalid>' ed25519 cert 1d >/dev/null 2>&1
fingerprint=$(gpg --batch --with-colons --list-secret-keys | awk -F: '$1 == "fpr" {print $10; exit}')
gpg --batch --pinentry-mode loopback --passphrase test-passphrase --quick-add-key "$fingerprint" ed25519 sign 1d >/dev/null 2>&1
APT_SIGNING_KEY=$(gpg --batch --pinentry-mode loopback --passphrase test-passphrase --armor --export-secret-subkeys "$fingerprint")
export APT_SIGNING_KEY APT_SIGNING_FINGERPRINT="$fingerprint" APT_SIGNING_PASSPHRASE=test-passphrase
bash "$root/build/make-apt-repo.sh" "$debs" "$out"
