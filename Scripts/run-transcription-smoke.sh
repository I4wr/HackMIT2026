#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/.build-classifier-smoke"
mkdir -p "$OUT"
cd "$ROOT"
swiftc -module-cache-path "$OUT/module-cache" -o "$OUT/transcription-smoke" \
  SilentVoice/Classifier/MouthSample.swift \
  SilentVoice/Camera/CaptureArchive.swift \
  SilentVoice/Services/SpeechOutput.swift \
  SilentVoice/Services/TranscriptionService.swift \
  SilentVoice/Services/SentenceRecognition.swift \
  Scripts/TranscriptionSmokeMain.swift
"$OUT/transcription-smoke"
