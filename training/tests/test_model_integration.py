"""Opt-in test with real weights. A static face checks plumbing, not accuracy."""
import os
from pathlib import Path
import time

import pytest

from silentvoice.capture import ClipManifest


@pytest.mark.skipif(not os.environ.get("SILENTVOICE_RUN_MODEL_TEST"), reason="Requires checkpoint and desktop graphics access")
def test_real_preprocessing_and_decoder(tmp_path):
    from PIL import Image
    from skimage import data
    from silentvoice.avsr import AutoAVSR

    started = time.perf_counter()
    engine = AutoAVSR.from_environment()
    startup = time.perf_counter() - started
    # Public-domain scikit-image astronaut fixture; fixed face crop repeated 30 times.
    face = Image.fromarray(data.astronaut()).crop((155, 35, 300, 180)).resize((256, 256))
    image = tmp_path / "face.png"
    face.save(image)
    manifest = ClipManifest(sampleID="00000000-0000-0000-0000-000000000001", schemaVersion=2,
                            frameCount=30, timestamps=[100 + i / 30 for i in range(30)])
    video = engine.preprocess(manifest, [image] * 30, tmp_path / "preview")
    assert video.shape == (25, 1, 88, 88)
    assert engine.torch.isfinite(video).all()
    assert len(list((tmp_path / "preview").glob("*.png"))) == 25
    started = time.perf_counter()
    text = engine._decode(video)
    assert isinstance(text, str)
    print({"device": engine.device, "startupSeconds": startup,
           "oneSecondStaticFaceDecodeSeconds": time.perf_counter() - started,
           "note": "static image is not a speech accuracy evaluation"})
