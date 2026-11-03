#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
NODE_BIN="${NODE_BIN:-$(command -v node)}"
exec "$NODE_BIN" --test Bridge/tests/*.test.mjs
