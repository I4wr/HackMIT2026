#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AVSR_REPO="${SILENTVOICE_AUTO_AVSR:-$ROOT/../auto_avsr}"
AVSR_CHECKPOINT="${SILENTVOICE_CHECKPOINT:-$ROOT/../vsr_trlrs2lrs3vox2avsp_base.pth}"
if [ ! -x "$ROOT/training/.venv/bin/silentvoice-local" ]; then
  echo "Set up training/.venv first; see docs/LocalInference.md." >&2
  exit 1
fi
exec "$ROOT/training/.venv/bin/silentvoice-local" \
  --auto-avsr "$AVSR_REPO" --checkpoint "$AVSR_CHECKPOINT" \
  --device "${SILENTVOICE_DEVICE:-auto}" serve "$@"
