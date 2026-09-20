"""CLI transcription, local serving, and labeled-clip evaluation."""
from __future__ import annotations

import argparse
import json
import logging
import os
from pathlib import Path
import statistics
import time

from .avsr import AutoAVSR
from .capture import InferenceError, load_archive


def words(text: str) -> list[str]:
    import re
    return re.findall(r"[a-z0-9]+(?:'[a-z0-9]+)?", text.lower())


def edit_distance(reference, hypothesis):
    previous = list(range(len(hypothesis) + 1))
    for row, expected in enumerate(reference, 1):
        current = [row]
        for column, actual in enumerate(hypothesis, 1):
            current.append(min(current[-1] + 1, previous[column] + 1,
                               previous[column - 1] + (expected != actual)))
        previous = current
    return previous[-1]


def evaluate(engine, dataset: Path):
    """JSONL: capture (relative directory), reference (empty for rest), session."""
    rows, distances, reference_count, exact, rest_false, failures = [], 0, 0, 0, 0, 0
    sentence_count = rest_count = 0
    for line in dataset.read_text().splitlines():
        if not line.strip():
            continue
        entry = json.loads(line)
        if not isinstance(entry.get("reference"), str) or not entry.get("session"):
            raise ValueError("Every evaluation row needs reference text and a session identifier.")
        reference = words(entry["reference"])
        started = time.perf_counter()
        error = None
        text = ""
        try:
            manifest, paths = load_archive(dataset.parent / entry["capture"])
            text = engine.transcribe(manifest, paths)
        except InferenceError as exc:
            error = exc.code
            # An empty decode is the correct result for a resting-face recording.
            if reference or exc.code != "empty_transcript":
                failures += 1
        predicted = words(text)
        if reference:
            sentence_count += 1
            distances += edit_distance(reference, predicted)
            reference_count += len(reference)
            exact += int(reference == predicted and error is None)
        else:
            rest_count += 1
            rest_false += int(bool(predicted))
        rows.append({**entry, "rawTranscript": text, "error": error,
                     "processingSeconds": time.perf_counter() - started})
    timings = sorted(row["processingSeconds"] for row in rows)
    return {"modelVersion": engine.model_version, "device": engine.device,
            "sentenceCount": sentence_count, "restCount": rest_count,
            "sessions": sorted({row["session"] for row in rows}),
            "wordErrorRate": distances / reference_count if reference_count else None,
            "sentenceExactMatchRate": exact / sentence_count if sentence_count else None,
            "restFalseTranscriptRate": rest_false / rest_count if rest_count else None,
            "failureCount": failures,
            "medianProcessingSeconds": statistics.median(timings) if timings else None,
            "p95ProcessingSeconds": timings[min(len(timings) - 1, int(len(timings) * 0.95))] if timings else None,
            "latencyScope": "archive preprocessing and decoding; excludes phone capture and network upload",
            "clips": rows}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--auto-avsr", type=Path, default=os.environ.get("SILENTVOICE_AUTO_AVSR"))
    parser.add_argument("--checkpoint", type=Path, default=os.environ.get("SILENTVOICE_CHECKPOINT"))
    parser.add_argument("--device", choices=["auto", "mps", "cpu"], default="auto")
    sub = parser.add_subparsers(dest="command", required=True)
    transcribe = sub.add_parser("transcribe", help="Transcribe one finalized schema-v2 archive")
    transcribe.add_argument("capture", type=Path)
    transcribe.add_argument("--preview", type=Path, help="Write aligned 88×88 mouth PNGs")
    evaluate_parser = sub.add_parser("evaluate", help="Evaluate labeled sentence and resting-face archives")
    evaluate_parser.add_argument("dataset", type=Path)
    evaluate_parser.add_argument("--output", type=Path, required=True)
    serve = sub.add_parser("serve", help="Start the Mac HTTP service")
    serve.add_argument("--host", default="0.0.0.0")
    serve.add_argument("--port", type=int, default=8000)
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO)
    if not args.auto_avsr or not args.checkpoint:
        parser.error("Provide --auto-avsr and --checkpoint, or set SILENTVOICE_AUTO_AVSR and SILENTVOICE_CHECKPOINT.")
    if args.command == "serve":
        import uvicorn
        os.environ["SILENTVOICE_AUTO_AVSR"] = str(args.auto_avsr)
        os.environ["SILENTVOICE_CHECKPOINT"] = str(args.checkpoint)
        os.environ["SILENTVOICE_DEVICE"] = args.device
        uvicorn.run("silentvoice.server:app", host=args.host, port=args.port, workers=1, access_log=False)
        return
    engine = AutoAVSR(args.auto_avsr, args.checkpoint, args.device)
    if args.command == "transcribe":
        manifest, paths = load_archive(args.capture)
        started = time.perf_counter()
        text = engine.transcribe(manifest, paths, args.preview)
        print(json.dumps({"sampleID": str(manifest.sampleID), "transcript": text,
                          "modelVersion": engine.model_version, "device": engine.device,
                          "processingSeconds": time.perf_counter() - started}))
    else:
        report = evaluate(engine, args.dataset)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, indent=2) + "\n")
        print(json.dumps({key: value for key, value in report.items() if key != "clips"}, indent=2))


if __name__ == "__main__":
    main()
