"""Shared wire/archive validation and timestamp resampling."""
from __future__ import annotations

import bisect
import json
import math
from pathlib import Path
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, ValidationError, model_validator

MAX_BYTES = 100 * 1024 * 1024
MAX_FRAMES = 300


class InferenceError(Exception):
    def __init__(self, code: str, message: str, status: int = 422):
        super().__init__(message)
        self.code, self.message, self.status = code, message, status


class ClipManifest(BaseModel):
    model_config = ConfigDict(extra="forbid", allow_inf_nan=False)
    sampleID: UUID
    schemaVersion: int = Field(strict=True)
    frameCount: int = Field(strict=True, ge=15, le=MAX_FRAMES)
    timestamps: list[float] = Field(min_length=15, max_length=MAX_FRAMES)

    @model_validator(mode="after")
    def validate_clip(self):
        if self.schemaVersion != 2:
            raise ValueError("Face images require schema v2; re-record this clip.")
        if len(self.timestamps) != self.frameCount:
            raise ValueError("Frame count and timestamps disagree.")
        if any(b <= a or b - a > 0.201 for a, b in zip(self.timestamps, self.timestamps[1:])):
            raise ValueError("Timestamps must increase without gaps over 200 ms.")
        duration = self.timestamps[-1] - self.timestamps[0]
        if not 0.45 <= duration <= 10:
            raise ValueError("Record between half a second and ten seconds.")
        return self


def parse_manifest(data: str | bytes) -> ClipManifest:
    try:
        return ClipManifest.model_validate_json(data)
    except ValidationError as error:
        raise InferenceError("invalid_capture", "Invalid recording manifest: " + str(error)) from error


def load_archive(path: Path) -> tuple[ClipManifest, list[Path]]:
    try:
        metadata = json.loads((path / "metadata.json").read_text())
        count = metadata["frameCount"]
        if metadata.get("schemaVersion") != 2:
            raise InferenceError("invalid_capture", "Schema-v1 recordings only support commands. Re-record with face images.")
        if not metadata.get("valid") or not isinstance(count, int) or not 15 <= count <= MAX_FRAMES:
            raise InferenceError("invalid_capture", "Recording is invalid or incomplete.")
        if metadata.get("faceFrameCount") != count:
            raise InferenceError("invalid_capture", "Recording is missing face images.")
        frames, timestamps = [], []
        for index in range(count):
            folder = path / f"{index:06d}"
            frame = json.loads((folder / "frame.json").read_text())
            if frame["index"] != index or frame.get("faceWidth") != 256 or frame.get("faceHeight") != 256:
                raise InferenceError("invalid_capture", "Invalid face frame metadata.")
            timestamps.append(frame["timestamp"])
            image = folder / "face.png"
            if not image.is_file():
                raise InferenceError("invalid_capture", "Recording is missing face images.")
            frames.append(image)
        manifest = parse_manifest(json.dumps({"sampleID": metadata["sampleID"], "schemaVersion": 2,
                                               "frameCount": count, "timestamps": timestamps}))
        return manifest, frames
    except (OSError, ValueError, KeyError, TypeError) as error:
        raise InferenceError("invalid_capture", "Cannot read finalized capture: " + str(error)) from error


def resample_indices(timestamps: list[float], fps: int = 25) -> list[int]:
    """Nearest real frame on a 25 Hz timeline, using time rather than frame count."""
    start, end = timestamps[0], timestamps[-1]
    count = math.floor((end - start) * fps + 1e-6) + 1
    indices = []
    for offset in range(count):
        target = start + offset / fps
        right = min(bisect.bisect_left(timestamps, target), len(timestamps) - 1)
        left = max(0, right - 1)
        indices.append(left if abs(timestamps[left] - target) <= abs(timestamps[right] - target) else right)
    return indices


def read_frames(paths: list[Path]):
    import numpy as np
    from PIL import Image, UnidentifiedImageError
    frames = []
    try:
        for path in paths:
            with Image.open(path) as image:
                if image.format != "PNG" or image.size != (256, 256):
                    raise InferenceError("invalid_capture", "Each face frame must be a 256×256 PNG.")
                frames.append(np.asarray(image.convert("RGB")))
    except (OSError, ValueError, UnidentifiedImageError) as error:
        raise InferenceError("invalid_capture", "Could not decode a face PNG.") from error
    return np.stack(frames)
