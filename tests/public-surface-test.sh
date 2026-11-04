#!/usr/bin/env bash
# Fail if public docs or Debian metadata reintroduce internal deployment details.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
if git -C "$root" grep -n -i -E 'ansible-infra|tosh|e1-1200|zorin|ci-runner|workstation_|williamboglietti/init-pxe|security@twtcloud.org' -- . ':!tests/public-surface-test.sh'; then
  echo "Internal deployment detail found in tracked public source" >&2
  exit 1
fi
for file in README.md build/build-deb.sh build/check-baseline.sh versions.env; do
  if grep -Eiq 'ansible|tosh|e1-1200|zorin|ci-runner|workstation|thewebtouch|twt' "$root/$file"; then
    echo "Internal deployment detail found in $file" >&2
    exit 1
  fi
done

shopt -s nullglob
packages=("$root"/dist/*.deb)
if (( ${#packages[@]} != 1 )); then
  echo "Expected exactly one .deb in dist/" >&2
  exit 1
fi
maintainer=$(dpkg-deb -f "${packages[0]}" Maintainer)
if [[ "$maintainer" != "BOGLIETTI <security@boglietti.org>" ]]; then
  echo "Unexpected public Maintainer field: $maintainer" >&2
  exit 1
fi
description=$(dpkg-deb -f "${packages[0]}" Description)
if grep -Eiq 'ansible|tosh|e1-1200|zorin|ci-runner|workstation|thewebtouch|twt' <<<"$description"; then
  echo "Internal deployment detail found in Debian package Description" >&2
  exit 1
fi
echo "Public source and package metadata contain no internal deployment details"
