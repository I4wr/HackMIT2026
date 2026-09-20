# Local inference validation — 2026-09-20

Environment: Apple M3, macOS 26.6.2, Xcode 27.0, Python 3.12.13. Auto-AVSR revision
`182b62837773ab01052d4ac21ef1d2203ea7d267`; checkpoint
`vsr_trlrs2lrs3vox2avsp_base.pth`, MD5 `49f770f2c0d8b8d769347ee47ed1648f`.

## Passed

- iOS simulator build, with local-network usage text and scoped local ATS settings
  confirmed in the generated app Info.plist. No new Swift compiler warnings.
- Capture, classifier, segmentation, and transcription smoke scripts. The existing
  segmentation test now checks alignment bounds against the processed sequence,
  matching the classifier's actual coordinate system.
- 18 Python tests for archive validation, resampling, image validation, evaluation
  accounting, HTTP errors, upload limits including chunked bodies, cleanup, and
  concurrent-request rejection while health remains responsive.
- Swift transcription smoke checks cover edited text spoken verbatim, preserved
  raw output, stale-result suppression, offline retry state, HTTP errors, archive
  packaging, response/sample correlation, and incomplete-archive rejection.
- Opt-in real-model test: checkpoint loaded, MediaPipe aligned a repeated static
  face fixture, and produced 25 finite 88×88 model-input patches and a decoder
  result. Startup took about 11.4 seconds; decoding one second of repeated imagery
  took about 1.3 seconds on CPU. This does not measure recognition accuracy.
- Launch script and actual HTTP server: `/health` returned ready, a multipart
  request returned HTTP 200, and the local round trip took about 1.2 seconds for
  the same static fixture. The temporary validation server was stopped afterward.

## Observed limitations

The pinned PyTorch build lacks native MPS 3D max pooling. Per-operation fallback
gets past it, but upstream CTC beam search encounters mixed MPS/CPU tensors.
Automatic full-CPU fallback works; `SILENTVOICE_DEVICE=cpu` skips the failed Metal
warm-up. These results do not establish latency for ten-second sentences.

The repeated static face returned “AND THEN” despite containing no speech.
Resting-face false positives remain possible. Sentence results always require
review and an explicit Speak tap; this implementation does not claim calibrated
confidence or dependable silence rejection.

`pip check` flags MediaPipe 0.10.21's incorrect internal x86_64 wheel tag on arm64.
The actual universal2 native library imported, detected landmarks, and ran in the
integration tests. The locked environment also emits upstream deprecation warnings.

The original guide's Imperial-hosted checkpoint and demo-video links returned 404.
The checkpoint was obtained from the official repository's Google Drive link;
the upstream spoken demo video could not be tested.

## Requires new physical recordings

No schema-v2 TrueDepth sentence recordings were available. Verify full-face crop
orientation/coverage, capture throughput, stop/ten-second completion, lifecycle
cancellation, local-network prompts, connectivity failures, retry, and offline
commands on a physical iPhone. Collect the 30 sentence clips across two sessions
plus ten resting-face clips described in the setup guide and run the evaluation
CLI. Word error rate, sentence accuracy, and phone-to-Mac latency remain unmeasured.

The downloaded checkout and checkpoint are installed beside the app repository;
the isolated Python environment is in `training/.venv`. Start the server with
`bash Scripts/run-local-inference.sh`.
