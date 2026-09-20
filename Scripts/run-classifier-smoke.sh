#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLASSIFIER="$ROOT/SilentVoice/Classifier"
OUT="$ROOT/.build-classifier-smoke"

mkdir -p "$OUT"
cd "$ROOT"
swiftc -o "$OUT/classifier-smoke" \
  "$CLASSIFIER"/*.swift \
  "$ROOT/Scripts/ClassifierSmokeMain.swift"

"$OUT/classifier-smoke"
