import json
from pathlib import Path
from uuid import uuid4

from PIL import Image
import pytest

from silentvoice.capture import InferenceError, load_archive, parse_manifest, read_frames, resample_indices
from silentvoice.cli import edit_distance, evaluate


def manifest(count=30):
    return {"sampleID": str(uuid4()), "schemaVersion": 2, "frameCount": count,
            "timestamps": [100 + index / 30 for index in range(count)]}


def test_resampling_uses_time_and_preserves_duration():
    assert resample_indices([100 + index / 30 for index in range(300)]) == [round(i * 1.2) for i in range(250)]
    # Dropping a single source frame should not shorten the 25 Hz timeline.
    timestamps = [100 + index / 30 for index in range(30) if index != 10]
    assert len(resample_indices(timestamps)) == 25


@pytest.mark.parametrize("change", [
    {"schemaVersion": 1}, {"frameCount": 301}, {"frameCount": 29},
    {"timestamps": [100.0] * 30}, {"timestamps": [float("nan")] * 30},
    {"timestamps": [100 + i for i in range(30)]},
])
def test_invalid_manifests(change):
    with pytest.raises(InferenceError):
        parse_manifest(json.dumps(manifest() | change))


def test_decode_requires_png_and_expected_size(tmp_path):
    path = tmp_path / "face.png"
    Image.new("RGB", (256, 256)).save(path)
    assert read_frames([path]).shape == (1, 256, 256, 3)
    Image.new("RGB", (192, 192)).save(path)
    with pytest.raises(InferenceError):
        read_frames([path])
    path.write_bytes(b"invalid png")
    with pytest.raises(InferenceError):
        read_frames([path])


def test_old_archive_has_actionable_error(tmp_path):
    (tmp_path / "metadata.json").write_text(json.dumps({"schemaVersion": 1, "frameCount": 30}))
    with pytest.raises(InferenceError, match="Re-record"):
        load_archive(tmp_path)


def test_word_error_distance():
    assert edit_distance(["i", "need", "water"], ["i", "want", "water", "please"]) == 2
    assert edit_distance(["help"], []) == 1


def test_evaluation_keeps_failures_in_accuracy_denominator(tmp_path, monkeypatch):
    monkeypatch.setattr("silentvoice.cli.load_archive", lambda path: (path.name, []))
    class Engine:
        device = "cpu"
        model_version = "fake"
        def transcribe(self, name, paths):
            if name == "bad":
                raise InferenceError("alignment_failed", "bad")
            return "I need water" if name == "good" else "help"
    dataset = tmp_path / "evaluation.jsonl"
    entries = [
        {"capture": "good", "reference": "I need water.", "session": "one"},
        {"capture": "bad", "reference": "I need water.", "session": "two"},
        {"capture": "rest", "reference": "", "session": "two"},
    ]
    dataset.write_text("\n".join(json.dumps(entry) for entry in entries))
    report = evaluate(Engine(), dataset)
    assert report["wordErrorRate"] == 0.5
    assert report["sentenceExactMatchRate"] == 0.5
    assert report["restFalseTranscriptRate"] == 1
    assert report["failureCount"] == 1
    assert report["clips"][0]["rawTranscript"] == "I need water"
