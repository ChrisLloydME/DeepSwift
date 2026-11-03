#!/bin/zsh
#
# Copy the pinned DSH runtime, the DeepSwift bridge, and a Node.js executable
# into a built DeepSwift.app. This script intentionally runs after Xcode has
# signed the app so the nested runtime can be signed explicitly.
#
# Usage: Scripts/package-runtime.sh <DeepSwift.app> [runtime-dir]
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:?usage: package-runtime.sh <DeepSwift.app> [runtime-dir]}"
RUNTIME="${2:-$ROOT/.local/runtime/bridge}"
if [[ -n "${DEEPSWIFT_NODE_BIN:-}" ]]; then
  NODE_BIN="$DEEPSWIFT_NODE_BIN"
elif [[ -x "$ROOT/.local/node/bin/node" ]]; then
  NODE_BIN="$ROOT/.local/node/bin/node"
else
  NODE_BIN="$(command -v node || true)"
fi
IDENTITY="${DEEPSWIFT_CODESIGN_IDENTITY:--}"

if [[ ! -d "$APP/Contents" ]]; then
  echo "not an app bundle: $APP" >&2
  exit 2
fi
if [[ ! -f "$RUNTIME/node_modules/@deepseek-ai/dsh/lib/bin.js" ]]; then
  echo "pinned DSH runtime not found under $RUNTIME" >&2
  exit 2
fi
if [[ ! -x "$NODE_BIN" ]]; then
  echo "Node executable not found: $NODE_BIN" >&2
  exit 2
fi

RES="$APP/Contents/Resources"
rm -rf "$RES/DSH" "$RES/Bridge" "$RES/Node"
mkdir -p "$RES/DSH" "$RES/Bridge/src" "$RES/Node/bin"

# Keep the installed package graph intact. The bridge resolves the Host from
# DSH/node_modules; no global Node or DSH installation is consulted.
ditto "$RUNTIME" "$RES/DSH"
ditto "$ROOT/Bridge/src" "$RES/Bridge/src"
# The bridge's package metadata is not needed at runtime, but retaining it
# makes diagnostics and version checks reproducible.
cp "$ROOT/Bridge/package.json" "$RES/Bridge/package.json" 2>/dev/null || true

cp -L "$NODE_BIN" "$RES/Node/bin/node"
chmod 755 "$RES/Node/bin/node"
if ! "$RES/Node/bin/node" -v >/dev/null 2>&1; then
  echo "The supplied Node executable is not self-contained (Homebrew's split libnode build does not qualify)." >&2
  echo "Run Scripts/prepare-node-runtime.sh, or set DEEPSWIFT_NODE_BIN to an official Node.js binary." >&2
  rm -rf "$RES/Node"
  exit 2
fi
NODE_REAL="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$NODE_BIN")"
NODE_PREFIX="$(dirname "$(dirname "$NODE_REAL")")"
if [[ -f "$NODE_PREFIX/LICENSE" ]]; then
  cp "$NODE_PREFIX/LICENSE" "$RES/Node/LICENSE"
fi
if [[ -f "$NODE_PREFIX/CHANGELOG.md" ]]; then
  cp "$NODE_PREFIX/CHANGELOG.md" "$RES/Node/CHANGELOG.md"
fi

cat > "$RES/Node/README.txt" <<'NODE_README'
Node.js is bundled solely to run the pinned official DeepSeek Harness Host.
The matching Node.js license is in LICENSE. DeepSwift does not install or
modify a global Node.js runtime.
NODE_README

# The nested executable must be signed for hardened-runtime execution. When
# no identity is supplied, use an ad-hoc signature for local distribution
# testing only.
codesign --force --options runtime \
  --entitlements "$ROOT/Scripts/node-entitlements.plist" \
  --sign "$IDENTITY" "$RES/Node/bin/node"

if [[ "$IDENTITY" != "-" ]]; then
  codesign --force --options runtime --sign "$IDENTITY" "$APP/Contents/Frameworks/SwiftTerm.framework"
  codesign --force --options runtime --sign "$IDENTITY" "$APP"
fi

echo "Packaged runtime into $APP"
echo "  Node: $(du -sh "$RES/Node" | awk '{print $1}')"
echo "  DSH:  $(du -sh "$RES/DSH" | awk '{print $1}')"
echo "  Bridge: $(du -sh "$RES/Bridge" | awk '{print $1}')"
