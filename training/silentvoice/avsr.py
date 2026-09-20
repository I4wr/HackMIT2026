"""Pinned Auto-AVSR full decoder adapter; no training or command vocabulary."""
from __future__ import annotations

import argparse
import logging
import os
from pathlib import Path
import subprocess
import sys

from .capture import ClipManifest, InferenceError, read_frames, resample_indices

UPSTREAM_REVISION = "182b62837773ab01052d4ac21ef1d2203ea7d267"
DEFAULT_CHECKPOINT = "vsr_trlrs2lrs3vox2avsp_base.pth"
log = logging.getLogger(__name__)


class AutoAVSR:
    def __init__(self, repo: Path, checkpoint: Path, device: str = "auto"):
        repo, checkpoint = repo.expanduser().resolve(), checkpoint.expanduser().resolve()
        revision = subprocess.check_output(["git", "-C", str(repo), "rev-parse", "HEAD"], text=True).strip()
        if revision != UPSTREAM_REVISION:
            raise ValueError(f"auto_avsr must be checked out at {UPSTREAM_REVISION}")
        if not checkpoint.is_file():
            raise ValueError(f"Checkpoint not found: {checkpoint}")
        sys.path.insert(0, str(repo))
        # This must be set before importing torch; e.g. max_pool3d in the frontend
        # has no native MPS implementation in the pinned PyTorch release.
        os.environ.setdefault("PYTORCH_ENABLE_MPS_FALLBACK", "1")
        import torch
        from lightning import ModelModule, get_beam_search_decoder
        from datamodule.transforms import VideoTransform
        from preparation.detectors.mediapipe.detector import LandmarksDetector
        from preparation.detectors.mediapipe.video_process import VideoProcess

        self.torch = torch
        self.module = ModelModule(argparse.Namespace(modality="video"))
        self.module.model.load_state_dict(torch.load(checkpoint, map_location="cpu", weights_only=True), strict=True)
        self.module.eval().requires_grad_(False)
        self.beam = get_beam_search_decoder(self.module.model, self.module.token_list)
        self.detector = LandmarksDetector()
        self.video_process = VideoProcess(convert_gray=False)
        self.transform = VideoTransform(subset="test")
        self.model_version = f"{checkpoint.stem}@{revision[:12]}"
        if device not in {"auto", "mps", "cpu"}:
            raise ValueError("Device must be auto, mps, or cpu.")
        self.device = "mps" if device != "cpu" and torch.backends.mps.is_available() else "cpu"
        try:
            self._move(self.device)
            self._decode(torch.zeros(25, 1, 88, 88))
        except (RuntimeError, NotImplementedError):
            if self.device == "cpu":
                raise
            log.warning("MPS warm-up failed; using CPU", exc_info=True)
            self._move("cpu")
            self._decode(torch.zeros(25, 1, 88, 88))

    @classmethod
    def from_environment(cls):
        repo = os.environ.get("SILENTVOICE_AUTO_AVSR")
        checkpoint = os.environ.get("SILENTVOICE_CHECKPOINT")
        if not repo or not checkpoint:
            raise ValueError("Set SILENTVOICE_AUTO_AVSR and SILENTVOICE_CHECKPOINT before starting the server.")
        return cls(Path(repo), Path(checkpoint), os.environ.get("SILENTVOICE_DEVICE", "auto"))

    def _move(self, device):
        self.device = device
        self.module.to(device)
        self.beam.to(device)

    def _decode(self, video):
        torch = self.torch
        with torch.inference_mode():
            model = self.module.model
            x = model.proj_encoder(model.frontend(video.to(self.device).unsqueeze(0)))
            encoded, _ = model.encoder(x, None)
            hypotheses = self.beam(encoded.squeeze(0))
            if not hypotheses:
                return ""
            tokens = hypotheses[0].yseq[1:].detach().cpu()
            return self.module.text_transform.post_process(tokens).replace("<eos>", "").strip()

    def preprocess(self, manifest: ClipManifest, paths: list[Path], preview: Path | None = None):
        frames = read_frames(paths)[resample_indices(manifest.timestamps)]
        try:
            landmarks = self.detector(frames)
            # Reject mostly missing faces rather than extrapolating an entire sentence.
            if sum(item is not None for item in landmarks) < 0.8 * len(frames):
                raise InferenceError("alignment_failed", "Keep your whole face visible and face the camera.")
            patches = self.video_process(frames, landmarks)
            if patches is None or patches.shape[1:3] != (96, 96):
                raise InferenceError("alignment_failed", "Could not align the mouth images. Please record again.")
        except (AssertionError, ValueError, OverflowError, IndexError) as error:
            raise InferenceError("alignment_failed", "Could not align the face images. Please record again.") from error
        video = self.torch.from_numpy(patches).permute(0, 3, 1, 2)
        transformed = self.transform(video)
        if preview is not None:
            from PIL import Image
            preview.mkdir(parents=True, exist_ok=True)
            for index, patch in enumerate(patches):
                Image.fromarray(patch[4:92, 4:92]).save(preview / f"{index:06d}.png")
        return transformed

    def transcribe(self, manifest: ClipManifest, paths: list[Path], preview: Path | None = None) -> str:
        video = self.preprocess(manifest, paths, preview)
        try:
            text = self._decode(video)
        except (RuntimeError, NotImplementedError):
            if self.device == "cpu":
                raise
            log.warning("MPS decoding failed; retrying on CPU", exc_info=True)
            self._move("cpu")
            text = self._decode(video)
        if not text:
            raise InferenceError("empty_transcript", "No sentence was decoded. Please record again.")
        return text
