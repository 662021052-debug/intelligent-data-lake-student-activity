"""OCR engine for the Silver layer.

`run_ocr(image_bytes) -> (text, confidence)` is exposed behind a small
`OcrEngine` interface so it can be swapped for a fake in tests (the real
EasyOCR model is heavy and non-deterministic — never call it from tests).

Mirrors `storage.py`: the heavy dependency (`easyocr`) is imported lazily so the
package is only required when the real backend actually runs. Local runs or
machines without the model can set `OCR_BACKEND=stub`.
"""
from __future__ import annotations

from typing import Optional, Protocol, runtime_checkable

from app.config import settings

# (extracted_text, average_confidence 0-1)
OcrResult = tuple[str, float]


@runtime_checkable
class OcrEngine(Protocol):
    def run_ocr(self, image_bytes: bytes) -> OcrResult:
        ...


class EasyOcrEngine:
    """Thai + English OCR via EasyOCR on CPU.

    The reader (and its model files) are loaded lazily on first use — building it
    is expensive, so we avoid paying that cost at import/startup time.
    """

    def __init__(self, languages: list[str]) -> None:
        self._languages = languages or ["en"]
        self._reader = None

    def _get_reader(self):
        if self._reader is None:
            import easyocr  # lazy: only needed for real OCR

            self._reader = easyocr.Reader(self._languages, gpu=False)
        return self._reader

    def run_ocr(self, image_bytes: bytes) -> OcrResult:
        reader = self._get_reader()
        # detail=1 -> list of (bbox, text, confidence)
        results = reader.readtext(image_bytes, detail=1)
        if not results:
            return ("", 0.0)
        texts = [str(r[1]) for r in results]
        confidences = [float(r[2]) for r in results]
        text = "\n".join(texts)
        confidence = sum(confidences) / len(confidences) if confidences else 0.0
        return (text, confidence)


class StubOcrEngine:
    """No-op OCR for environments without the model. Always yields an empty read
    (confidence 0), which the pipeline treats as 'needs_review'."""

    def run_ocr(self, image_bytes: bytes) -> OcrResult:
        return ("", 0.0)


_ocr: Optional[OcrEngine] = None


def _build_ocr() -> OcrEngine:
    if settings.ocr_backend == "stub":
        return StubOcrEngine()
    languages = [lang.strip() for lang in settings.ocr_languages.split(",") if lang.strip()]
    return EasyOcrEngine(languages)


def get_ocr() -> OcrEngine:
    """FastAPI dependency returning the process-wide OCR engine."""
    global _ocr
    if _ocr is None:
        _ocr = _build_ocr()
    return _ocr
