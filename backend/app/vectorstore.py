"""Vector store for RAG document chunks (Phase 16).

Behind a small :class:`VectorStore` interface, mirroring ``storage.py`` / ``ocr.py``:

  * :class:`InMemoryVectorStore` — portable cosine similarity over an in-process
    list. Used by SQLite dev and by tests; no external service required. The rule
    document is small (a handful of chunks), so a linear scan is more than fast
    enough.
  * :class:`PgVectorStore` — Postgres ``pgvector`` extension for production. Owns
    its own table (created via raw SQL) so no pgvector-typed SQLModel column leaks
    into the portable schema used by SQLite.

Both are re-ingested idempotently: :meth:`replace_source` clears a source's chunks
before inserting the fresh set, so ingesting on every startup is safe.
"""
from __future__ import annotations

import math
from dataclasses import dataclass
from typing import Optional, Protocol, runtime_checkable

from app.config import settings


@dataclass
class StoredChunk:
    source: str
    chunk_index: int
    content: str
    embedding: list[float]


@dataclass
class RetrievedChunk:
    source: str
    chunk_index: int
    content: str
    score: float  # cosine similarity in [-1, 1]; higher is more relevant


def cosine_similarity(a: list[float], b: list[float]) -> float:
    if len(a) != len(b):
        # Vectors from different embedding models are not comparable.
        raise ValueError("embedding dimensions do not match")
    dot = sum(x * y for x, y in zip(a, b))
    norm_a = math.sqrt(sum(x * x for x in a))
    norm_b = math.sqrt(sum(y * y for y in b))
    if norm_a == 0.0 or norm_b == 0.0:
        return 0.0
    return dot / (norm_a * norm_b)


@runtime_checkable
class VectorStore(Protocol):
    def replace_source(self, source: str, chunks: list[StoredChunk]) -> None:
        """Atomically replace all chunks for ``source`` with ``chunks``."""
        ...

    def search(self, embedding: list[float], k: int) -> list[RetrievedChunk]:
        """Return the ``k`` most similar chunks, most relevant first."""
        ...

    def count(self) -> int:
        ...


class InMemoryVectorStore:
    """Process-wide, dict-backed store (portable). Mirrors ``InMemoryStorage``."""

    def __init__(self) -> None:
        self._chunks: list[StoredChunk] = []

    def replace_source(self, source: str, chunks: list[StoredChunk]) -> None:
        self._chunks = [c for c in self._chunks if c.source != source]
        self._chunks.extend(chunks)

    def search(self, embedding: list[float], k: int) -> list[RetrievedChunk]:
        scored = [
            RetrievedChunk(
                source=c.source,
                chunk_index=c.chunk_index,
                content=c.content,
                score=cosine_similarity(embedding, c.embedding),
            )
            for c in self._chunks
        ]
        scored.sort(key=lambda r: r.score, reverse=True)
        return scored[: max(k, 0)]

    def count(self) -> int:
        return len(self._chunks)


class PgVectorStore:
    """Postgres pgvector-backed store. Owns table ``rag_rule_chunk``.

    Embeddings are passed as pgvector string literals (``[0.1,0.2,...]``) so no
    extra Python dependency (``pgvector``) is needed; the ``vector`` column type and
    the ``<=>`` (cosine distance) operator come from the extension itself.
    """

    _TABLE = "rag_rule_chunk"

    def __init__(self, engine, dim: int) -> None:
        self._engine = engine
        self._dim = dim
        self._ensure_schema()

    def _ensure_schema(self) -> None:
        from sqlalchemy import text

        with self._engine.begin() as conn:
            conn.execute(text("CREATE EXTENSION IF NOT EXISTS vector"))
            conn.execute(
                text(
                    f"CREATE TABLE IF NOT EXISTS {self._TABLE} ("
                    "id serial PRIMARY KEY,"
                    "source text NOT NULL,"
                    "chunk_index integer NOT NULL,"
                    "content text NOT NULL,"
                    f"embedding vector({self._dim}) NOT NULL)"
                )
            )

    @staticmethod
    def _to_literal(embedding: list[float]) -> str:
        return "[" + ",".join(repr(float(x)) for x in embedding) + "]"

    def replace_source(self, source: str, chunks: list[StoredChunk]) -> None:
        from sqlalchemy import text

        with self._engine.begin() as conn:
            conn.execute(
                text(f"DELETE FROM {self._TABLE} WHERE source = :source"),
                {"source": source},
            )
            for c in chunks:
                conn.execute(
                    text(
                        f"INSERT INTO {self._TABLE} (source, chunk_index, content, embedding) "
                        "VALUES (:source, :idx, :content, CAST(:emb AS vector))"
                    ),
                    {
                        "source": c.source,
                        "idx": c.chunk_index,
                        "content": c.content,
                        "emb": self._to_literal(c.embedding),
                    },
                )

    def search(self, embedding: list[float], k: int) -> list[RetrievedChunk]:
        from sqlalchemy import text

        with self._engine.connect() as conn:
            rows = conn.execute(
                text(
                    f"SELECT source, chunk_index, content, "
                    "1 - (embedding <=> CAST(:emb AS vector)) AS score "
                    f"FROM {self._TABLE} ORDER BY embedding <=> CAST(:emb AS vector) LIMIT :k"
                ),
                {"emb": self._to_literal(embedding), "k": max(k, 0)},
            ).all()
        return [
            RetrievedChunk(source=r[0], chunk_index=r[1], content=r[2], score=float(r[3]))
            for r in rows
        ]

    def count(self) -> int:
        from sqlalchemy import text

        with self._engine.connect() as conn:
            return int(conn.execute(text(f"SELECT count(*) FROM {self._TABLE}")).scalar_one())


_vector_store: Optional[VectorStore] = None


def _build_vector_store() -> VectorStore:
    if settings.vector_backend == "pgvector":
        from app.database import engine
        from app.llm import STUB_EMBEDDING_DIM

        # Gemini's text-embedding-004 is 768-dim; the stub is STUB_EMBEDDING_DIM.
        dim = 768 if (settings.llm_backend == "gemini" and settings.gemini_api_key) else STUB_EMBEDDING_DIM
        return PgVectorStore(engine, dim=dim)
    return InMemoryVectorStore()


def get_vector_store() -> VectorStore:
    """FastAPI dependency returning the process-wide vector store."""
    global _vector_store
    if _vector_store is None:
        _vector_store = _build_vector_store()
    return _vector_store
