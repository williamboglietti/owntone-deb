#!/usr/bin/env bash
# Build a standard signed APT repository for OwnTone.
# Usage: bash make-apt-repo.sh DEB_DIRECTORY OUTPUT_DIRECTORY
# Required environment: APT_SIGNING_KEY, APT_SIGNING_PASSPHRASE,
# APT_SIGNING_FINGERPRINT. The private key is read only from the environment.
set -euo pipefail
export LC_ALL=C

debs=$1
out=$2
suite=noble

for name in APT_SIGNING_KEY APT_SIGNING_PASSPHRASE APT_SIGNING_FINGERPRINT; do
  if ! printenv "$name" >/dev/null 2>&1; then
    printf 'Missing required environment variable: %s\n' "$name" >&2
    exit 1
  fi
done
if [[ ! "$APT_SIGNING_FINGERPRINT" =~ ^[0-9A-Fa-f]{40}$ ]]; then
  echo "APT_SIGNING_FINGERPRINT must be a 40-character OpenPGP fingerprint" >&2
  exit 1
fi
if [[ -z "$APT_SIGNING_PASSPHRASE" ]]; then
  echo "APT_SIGNING_PASSPHRASE must not be empty" >&2
  exit 1
fi
if [[ ! -d "$debs" ]]; then
  echo "DEB_DIRECTORY is missing: $debs" >&2
  exit 1
fi
if [[ -e "$out" ]]; then
  echo "OUTPUT_DIRECTORY already exists: $out" >&2
  exit 1
fi

work=$(mktemp -d)
gnupg_home="$work/gnupg"
install -d -m 0700 "$gnupg_home"
trap 'gpgconf --homedir "$gnupg_home" --kill gpg-agent >/dev/null 2>&1 || true; rm -rf -- "$work"' EXIT
export GNUPGHOME="$gnupg_home"

printf '%s' "$APT_SIGNING_KEY" | gpg --batch --quiet --import
fingerprint=$(gpg --batch --with-colons --list-secret-keys |
  awk -F: '$1 == "sec" { secret = 1; next } secret && $1 == "fpr" { print toupper($10); exit }')
if [[ "$fingerprint" != "${APT_SIGNING_FINGERPRINT^^}" ]]; then
  echo "Imported signing-key fingerprint does not match APT_SIGNING_FINGERPRINT" >&2
  exit 1
fi

shopt -s nullglob
packages=("$debs"/*.deb)
if (( ${#packages[@]} == 0 )); then
  echo "No .deb files found in $debs" >&2
  exit 1
fi

mkdir -p "$out/dists/$suite/main/binary-amd64" "$out/pool/$suite"
for package in "${packages[@]}"; do
  architecture=$(dpkg-deb -f "$package" Architecture)
  if [[ "$architecture" != amd64 ]]; then
    echo "Unexpected package architecture in $package: $architecture" >&2
    exit 1
  fi
  install -m 0644 -- "$package" "$out/pool/$suite/"
done
gpg --batch --yes --export "$fingerprint" > "$out/boglietti-apt.gpg"

(
  cd "$out"
  apt-ftparchive packages "pool/$suite" > "dists/$suite/main/binary-amd64/Packages"
  gzip -9n < "dists/$suite/main/binary-amd64/Packages" > "dists/$suite/main/binary-amd64/Packages.gz"
)

release_content=$(apt-ftparchive \
  -o "APT::FTPArchive::Release::Origin=boglietti.ovh" \
  -o "APT::FTPArchive::Release::Label=boglietti.ovh" \
  -o "APT::FTPArchive::Release::Suite=$suite" \
  -o "APT::FTPArchive::Release::Codename=$suite" \
  -o "APT::FTPArchive::Release::Components=main" \
  -o "APT::FTPArchive::Release::Architectures=amd64" \
  -o "APT::FTPArchive::Release::ValidTime=2592000" \
  release "$out/dists/$suite")
printf '%s\n' "$release_content" > "$out/dists/$suite/Release"

sign() {
  printf '%s' "$APT_SIGNING_PASSPHRASE" | gpg --batch --yes \
    --pinentry-mode loopback --passphrase-fd 0 --local-user "$fingerprint" "$@"
}
sign --clearsign --output "$out/dists/$suite/InRelease" "$out/dists/$suite/Release"
sign --armor --detach-sign --output "$out/dists/$suite/Release.gpg" "$out/dists/$suite/Release"
gpg --batch --quiet --verify "$out/dists/$suite/InRelease"

printf 'APT repository built: suite=%s packages=%s fingerprint=%s\n' \
  "$suite" "${#packages[@]}" "$fingerprint"
