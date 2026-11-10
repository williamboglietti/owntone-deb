#!/usr/bin/env bash
# Build a throwaway APT repository and verify it with APT using only a temporary key.
set -euo pipefail
export LC_ALL=C

root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
server_pid=''
cleanup() {
  if [[ -n "$server_pid" ]]; then
    kill "$server_pid" >/dev/null 2>&1 || true
  fi
  rm -rf -- "$work"
}
trap cleanup EXIT

for suite in noble resolute trixie; do
  for architecture in amd64 arm64; do
    package_root="$work/package-$suite-$architecture"
    mkdir -p "$package_root/DEBIAN" "$work/debs/$suite/$architecture"
    cat > "$package_root/DEBIAN/control" <<CONTROL
Package: owntone
Version: 0.0.1-1${suite}1
Section: sound
Priority: optional
Architecture: $architecture
Maintainer: BOGLIETTI <security@boglietti.org>
Description: Test package for signed APT repository verification
CONTROL
    dpkg-deb --root-owner-group --build "$package_root" "$work/debs/$suite/$architecture/owntone_0.0.1-1${suite}1_${architecture}.deb" >/dev/null
  done
done

test_key_home="$work/test-key"
install -d -m 0700 "$test_key_home"
GNUPGHOME="$test_key_home" gpg --batch --pinentry-mode loopback --passphrase test-passphrase \
  --quick-gen-key "APT test signing <apt-test@example.invalid>" ed25519 cert 1d >/dev/null 2>&1
fingerprint=$(GNUPGHOME="$test_key_home" gpg --batch --with-colons --list-secret-keys |
  awk -F: '$1 == "sec" { secret = 1; next } secret && $1 == "fpr" { print toupper($10); exit }')
GNUPGHOME="$test_key_home" gpg --batch --pinentry-mode loopback --passphrase test-passphrase \
  --quick-add-key "$fingerprint" ed25519 sign 1d >/dev/null 2>&1
APT_SIGNING_KEY=$(GNUPGHOME="$test_key_home" gpg --batch --pinentry-mode loopback \
  --passphrase test-passphrase --armor --export-secret-subkeys "$fingerprint")
export APT_SIGNING_KEY APT_SIGNING_FINGERPRINT="$fingerprint" APT_SIGNING_PASSPHRASE=test-passphrase

repo="$work/repo"
bash "$root/build/make-apt-repo.sh" "$work/debs" "$repo"
gpgv --keyring "$repo/boglietti-apt.gpg" "$repo/dists/noble/InRelease" >/dev/null
grep -q 'Components: main' "$repo/dists/noble/Release"
for suite in noble resolute trixie; do
  gpgv --keyring "$repo/boglietti-apt.gpg" "$repo/dists/$suite/InRelease" >/dev/null
  for architecture in amd64 arm64; do
    grep -q 'owntone' "$repo/dists/$suite/main/binary-$architecture/Packages"
    grep -q "Architecture: $architecture" "$repo/dists/$suite/main/binary-$architecture/Packages"
  done
done

port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')
(
  cd "$repo"
  exec python3 -m http.server "$port" --bind 127.0.0.1
) >"$work/http.log" 2>&1 &
server_pid=$!
sleep 1
for suite in noble resolute trixie; do
  for architecture in amd64 arm64; do
    APT_VERIFY_PROTO=http bash "$root/build/verify-apt-repo.sh" "http://127.0.0.1:$port" "$suite" "$repo" "$architecture"
  done
done

mkdir -p "$work/apt/lists/partial" "$work/apt/cache/archives/partial" "$work/download"
cp "$repo/boglietti-apt.gpg" "$work/apt/keyring.gpg"
printf 'deb [signed-by=%s] http://127.0.0.1:%s noble main\n' \
  "$work/apt/keyring.gpg" "$port" > "$work/apt/sources.list"
apt_options=(
  -o "Dir::Etc::sourcelist=$work/apt/sources.list"
  -o Dir::Etc::sourceparts=/nonexistent
  -o "Dir::State::Lists=$work/apt/lists"
  -o "Dir::Cache=$work/apt/cache"
  -o Debug::NoLocking=1
  -o "APT::Sandbox::User=$(id -un)"
)
apt-get "${apt_options[@]}" update >/dev/null
(
  cd "$work/download"
  apt-get "${apt_options[@]}" download owntone >/dev/null
)
downloaded=$(find "$work/download" -name 'owntone_*.deb' -print -quit)
[[ -n "$downloaded" ]]
cmp -s "$repo/pool/noble/amd64/owntone_0.0.1-1noble1_amd64.deb" "$downloaded"

wrong_home="$work/wrong-key"
install -d -m 0700 "$wrong_home"
GNUPGHOME="$wrong_home" gpg --batch --pinentry-mode loopback --passphrase '' \
  --quick-gen-key "Wrong test key <wrong@example.invalid>" ed25519 sign 1d >/dev/null 2>&1
GNUPGHOME="$wrong_home" gpg --batch --armor --export \
  "$(GNUPGHOME="$wrong_home" gpg --batch --with-colons --list-keys | awk -F: '/^fpr:/ {print $10; exit}')" |
  gpg --batch --yes --dearmor -o "$work/apt/wrong.gpg"
mkdir -p "$work/apt-bad/lists/partial" "$work/apt-bad/cache/archives/partial"
printf 'deb [signed-by=%s] http://127.0.0.1:%s noble main\n' \
  "$work/apt/wrong.gpg" "$port" > "$work/apt-bad/sources.list"
bad_options=(
  -o "Dir::Etc::sourcelist=$work/apt-bad/sources.list"
  -o Dir::Etc::sourceparts=/nonexistent
  -o "Dir::State::Lists=$work/apt-bad/lists"
  -o "Dir::Cache=$work/apt-bad/cache"
  -o Debug::NoLocking=1
  -o "APT::Sandbox::User=$(id -un)"
)
if apt-get "${bad_options[@]}" update >"$work/wrong-key.log" 2>&1; then
  echo "APT accepted the repository with an unrelated key" >&2
  exit 1
fi
echo "signed APT repository, package checksum, and wrong-key rejection verified"
