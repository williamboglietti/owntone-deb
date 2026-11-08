#!/usr/bin/env bash
# À lancer DANS le conteneur de build (voir build.sh) : compile OwnTone avec un jeu
# d'instructions x86-64 de base, vérifie qu'aucun SSE4/AVX n'est entré dans les binaires,
# puis écrit le .deb et son sha256 dans /out.
set -euo pipefail

cd /src
# shellcheck source=../versions.env
. ./versions.env
export DEBIAN_FRONTEND=noninteractive

apt-get update -qq
apt-get install -y -qq --no-install-recommends ca-certificates curl xz-utils binutils dpkg-dev \
  build-essential autotools-dev autoconf automake libtool gettext gawk gperf bison flex \
  libconfuse-dev libunistring-dev libsqlite3-dev libavcodec-dev libavformat-dev \
  libavfilter-dev libswscale-dev libavutil-dev libasound2-dev libxml2-dev libgcrypt20-dev \
  libavahi-client-dev zlib1g-dev libevent-dev libplist-dev libsodium-dev libjson-c-dev \
  libwebsockets-dev libcurl4-openssl-dev libprotobuf-c-dev >/dev/null

work="$(mktemp -d)"
archive="$work/owntone-$OWNTONE_VERSION.tar.xz"
curl -fsSL -o "$archive" \
  "https://github.com/owntone/owntone-server/releases/download/$OWNTONE_VERSION/owntone-$OWNTONE_VERSION.tar.xz"
echo "$OWNTONE_SHA256  $archive" | sha256sum -c -
tar -xf "$archive" -C "$work"

# Compiler pour l'ensemble d'instructions x86-64 de base, indépendamment du processeur du runner.
architecture=$(dpkg --print-architecture)
codename=${TARGET_CODENAME:-noble}
case "$architecture" in
  amd64) export CFLAGS="-O2 -g0 -march=x86-64 -mtune=generic" ;;
  arm64) export CFLAGS="-O2 -g0" ;;
  *) echo "Unsupported architecture: $architecture" >&2; exit 1 ;;
esac
[[ "$codename" =~ ^[a-z0-9]+$ ]] || { echo "Invalid target codename" >&2; exit 1; }
pkg="$work/pkg"
cd "$work/owntone-$OWNTONE_VERSION"
# Sans --enable-install-user : le compte est créé par le postinst, pas dans le conteneur.
./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var >/dev/null
make -j"$(nproc)"
make install DESTDIR="$pkg"

# Le paquet fournit un exemple de configuration ; l'administrateur fournit sa configuration active.
install -d "$pkg/usr/share/doc/owntone"
mv "$pkg/etc/owntone.conf" "$pkg/usr/share/doc/owntone/owntone.conf.example"
rm -rf "$pkg/var/run" "$pkg/var/log"
# Un fichier sous /etc serait un conffile ; les unités d'un paquet vont dans /usr/lib.
install -d "$pkg/usr/lib/systemd/system"
mv "$pkg"/etc/systemd/system/owntone*.service "$pkg/usr/lib/systemd/system/"
rm -rf "$pkg/etc/systemd"
rmdir "$pkg/etc"

if [[ "$architecture" == amd64 ]]; then
  /src/build/check-baseline.sh "$pkg"
fi

# Dépendances d'exécution relevées sur les binaires réellement liés.
mkdir -p "$work/debian"
printf 'Source: owntone\n\nPackage: owntone\nArchitecture: %s\n' "$architecture" > "$work/debian/control"
cd "$work"
elfs=()
while IFS= read -r f; do
  if file_type="$(head -c 4 "$f" | od -An -c | tr -d ' ')" && [ "$file_type" = '177ELF' ]; then elfs+=("-e$f"); fi
done < <(find "$pkg" -type f \( -perm -u+x -o -name '*.so*' \))
depends="$(dpkg-shlibdeps -O --ignore-missing-info "${elfs[@]}" 2>/dev/null | sed -n 's/^shlibs:Depends=//p')"
[ -n "$depends" ] || { echo "Aucune dépendance relevée : abandon." >&2; exit 1; }

version="$OWNTONE_VERSION-${DEB_REVISION}${codename}1"
install -d "$pkg/DEBIAN"
cat > "$pkg/DEBIAN/control" <<CONTROL
Package: owntone
Version: $version
Section: sound
Priority: optional
Architecture: $architecture
Maintainer: BOGLIETTI <security@boglietti.org>
Depends: $depends
Description: OwnTone $OWNTONE_VERSION, serveur audio DAAP/AirPlay
 Paquet $architecture pour $codename.
 Le paquet fournit un exemple de configuration dans /usr/share/doc/owntone.
CONTROL
install -m 0755 /src/build/postinst "$pkg/DEBIAN/postinst"

install -d /out
deb="/out/owntone_${version}_${architecture}.deb"
dpkg-deb --root-owner-group --build "$pkg" "$deb" >/dev/null
(cd /out && sha256sum "$(basename "$deb")" > "$(basename "$deb").sha256")
dpkg-deb --info "$deb" | sed -n '1,/Description/p'
cat "$deb.sha256"
