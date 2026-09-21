"""Object storage for the Bronze layer.

The Bronze layer keeps raw evidence files exactly as uploaded (immutable). This
module abstracts the storage backend so the rest of the app depends on a small
interface (`ObjectStorage`) rather than on MinIO/S3 directly — that also lets
tests swap in an in-memory fake without a running MinIO.
"""
from __future__ import annotations

import io
from typing import Iterator, Optional, Protocol, runtime_checkable

from app.config import settings


STREAM_CHUNK_SIZE = 64 * 1024


@runtime_checkable
class ObjectStorage(Protocol):
    def ensure_bucket(self, bucket: str) -> None:
        ...

    def upload_object(
        self, bucket: str, object_key: str, data: bytes, content_type: str
    ) -> None:
        ...

    def get_object_bytes(self, bucket: str, object_key: str) -> bytes:
        ...

    def iter_object(self, bucket: str, object_key: str, chunk_size: int = ...) -> Iterator[bytes]:
        ...

    def remove_object(self, bucket: str, object_key: str) -> None:
        ...


class MinIOStorage:
    """S3-compatible storage backed by MinIO.

    `minio` is imported lazily so the dependency is only required when the real
    backend is actually used (tests use the in-memory fake instead).
    """

    def __init__(
        self,
        endpoint: str,
        access_key: str,
        secret_key: str,
        secure: bool = False,
    ) -> None:
        from minio import Minio

        self._client = Minio(
            endpoint,
            access_key=access_key,
            secret_key=secret_key,
            secure=secure,
        )

    def ensure_bucket(self, bucket: str) -> None:
        if not self._client.bucket_exists(bucket):
            self._client.make_bucket(bucket)

    def upload_object(
        self, bucket: str, object_key: str, data: bytes, content_type: str
    ) -> None:
        self._client.put_object(
            bucket,
            object_key,
            io.BytesIO(data),
            length=len(data),
            content_type=content_type,
        )

    def get_object_bytes(self, bucket: str, object_key: str) -> bytes:
        response = None
        try:
            response = self._client.get_object(bucket, object_key)
            return response.read()
        finally:
            if response is not None:
                response.close()
                response.release_conn()

    def iter_object(
        self, bucket: str, object_key: str, chunk_size: int = STREAM_CHUNK_SIZE
    ) -> Iterator[bytes]:
        """Open the object now (a missing key raises FileNotFoundError here, not on the
        first `next()`), then hand back an iterator that streams it chunk by chunk."""
        from minio.error import S3Error

        try:
            response = self._client.get_object(bucket, object_key)
        except S3Error as exc:
            if exc.code in ("NoSuchKey", "NoSuchBucket"):
                raise FileNotFoundError(object_key) from exc
            raise

        def _stream() -> Iterator[bytes]:
            try:
                yield from response.stream(chunk_size)
            finally:
                response.close()
                response.release_conn()

        return _stream()

    def remove_object(self, bucket: str, object_key: str) -> None:
        # MinIO's remove_object is already idempotent — a missing key is not an error
        self._client.remove_object(bucket, object_key)


class InMemoryStorage:
    """Dict-backed storage for tests and local runs without MinIO."""

    def __init__(self) -> None:
        self._buckets: set[str] = set()
        self._objects: dict[tuple[str, str], bytes] = {}

    def ensure_bucket(self, bucket: str) -> None:
        self._buckets.add(bucket)

    def upload_object(
        self, bucket: str, object_key: str, data: bytes, content_type: str
    ) -> None:
        self._buckets.add(bucket)
        self._objects[(bucket, object_key)] = data

    def get_object_bytes(self, bucket: str, object_key: str) -> bytes:
        try:
            return self._objects[(bucket, object_key)]
        except KeyError as exc:
            raise FileNotFoundError(object_key) from exc

    def iter_object(
        self, bucket: str, object_key: str, chunk_size: int = STREAM_CHUNK_SIZE
    ) -> Iterator[bytes]:
        data = self.get_object_bytes(bucket, object_key)  # FileNotFoundError if missing
        return (data[i : i + chunk_size] for i in range(0, len(data), chunk_size))

    def remove_object(self, bucket: str, object_key: str) -> None:
        self._objects.pop((bucket, object_key), None)


_storage: Optional[ObjectStorage] = None


def _build_storage() -> ObjectStorage:
    if settings.storage_backend == "memory":
        return InMemoryStorage()
    return MinIOStorage(
        endpoint=settings.minio_endpoint,
        access_key=settings.minio_root_user,
        secret_key=settings.minio_root_password,
        secure=settings.minio_secure,
    )


def get_storage() -> ObjectStorage:
    """FastAPI dependency returning the process-wide storage backend."""
    global _storage
    if _storage is None:
        _storage = _build_storage()
    return _storage
