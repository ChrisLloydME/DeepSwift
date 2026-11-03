#!/bin/zsh
#
# Download an official, self-contained Node.js distribution into .local/node
# for packaging. This never touches a system Node.js, global npm, or PATH.
#
# Usage: Scripts/prepare-node-runtime.sh [--force]
#
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/.local/node"
VERSION="${DEEPSWIFT_NODE_VERSION:-26.13.0}"
ARCH="${DEEPSWIFT_NODE_ARCH:-arm64}"
FORCE="${1:-}"

if [[ -x "$DEST/bin/node" && "$FORCE" != "--force" ]]; then
  "$DEST/bin/node" -v
  echo "Using existing $DEST"
  exit 0
fi

case "$ARCH" in
  arm64|x64) ;;
  *) echo "unsupported DEEPSWIFT_NODE_ARCH: $ARCH" >&2; exit 2 ;;
esac

NAME="node-v${VERSION}-darwin-${ARCH}"
BASE="https://nodejs.org/dist/v${VERSION}"
TMP="$DEST/.download"
mkdir -p "$DEST"
rm -rf "$TMP"
mkdir -p "$TMP"

curl -fsSL "$BASE/$NAME.tar.gz" -o "$TMP/$NAME.tar.gz"
curl -fsSL "$BASE/SHASUMS256.txt" -o "$TMP/SHASUMS256.txt"
EXPECTED="$(awk -v file="$NAME.tar.gz" '$2 == file { print $1 }' "$TMP/SHASUMS256.txt")"
ACTUAL="$(shasum -a 256 "$TMP/$NAME.tar.gz" | awk '{ print $1 }')"
if [[ -z "$EXPECTED" || "$EXPECTED" != "$ACTUAL" ]]; then
  echo "Node.js checksum verification failed" >&2
  rm -rf "$TMP"
  exit 2
fi

rm -rf "$DEST/bin" "$DEST/include" "$DEST/lib" "$DEST/share" "$DEST/LICENSE" "$DEST/CHANGELOG.md" "$DEST/README.md"
tar -xzf "$TMP/$NAME.tar.gz" -C "$DEST" --strip-components=1
rm -rf "$TMP"
"$DEST/bin/node" -v
echo "Node.js ${VERSION} (${ARCH}) prepared at $DEST"
