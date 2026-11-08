#!/usr/bin/env bash
# Dans un Ubuntu 24.04 neuf avec le .deb dans /dist : installation, compte, dossiers,
# unité systemd, absence de /etc/owntone.conf, bibliothèques résolues, réinstallation, purge.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
architecture=$(dpkg --print-architecture)
shopt -s nullglob
packages=(/dist/owntone_*_"$architecture".deb)
(( ${#packages[@]} == 1 )) || { echo "Expected one $architecture package" >&2; exit 1; }
deb=${packages[0]}
apt-get update -qq
apt-get install -y -qq --no-install-recommends "$deb" >/dev/null
/usr/sbin/owntone --version
getent passwd owntone >/dev/null && id -nG owntone | grep -qw audio
[ "$(stat -c %U /var/cache/owntone)" = owntone ]
[ ! -e /etc/owntone.conf ]
dpkg -L owntone | grep -q '^/usr/lib/systemd/system/owntone.service$'
! ldd /usr/sbin/owntone | grep -q 'not found'
apt-get install -y -qq --reinstall "$deb" >/dev/null
dpkg --purge owntone >/dev/null
echo "install-test : ok"
