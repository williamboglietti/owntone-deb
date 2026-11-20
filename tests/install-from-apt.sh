#!/usr/bin/env bash
# Run inside a disposable native target container against an ephemeral signed feed.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
architecture=$(dpkg --print-architecture)
printf 'deb [signed-by=/test-key.gpg] http://127.0.0.1:8765 %s main\n' "$TARGET" > /etc/apt/sources.list.d/owntone-test.list
apt-get update -qq
apt-get install -y -qq --no-install-recommends owntone >/dev/null
dpkg-query -W -f='${Architecture} ${Version}\n' owntone | grep -q "^$architecture .*${TARGET}"
/usr/sbin/owntone --version
! ldd /usr/sbin/owntone | grep -q 'not found'
dpkg --purge owntone >/dev/null
