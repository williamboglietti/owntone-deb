#!/usr/bin/env bash
# Build a standard signed APT repository for OwnTone.
# Usage: bash make-apt-repo.sh DEB_DIRECTORY OUTPUT_DIRECTORY
# Required environment: APT_SIGNING_KEY, APT_SIGNING_PASSPHRASE,
# APT_SIGNING_FINGERPRINT. The private key is read only from the environment.
set -euo pipefail
export LC_ALL=C

debs=$1
out=$2

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
suites=(noble resolute trixie)
architectures=(amd64 arm64)
mkdir -p "$out"
gpg --batch --yes --export "$fingerprint" > "$out/boglietti-apt.gpg"

sign() {
  printf '%s' "$APT_SIGNING_PASSPHRASE" | gpg --batch --yes \
    --pinentry-mode loopback --passphrase-fd 0 --local-user "$fingerprint" "$@"
}

for suite in "${suites[@]}"; do
  for architecture in "${architectures[@]}"; do
    packages=("$debs/$suite/$architecture"/*.deb)
    if (( ${#packages[@]} != 1 )); then
      echo "Expected exactly one package for $suite/$architecture" >&2; exit 1
    fi
    package=${packages[0]}
    [[ $(dpkg-deb -f "$package" Package) == owntone ]] || { echo "Unexpected package" >&2; exit 1; }
    [[ $(dpkg-deb -f "$package" Architecture) == "$architecture" ]] || { echo "Unexpected architecture" >&2; exit 1; }
    version=$(dpkg-deb -f "$package" Version)
    [[ "$version" == *"${suite}"* ]] || { echo "Unexpected distribution in package version" >&2; exit 1; }
    index_dir="$out/dists/$suite/main/binary-$architecture"
    mkdir -p "$index_dir" "$out/pool/$suite/$architecture"
    install -m 0644 -- "$package" "$out/pool/$suite/$architecture/"
    (
      cd "$out"
      apt-ftparchive packages "pool/$suite/$architecture" > "dists/$suite/main/binary-$architecture/Packages"
      gzip -9n < "dists/$suite/main/binary-$architecture/Packages" > "dists/$suite/main/binary-$architecture/Packages.gz"
    )
  done
  apt-ftparchive \
    -o "APT::FTPArchive::Release::Origin=boglietti.ovh" \
    -o "APT::FTPArchive::Release::Label=boglietti.ovh" \
    -o "APT::FTPArchive::Release::Suite=$suite" \
    -o "APT::FTPArchive::Release::Codename=$suite" \
    -o "APT::FTPArchive::Release::Components=main" \
    -o "APT::FTPArchive::Release::Architectures=amd64 arm64" \
    -o "APT::FTPArchive::Release::ValidTime=2592000" \
    release "$out/dists/$suite" > "$out/dists/$suite/Release"
  sign --clearsign --output "$out/dists/$suite/InRelease" "$out/dists/$suite/Release"
  sign --armor --detach-sign --output "$out/dists/$suite/Release.gpg" "$out/dists/$suite/Release"
  gpg --batch --quiet --verify "$out/dists/$suite/InRelease"
done

printf 'APT repository built: suites=%s fingerprint=%s\n' "${suites[*]}" "$fingerprint"
