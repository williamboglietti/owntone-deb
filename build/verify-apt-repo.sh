#!/usr/bin/env bash
# Verify a published public APT feed, compare its files, and download the package through APT.
# Usage: bash verify-apt-repo.sh BASE SUITE REPOSITORY_DIRECTORY
set -euo pipefail

base=$1
suite=$2
repo=$3
architecture=${4:-$(dpkg --print-architecture)}
case "$suite:$architecture" in
  noble:amd64|noble:arm64|resolute:amd64|resolute:arm64|trixie:amd64|trixie:arm64) ;;
  *) echo "Unsupported suite or architecture" >&2; exit 1 ;;
esac
proto=$(printenv APT_VERIFY_PROTO 2>/dev/null || true)
[ -n "$proto" ] || proto=https
[[ "$base" == https://* || "$proto" == http ]] || {
  echo "APT repository verification requires HTTPS" >&2
  exit 1
}
[[ -f "$repo/boglietti-apt.gpg" ]] || {
  echo "public signing key is missing from the local repository" >&2
  exit 1
}

work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
curl_file() {
  local relative=$1
  curl --proto "=$proto" --tlsv1.2 -fsSL --max-time 60 -o "$work/download" "$base/$relative"
}
curl_file boglietti-apt.gpg
cmp -s "$work/download" "$repo/boglietti-apt.gpg" || {
  echo "published public key differs from the local key" >&2
  exit 1
}

(
  cd "$repo"
  find dists pool -type f -print | sort
) | while IFS= read -r relative; do
  curl_file "$relative"
  cmp -s "$work/download" "$repo/$relative" || {
    echo "published file differs from local build: $relative" >&2
    exit 1
  }
done

install -d "$work/apt/lists/partial" "$work/apt/cache/archives/partial" "$work/downloaded-debs"
printf 'deb [arch=%s signed-by=%s] %s %s main\n' "$architecture" "$repo/boglietti-apt.gpg" "$base" "$suite" > "$work/apt/sources.list"
apt_options=(
  -o "Dir::Etc::sourcelist=$work/apt/sources.list"
  -o Dir::Etc::sourceparts=/nonexistent
  -o "Dir::State::Lists=$work/apt/lists"
  -o "Dir::Cache=$work/apt/cache"
  -o "APT::Architecture=$architecture"
  -o "APT::Architectures=$architecture"
  -o Debug::NoLocking=1
  -o "APT::Sandbox::User=$(id -un)"
)
apt-get "${apt_options[@]}" update >/dev/null
(
  cd "$work/downloaded-debs"
  apt-get "${apt_options[@]}" download "owntone:$architecture" >/dev/null
)
local_deb=$(cd "$repo" && find "pool/$suite/$architecture" -name '*.deb' -print -quit)
downloaded_deb=$(find "$work/downloaded-debs" -name 'owntone_*.deb' -print -quit)
[[ -n "$local_deb" && -n "$downloaded_deb" ]] || {
  echo "OwnTone package was not found in the local or published repository" >&2
  exit 1
}
local_sha=$(sha256sum "$repo/$local_deb" | cut -d' ' -f1)
downloaded_sha=$(sha256sum "$downloaded_deb" | cut -d' ' -f1)
[[ "$local_sha" == "$downloaded_sha" ]] || {
  echo "APT-downloaded OwnTone package has a different SHA-256" >&2
  exit 1
}
echo "published key, signed indexes, repository files, and OwnTone package SHA-256 verified"
