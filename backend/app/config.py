from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    database_url: str = "sqlite:///./dev.db"
    jwt_secret: str = "change-this-secret-in-production"
    jwt_algorithm: str = "HS256"
    access_token_expire_minutes: int = 60
    cors_origins: str = "*"

    # ---- Object storage (Bronze layer) ----
    # storage_backend: "minio" (default) or "memory" (tests / no-MinIO local runs)
    storage_backend: str = "minio"
    minio_endpoint: str = "localhost:9000"
    minio_root_user: str = "minioadmin"
    minio_root_password: str = "minioadmin"
    minio_secure: bool = False
    minio_bucket_bronze: str = "bronze"

    # ---- OCR / Silver layer ----
    # ocr_backend: "easyocr" (real, Thai+English, CPU) or "stub" (no-op, for
    # local runs / machines without the heavy model installed).
    ocr_backend: str = "easyocr"
    ocr_languages: str = "th,en"
    # Auto-approval thresholds (Phase 14): approve only when OCR is confident AND
    # the extracted text matches the student/activity well enough.
    ocr_auto_confidence: float = 0.6
    ocr_auto_match: float = 0.7

    # ---- เช็กอินหน้างานด้วย QR ----
    # หน้าต่างเวลาที่ยอมให้สแกน QR ได้: เปิดก่อนเริ่มกิจกรรม checkin_open_before_minutes
    # นาที และปิดหลังกิจกรรมจบ (start_at + activity.hours) อีก checkin_close_after_minutes
    # นาที — กันสแกนจากรูปถ่ายย้อนหลัง/ล่วงหน้า (กฎ D1)
    checkin_open_before_minutes: int = 60
    checkin_close_after_minutes: int = 180

    # ---- Chatbot (LLM + RAG, Phase 16) ----
    # llm_backend: "gemini" (real cloud LLM, needs gemini_api_key) or "stub"
    # (deterministic, offline — used by tests and local runs without a key).
    # Defaults to stub so the app boots and tests run without any API key.
    llm_backend: str = "stub"
    gemini_api_key: str = ""
    gemini_model: str = "gemini-flash-latest"
    gemini_embed_model: str = "models/gemini-embedding-001"
    # vector_backend: "memory" (portable cosine over an in-process store — used by
    # SQLite dev + tests) or "pgvector" (Postgres pgvector extension, production).
    vector_backend: str = "memory"
    # How many rule chunks to retrieve for a RAG answer.
    rag_top_k: int = 4

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    @property
    def cors_origin_list(self) -> list[str]:
        if self.cors_origins == "*":
            return ["*"]
        return [origin.strip() for origin in self.cors_origins.split(",")]


settings = Settings()
