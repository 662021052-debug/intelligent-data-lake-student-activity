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

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    @property
    def cors_origin_list(self) -> list[str]:
        if self.cors_origins == "*":
            return ["*"]
        return [origin.strip() for origin in self.cors_origins.split(",")]


settings = Settings()
