"""One-model, one-request local HTTP server with bounded uploads."""
from __future__ import annotations

from contextlib import asynccontextmanager
import logging
from pathlib import Path
import tempfile
import threading
import time

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from starlette.concurrency import run_in_threadpool
from starlette.datastructures import UploadFile
from starlette.formparsers import MultiPartException

from .capture import InferenceError, MAX_BYTES, parse_manifest

log = logging.getLogger(__name__)


class RequestSizeLimit:
    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http":
            return await self.app(scope, receive, send)
        headers = dict(scope["headers"])
        try:
            length = int(headers.get(b"content-length", b"0"))
        except ValueError:
            length = MAX_BYTES + 1
        if length > MAX_BYTES or length < 0:
            return await JSONResponse({"code": "upload_too_large", "message": "Maximum upload is 100 MB."}, 413)(scope, receive, send)
        total = 0

        async def bounded_receive():
            nonlocal total
            message = await receive()
            total += len(message.get("body", b""))
            if total > MAX_BYTES:
                scope.setdefault("state", {})["upload_too_large"] = True
                # The multipart parser closes already-spooled files on this exception.
                raise MultiPartException("Maximum upload is 100 MB.")
            return message

        await self.app(scope, bounded_receive, send)


def create_app(engine_factory=None):
    if engine_factory is None:
        from .avsr import AutoAVSR
        engine_factory = AutoAVSR.from_environment
    gate = threading.Lock()

    @asynccontextmanager
    async def lifespan(app):
        app.state.engine = None
        app.state.error = None
        try:
            app.state.engine = await run_in_threadpool(engine_factory)
        except Exception as error:
            log.exception("Model unavailable")
            app.state.error = str(error)
        yield

    app = FastAPI(title="SilentVoice local transcription", lifespan=lifespan)
    app.add_middleware(RequestSizeLimit)

    @app.exception_handler(InferenceError)
    async def inference_error(request, error):
        return JSONResponse({"code": error.code, "message": error.message}, error.status)

    @app.get("/health")
    async def health():
        engine = app.state.engine
        return {"ready": engine is not None, "modelVersion": engine.model_version if engine else "unavailable",
                "device": engine.device if engine else "none", "error": app.state.error}

    @app.post("/v1/transcribe")
    async def transcribe(request: Request):
        engine = app.state.engine
        if engine is None:
            raise InferenceError("model_unavailable", "The Mac model is unavailable. Check /health and the server console.", 503)
        if not gate.acquire(blocking=False):
            raise InferenceError("busy", "The Mac is transcribing another recording. Please retry shortly.", 503)
        try:
            started = time.perf_counter()
            async with request.form(max_files=300, max_fields=1, max_part_size=64 * 1024) as form:
                metadata = form.get("manifest")
                if not isinstance(metadata, str):
                    raise InferenceError("invalid_capture", "A JSON manifest is required.")
                manifest = parse_manifest(metadata)
                uploads = form.getlist("frames")
                if len(uploads) != manifest.frameCount:
                    raise InferenceError("invalid_capture", "Frame files and manifest count disagree.")
                with tempfile.TemporaryDirectory(prefix="silentvoice-upload-") as temporary:
                    paths = []
                    for index, upload in enumerate(uploads):
                        if not isinstance(upload, UploadFile) or upload.filename != f"{index:06d}.png":
                            raise InferenceError("invalid_capture", "Face PNGs must be in numbered frame order.")
                        content = await upload.read(1024 * 1024 + 1)
                        if not content or len(content) > 1024 * 1024:
                            raise InferenceError("invalid_capture", "A face PNG is empty or exceeds 1 MB.")
                        path = Path(temporary) / f"{index:06d}.png"
                        path.write_bytes(content)
                        paths.append(path)
                    text = await run_in_threadpool(engine.transcribe, manifest, paths)
                if not text.strip():
                    raise InferenceError("empty_transcript", "No sentence was decoded. Please record again.")
                return {"sampleID": str(manifest.sampleID), "transcript": text,
                        "modelVersion": engine.model_version, "processingSeconds": time.perf_counter() - started}
        except InferenceError:
            raise
        except Exception as error:
            from starlette.exceptions import HTTPException
            if getattr(request.state, "upload_too_large", False):
                raise InferenceError("upload_too_large", "Maximum upload is 100 MB.", 413) from error
            if isinstance(error, HTTPException):
                raise InferenceError("invalid_capture", str(error.detail), 400) from error
            log.exception("Transcription failed")
            raise InferenceError("inference_failed", "The Mac could not process this recording. Check the server console and retry.", 500) from error
        finally:
            gate.release()
    return app


app = create_app()
