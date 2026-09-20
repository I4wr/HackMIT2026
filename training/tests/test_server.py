from concurrent.futures import ThreadPoolExecutor
from io import BytesIO
import json
from pathlib import Path
import threading

from fastapi.testclient import TestClient
from PIL import Image
import pytest
import httpx

from silentvoice.capture import InferenceError, MAX_BYTES, read_frames
from silentvoice.server import create_app
from test_capture import manifest


class FakeEngine:
    device = "cpu"
    model_version = "test-model"
    paths = []
    def transcribe(self, metadata, paths):
        self.paths = paths
        read_frames(paths)
        return "I need water"


def payload(metadata=None):
    metadata = metadata or manifest()
    data = BytesIO()
    Image.new("RGB", (256, 256)).save(data, format="PNG")
    files = [("manifest", (None, json.dumps(metadata)))]
    files += [("frames", (f"{i:06d}.png", data.getvalue(), "image/png")) for i in range(metadata["frameCount"])]
    return files


def test_health_transcript_and_upload_cleanup():
    engine = FakeEngine()
    with TestClient(create_app(lambda: engine)) as client:
        assert client.get("/health").json()["ready"]
        metadata = manifest()
        result = client.post("/v1/transcribe", files=payload(metadata))
        assert result.status_code == 200
        assert result.json()["sampleID"] == metadata["sampleID"]
        assert result.json()["transcript"] == "I need water"
        assert all(not path.exists() for path in engine.paths)


def test_unavailable_model():
    def missing():
        raise ValueError("missing checkpoint")
    with TestClient(create_app(missing)) as client:
        assert not client.get("/health").json()["ready"]
        assert client.post("/v1/transcribe", files=payload()).json()["code"] == "model_unavailable"


def test_bad_uploads_and_size_limit():
    with TestClient(create_app(FakeEngine)) as client:
        assert client.post("/v1/transcribe", files=payload()[:-1]).status_code == 422
        assert client.post("/v1/transcribe", files=payload(manifest() | {"schemaVersion": 1})).status_code == 422
        files = payload()
        files[1] = ("frames", ("../../bad.png", b"bad", "image/png"))
        assert client.post("/v1/transcribe", files=files).status_code == 422
        files[1] = ("frames", ("000000.png", b"bad", "image/png"))
        assert client.post("/v1/transcribe", files=files).status_code == 422
        assert client.post("/v1/transcribe", headers={"content-length": str(MAX_BYTES + 1)}).status_code == 413


def test_chunked_upload_cannot_bypass_size_limit(monkeypatch):
    request = httpx.Request("POST", "http://testserver/v1/transcribe", files=payload())
    body = request.read()
    monkeypatch.setattr("silentvoice.server.MAX_BYTES", len(body) - 1)
    with TestClient(create_app(FakeEngine)) as client:
        response = client.post("/v1/transcribe", headers={"content-type": request.headers["content-type"]},
                               content=(body[index:index + 100] for index in range(0, len(body), 100)))
        assert response.status_code == 413
        assert response.json()["code"] == "upload_too_large"


@pytest.mark.parametrize("failure", [InferenceError("alignment_failed", "Try again"), RuntimeError("backend failed")])
def test_failed_requests_release_gate_and_delete_uploads(failure):
    engine = FakeEngine()
    original = engine.transcribe
    def fail(metadata, paths):
        engine.paths = paths
        raise failure
    engine.transcribe = fail
    with TestClient(create_app(lambda: engine)) as client:
        response = client.post("/v1/transcribe", files=payload())
        assert response.status_code in (422, 500)
        assert all(not path.exists() for path in engine.paths)
        engine.transcribe = original
        assert client.post("/v1/transcribe", files=payload()).status_code == 200


def test_concurrent_request_is_busy_while_health_stays_responsive():
    entered, release = threading.Event(), threading.Event()
    class SlowEngine(FakeEngine):
        def transcribe(self, metadata, paths):
            entered.set()
            assert release.wait(5)
            return "hello"
    with TestClient(create_app(SlowEngine)) as client, ThreadPoolExecutor() as pool:
        first = pool.submit(client.post, "/v1/transcribe", files=payload())
        assert entered.wait(5)
        try:
            assert client.get("/health").status_code == 200
            assert client.post("/v1/transcribe", files=payload()).json()["code"] == "busy"
        finally:
            release.set()
        assert first.result().status_code == 200
