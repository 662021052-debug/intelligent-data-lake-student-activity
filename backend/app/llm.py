"""LLM client for the chatbot (Phase 16), behind a small interface so tests mock it.

Mirrors ``storage.py`` / ``ocr.py``: the cloud dependency (``google-generativeai``)
is imported lazily and only used when ``llm_backend="gemini"`` with an API key
configured. Tests and offline runs use :class:`StubLlm` — deterministic hash-based
embeddings and a canned generator — so there are no network calls, no cost, and no
nondeterminism.

Only two capabilities are needed:
  * ``embed`` / ``embed_query`` — turn text into a vector for retrieval (RAG).
  * ``generate`` — write the final Thai answer grounded on retrieved rule text.
"""
from __future__ import annotations

import hashlib
from typing import Optional, Protocol, runtime_checkable

from app.config import settings

# Dimension of StubLlm embeddings. The real Gemini embedding model returns its own
# (larger) dimension; retrieval only requires that document and query vectors come
# from the *same* client, so the two never need to agree on a size. A large space
# keeps hash collisions between distinct n-grams rare.
STUB_EMBEDDING_DIM = 2048


@runtime_checkable
class LlmClient(Protocol):
    def embed(self, texts: list[str]) -> list[list[float]]:
        """Embed a batch of documents (for ingestion)."""
        ...

    def embed_query(self, text: str) -> list[float]:
        """Embed a single query string (for retrieval)."""
        ...

    def generate(self, prompt: str, *, system: Optional[str] = None) -> str:
        """Produce a free-text completion for ``prompt``."""
        ...


def _char_ngrams(text: str, n: int = 3) -> list[str]:
    """Character n-grams of the whitespace-stripped text.

    Thai is written without spaces, so word tokenization needs a segmenter we do
    not want as a test dependency. Character n-grams capture substring overlap
    (e.g. a query and a rule chunk that both contain "รับใช้สังคม") well enough to
    make deterministic offline retrieval meaningful.
    """
    compact = "".join(text.lower().split())
    if len(compact) < n:
        return [compact] if compact else []
    return [compact[i : i + n] for i in range(len(compact) - n + 1)]


class StubLlm:
    """Deterministic, offline LLM stand-in used by tests and keyless local runs.

    Embeddings are a binary bag-of-ngrams hash projection: each distinct n-gram sets
    one dimension. Under cosine similarity this rewards a focused chunk that shares
    the query's *distinctive* n-grams and does not let a long chunk win merely by
    repeating common ones — enough for retrieval tests to assert the right rule chunk
    comes back, without a real embedding model.
    """

    def __init__(self, dim: int = STUB_EMBEDDING_DIM) -> None:
        self._dim = dim

    def _embed_one(self, text: str) -> list[float]:
        vec = [0.0] * self._dim
        for gram in set(_char_ngrams(text)):
            bucket = int(hashlib.sha1(gram.encode("utf-8")).hexdigest(), 16) % self._dim
            vec[bucket] = 1.0
        return vec

    def embed(self, texts: list[str]) -> list[list[float]]:
        return [self._embed_one(t) for t in texts]

    def embed_query(self, text: str) -> list[float]:
        return self._embed_one(text)

    def generate(self, prompt: str, *, system: Optional[str] = None) -> str:
        # Offline mode cannot phrase a natural answer, so it returns a clearly
        # marked placeholder. Callers (and tests) rely on the retrieved `sources`,
        # not on this text, when the real LLM is unavailable.
        return "(โหมดออฟไลน์: ไม่มีโมเดลภาษา) โปรดดูข้อมูลอ้างอิงจากเอกสารด้านล่าง"


class GeminiClient:
    """Google Gemini client. ``google.generativeai`` is imported lazily so the
    dependency is only required when this backend is actually selected."""

    def __init__(self, api_key: str, model: str, embed_model: str) -> None:
        import google.generativeai as genai  # lazy: only for the real backend

        genai.configure(api_key=api_key)
        self._genai = genai
        self._model_name = model
        self._embed_model = embed_model

    def embed(self, texts: list[str]) -> list[list[float]]:
        return [self._embed_content(t, "retrieval_document") for t in texts]

    def embed_query(self, text: str) -> list[float]:
        return self._embed_content(text, "retrieval_query")

    def _embed_content(self, text: str, task_type: str) -> list[float]:
        res = self._genai.embed_content(
            model=self._embed_model, content=text, task_type=task_type
        )
        return [float(x) for x in res["embedding"]]

    def generate(self, prompt: str, *, system: Optional[str] = None) -> str:
        model = self._genai.GenerativeModel(self._model_name, system_instruction=system)
        res = model.generate_content(prompt)
        return (getattr(res, "text", "") or "").strip()


_llm: Optional[LlmClient] = None


def _build_llm() -> LlmClient:
    # Fall back to the offline stub whenever the real backend is not usable, so a
    # missing key never crashes the app — it just answers in offline mode.
    if settings.llm_backend == "gemini" and settings.gemini_api_key:
        return GeminiClient(
            api_key=settings.gemini_api_key,
            model=settings.gemini_model,
            embed_model=settings.gemini_embed_model,
        )
    return StubLlm()


def get_llm() -> LlmClient:
    """FastAPI dependency returning the process-wide LLM client."""
    global _llm
    if _llm is None:
        _llm = _build_llm()
    return _llm
