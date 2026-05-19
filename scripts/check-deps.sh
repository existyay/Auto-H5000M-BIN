#!/usr/bin/env bash
# Quick local dependency audit for the OpenWrt build (WSL/Ubuntu).
set -u

CMDS=(
  git curl wget make sed awk gawk grep find tar xargs file unzip rsync zstd
  gcc g++ cpp ld ar nm strip
  python3 pip3
  autoconf automake libtool patch m4 bison flex pkg-config
  gettext msgfmt
  ccache
  rustc cargo
  go
  luac lua
  perl
  sudo
)

# Apt packages we expect to be installed (-dev headers, etc.).
PKGS=(
  build-essential libncurses5-dev libncursesw5-dev libssl-dev
  libgmp3-dev libmbedtls-dev zlib1g-dev
  libelf-dev
)

echo "=== command -v checks ==="
for c in "${CMDS[@]}"; do
  if command -v "$c" >/dev/null 2>&1; then
    printf '  OK   %-14s -> %s\n' "$c" "$(command -v "$c")"
  else
    printf '  MISS %s\n' "$c"
  fi
done

echo
echo "=== dpkg -s checks ==="
for p in "${PKGS[@]}"; do
  if dpkg -s "$p" >/dev/null 2>&1; then
    printf '  OK   %s\n' "$p"
  else
    printf '  MISS %s\n' "$p"
  fi
done

echo
echo "=== versions ==="
for c in gcc g++ make python3 rustc cargo go perl; do
  if command -v "$c" >/dev/null 2>&1; then
    "$c" --version 2>&1 | head -n1 | sed "s/^/  $c: /"
  fi
done

echo
echo "=== disk ==="
df -h "$(pwd)" | sed 's/^/  /'
