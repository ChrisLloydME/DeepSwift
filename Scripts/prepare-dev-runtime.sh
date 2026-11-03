#!/bin/bash
# Prepare the isolated, project-local DSH development runtime.
#
# This script never changes a global npm installation, global npm config,
# or the user's existing DSH home. All packages, caches, and profiles live
# under .local/ and the runtime receives an explicit isolated DSH_HOME.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PINNED="$ROOT/Bridge/pinned-runtime.json"
VERSION="$(node -e "process.stdout.write(require(process.argv[1]).version)" "$PINNED")"
PROFILE="$(node -e "process.stdout.write(require(process.argv[1]).profile)" "$PINNED")"
NODE_BIN="${NODE_BIN:-$(command -v node || true)}"

if [ -z "$NODE_BIN" ]; then
    echo "error: Node.js was not found. Install Node 24.9 or later." >&2
    exit 1
fi

"$NODE_BIN" -e '
const [major, minor] = process.versions.node.split(".").map(Number)
if (major < 24 || (major === 24 && minor < 9)) {
  console.error(`error: Node ${process.versions.node} is too old; DSH requires >=24.9.0`)
  process.exit(1)
}
'

RUNTIME="${DEEPSWIFT_RUNTIME_DIR:-$ROOT/.local/runtime/bridge}"
CACHE="$ROOT/.local/cache/npm"
PROFILES="$ROOT/.local/profiles"
WORKSPACES="$ROOT/.local/workspaces"
mkdir -p "$RUNTIME" "$CACHE" "$PROFILES" "$WORKSPACES"

cat > "$RUNTIME/package.json" <<JSON
{
  "name": "deepswift-dev-runtime",
  "private": true,
  "type": "module",
  "version": "0.0.0",
  "description": "Isolated official DSH runtime for DeepSwift development",
  "dependencies": {
    "@deepseek-ai/dsh": "$VERSION"
  },
  "allowScripts": {
    "@deepseek-ai/dsh-subprocess-local": true,
    "koffi": true,
    "node-pty": true,
    "protobufjs": true,
    "@google/genai": true
  }
}
JSON

export npm_config_cache="$CACHE"
export npm_config_userconfig="$ROOT/.local/cache/npmrc"
export npm_config_logs_dir="$ROOT/.local/cache/logs"
export npm_config_update_notifier=false
export npm_config_fund=false
export npm_config_audit=false

echo "Installing @deepseek-ai/dsh@$VERSION into $RUNTIME (isolated cache: $CACHE)"
(
    cd "$RUNTIME"
    npm install --no-audit --no-fund --save-exact "@deepseek-ai/dsh@$VERSION"
)

INSTALLED="$("$NODE_BIN" -e "process.stdout.write(require('$RUNTIME/node_modules/@deepseek-ai/dsh/package.json').version)")"
if [ "$INSTALLED" != "$VERSION" ]; then
    echo "error: installed DSH $INSTALLED does not match pinned $VERSION" >&2
    exit 1
fi

echo "DSH $VERSION prepared."
echo "Host binary: $RUNTIME/node_modules/@deepseek-ai/dsh/lib/bin.js"
echo "Profile template: $PROFILE"
echo "Set DEEPSWIFT_DSH_HOME=$PROFILES/dev to use a dedicated development profile."
