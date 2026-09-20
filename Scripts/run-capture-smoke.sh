#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/.build-classifier-smoke"
mkdir -p "$OUT"
cd "$ROOT"
swiftc -module-cache-path "$OUT/module-cache" -o "$OUT/capture-smoke" \
  SilentVoice/Classifier/MouthSample.swift \
  SilentVoice/Camera/MouthFeaturePipeline.swift \
  SilentVoice/Camera/CaptureArchive.swift \
  Scripts/CaptureSmokeMain.swift
"$OUT/capture-smoke"
