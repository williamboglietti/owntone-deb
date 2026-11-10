#!/usr/bin/env bash
# Check SFTP deployment command ordering and host-key pinning without network access.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/bin" "$work/repo/pool" "$work/repo/dists"
for suite in noble resolute trixie; do
  mkdir -p "$work/repo/pool/$suite" "$work/repo/dists/$suite"
  touch "$work/repo/dists/$suite/InRelease"
done
touch "$work/repo/boglietti-apt.gpg"
cat > "$work/bin/lftp" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
[[ $1 == -f ]]
cp "$2" "$CAPTURE"
SCRIPT
chmod +x "$work/bin/lftp"
export PATH="$work/bin:$PATH" CAPTURE="$work/commands"
export APT_SFTP_HOST=apt-test.example APT_SFTP_USER=test APT_SFTP_PASSWORD=test-password
export APT_SFTP_KNOWN_HOSTS='apt-test.example ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIE5vdEFQcm9kdWN0aW9uS2V5'
bash "$root/build/deploy-apt-repo.sh" "$work/repo" >/dev/null
pool_line=$(grep -n 'mirror.*repo/pool' "$CAPTURE" | cut -d: -f1)
index_line=$(grep -n 'mirror.*repo/dists/noble' "$CAPTURE" | cut -d: -f1)
release_line=$(grep -n 'mv .*noble/InRelease.tmp' "$CAPTURE" | cut -d: -f1)
(( pool_line < index_line && index_line < release_line ))
grep -q 'StrictHostKeyChecking=yes' "$CAPTURE"
for suite in noble resolute trixie; do
  grep -q "mv .*dists/$suite/InRelease.tmp" "$CAPTURE"
done
export APT_SFTP_KNOWN_HOSTS='other.example ssh-ed25519 AAAA'
if bash "$root/build/deploy-apt-repo.sh" "$work/repo" >/dev/null 2>&1; then
  echo 'Unpinned SFTP host was accepted' >&2
  exit 1
fi
echo 'SFTP host pin and deployment ordering verified with a mock client'
