#!/usr/bin/env bash
# Sync a signed public APT repository over pinned-host SFTP; never delete remote files.
# Usage: bash deploy-apt-repo.sh REPOSITORY_DIRECTORY
# Required environment: APT_SFTP_HOST, APT_SFTP_USER, APT_SFTP_PASSWORD,
# APT_SFTP_KNOWN_HOSTS. No host or credentials are stored in this repository.
set -euo pipefail

repo=$1
for name in APT_SFTP_HOST APT_SFTP_USER APT_SFTP_PASSWORD APT_SFTP_KNOWN_HOSTS; do
  if ! printenv "$name" >/dev/null 2>&1; then
    printf 'Missing required environment variable: %s\n' "$name" >&2
    exit 1
  fi
done
for suite in noble resolute trixie; do
  [[ -f "$repo/dists/$suite/InRelease" && -d "$repo/pool/$suite" ]] || {
    echo "Repository is missing the $suite suite" >&2; exit 1
  }
done

work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
umask 077
known_hosts="$work/known_hosts"
printf '%s\n' "$APT_SFTP_KNOWN_HOSTS" > "$known_hosts"
if ! grep -q "^$APT_SFTP_HOST " "$known_hosts"; then
  echo "APT_SFTP_HOST is not pinned in APT_SFTP_KNOWN_HOSTS" >&2
  exit 1
fi
commands="$work/lftp.cmd"
{
  echo "set cmd:fail-exit yes"
  echo "set net:max-retries 2"
  echo "set net:timeout 30"
  echo "set sftp:connect-program \"ssh -a -x -o StrictHostKeyChecking=yes -o UserKnownHostsFile=$known_hosts\""
  printf '%s\n' "open -u \"$APT_SFTP_USER,$APT_SFTP_PASSWORD\" \"sftp://$APT_SFTP_HOST\""
  # Upload immutable packages and indexes before switching signed releases.
  printf '%s\n' "mirror --reverse --verbose \"$repo/pool\" \"root/apt/pool\""
  printf '%s\n' "put -o \"root/apt/boglietti-apt.gpg.tmp\" \"$repo/boglietti-apt.gpg\""
  printf '%s\n' 'mv root/apt/boglietti-apt.gpg.tmp root/apt/boglietti-apt.gpg'
  for suite in noble resolute trixie; do
    printf '%s\n' "mirror --reverse --verbose --exclude-glob=InRelease --exclude-glob=Release --exclude-glob=Release.gpg \"$repo/dists/$suite\" \"root/apt/dists/$suite\""
    for file in Release Release.gpg InRelease; do
      printf '%s\n' "put -o \"root/apt/dists/$suite/$file.tmp\" \"$repo/dists/$suite/$file\""
      printf '%s\n' "mv \"root/apt/dists/$suite/$file.tmp\" \"root/apt/dists/$suite/$file\""
    done
  done
  printf '%s\n' "bye"
} > "$commands"
lftp -f "$commands"
printf 'Published signed APT repository to root/apt\n'
