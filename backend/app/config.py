from pydantic import AliasChoices, Field
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

    # ---- ภาพเกือบเหมือน: pHash 256 บิต + text veto (OCR เฟส 3A.2) ----
    # checksum ไม่ตรง แต่ Hamming distance ของ pHash ≤ ค่านี้ → ภาพคล้าย (flag แบบ near)
    # วัดบนเกียรติบัตรเดโม: สำเนาบีบอัด/ย่อ 6–12 บิต · ใบคนละคนเทมเพลตเดียวกันห่างอย่างน้อย 24 บิต
    ocr_phash_near_bits: int = 16
    # text veto: ภาพคล้ายแต่ข้อความ OCR ของสองใบต่างกันชัด (ความคล้าย < ค่านี้) และอ่านออกทั้งคู่
    # → ถือเป็นเทมเพลตเดียวกันคนละคน ไม่ flag · ใบใดอ่านไม่ออก/ว่าง/ยังไม่เคย OCR → คง flag ไว้
    # วัดแล้ว: ใบเดิม OCR ใหม่หลังบีบอัด/ย่อได้ 0.72–0.99 · ใบคนละคนมัธยฐาน 0.48
    # ตั้ง 0 = ปิด veto
    ocr_text_veto_max_similarity: float = 0.5
    # "อ่านออก" = มีตัวอักษรอย่างน้อยเท่านี้หลังตัดช่องว่าง (เกียรติบัตรเดโมอ่านได้ 128–283 ตัว)
    ocr_text_veto_min_chars: int = 40

    # ---- PDF: render หน้าเป็นภาพแล้ว OCR (OCR เฟส 3B) ----
    # OCR บน CPU ใช้หน้าละหลายวินาที จึงอ่านแค่ไม่กี่หน้าแรก (เกียรติบัตรส่วนใหญ่มีหน้าเดียว)
    ocr_pdf_max_pages: int = 3
    ocr_pdf_dpi: int = 200
    # กันหน้า PDF ขนาดผิดปกติ (เช่น 5 เมตร) กลายเป็นภาพหลายหมื่นพิกเซลจนหน่วยความจำหมด
    ocr_pdf_max_side_px: int = 4000
    # text layer ก่อน: PDF ที่ export จากโปรแกรมมีข้อความจริงอยู่แล้ว ใช้ตรง ๆ ข้าม OCR
    # (อ่านถูกทุกตัว เร็วกว่า OCR หน้าละหลายวินาที) — ถือว่ามีเมื่อข้อความ ≥ ค่านี้หลังตัดช่องว่าง
    # น้อยกว่านี้ (เช่นมีแค่เลขหน้า/ลายน้ำ) หรือเป็น PDF สแกนภาพล้วน ค่อย render + OCR
    ocr_pdf_text_layer_min_chars: int = 40
    # ความมั่นใจที่ใส่ให้ข้อความจาก text layer (อ่านจากไฟล์ตรง ๆ ไม่ได้เดา)
    ocr_pdf_text_layer_confidence: float = 1.0

    # ---- เช็กอินหน้างานด้วย QR ----
    # URL ของ "หน้าเว็บนิสิต" ที่ QR จะชี้ไป — ต้องเป็นโดเมนจริงที่มือถือเปิดถึง
    # ตอน deploy (localhost ใช้ได้แค่ทดสอบในเครื่องเดียว) เก็บ URL เต็มลง QR
    # เพื่อให้กล้องมือถือปกติขึ้นปุ่ม "เปิดลิงก์" ให้ ไม่ต้องเปิดแอปสแกนเอง
    public_app_base_url: str = "http://localhost:8080"
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

    # ---- อีเมลแจ้งเตือน (ข้อ 6.4) ----
    # email_backend: "smtp" (ส่งจริง ต้องตั้ง SMTP_HOST) หรือ "stub" (ไม่ส่งจริง
    # เก็บไว้ใน memory) — ดีฟอลต์เป็น stub เพื่อไม่ให้ระบบที่ยังไม่ตั้งค่าเผลอ
    # ยิงอีเมลถึงนิสิตทั้งมหาวิทยาลัย
    email_backend: str = "stub"
    smtp_host: str = ""
    smtp_port: int = 587
    smtp_user: str = ""
    # รับทั้ง SMTP_PASSWORD และ SMTP_PASS — เอกสารสเปกเขียน SMTP_PASS ถ้าไม่รับ
    # ชื่อนี้ด้วย คนตั้งค่าตามเอกสารจะได้รหัสผ่านว่างแบบเงียบ ๆ แล้วงงว่าทำไม login ไม่ผ่าน
    smtp_password: str = Field(
        default="", validation_alias=AliasChoices("smtp_password", "smtp_pass")
    )
    smtp_from: str = "no-reply@tsu.ac.th"
    smtp_use_tls: bool = True
    # ต่ำกว่ากี่ % ของชั่วโมงที่ต้องได้ ถือว่าเป็นกลุ่มเสี่ยง (ตรงกับดีฟอลต์ของ
    # /dashboard/at-risk เพื่อให้ "รายชื่อบนแดชบอร์ด" กับ "คนที่ได้รับอีเมล" ตรงกัน)
    notify_at_risk_threshold: float = 50
    # ตั้งเวลาเช็กกลุ่มเสี่ยงอัตโนมัติวันละครั้ง — ปิดไว้เป็นค่าเริ่มต้น ต้องเปิดเอง
    # ตอน deploy จริง (ดีฟอลต์เปิดจะทำให้ทุกเครื่อง dev มี thread ตั้งเวลาโดยไม่ตั้งใจ)
    notify_scheduler_enabled: bool = False
    # สวิตช์แยกรายงาน (มีผลเมื่อ scheduler เปิด) — เตือนกิจกรรมพรุ่งนี้เปิดไว้ แต่อีเมลกลุ่มเสี่ยงปิดไว้
    # เปิด scheduler เพื่อเตือนกิจกรรมแล้วต้องไม่พาอีเมลกลุ่มเสี่ยงออกไปด้วยโดยไม่ตั้งใจ
    notify_reminder_enabled: bool = True
    notify_at_risk_enabled: bool = False
    # อีเมลยืนยันตอนนิสิตสมัครกิจกรรม — ไม่ขึ้นกับ scheduler (ส่งทันทีหลังสมัคร) ปิดได้ด้วยสวิตช์นี้
    notify_registration_email_enabled: bool = True
    notify_at_risk_hour: int = 8  # เวลาไทยที่ให้ job รายวันทำงาน
    # เวลาไทยที่ส่งอีเมลเตือน "พรุ่งนี้มีกิจกรรม" — ค่าเริ่มต้นเป็นหัวค่ำ เพราะอีเมลที่ถึง
    # ตอนเย็นก่อนวันงานมีโอกาสถูกอ่านก่อนเข้านอนมากกว่าฉบับที่ส่งตั้งแต่เช้าวันก่อนหน้า
    notify_activity_reminder_hour: int = 18

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    @property
    def cors_origin_list(self) -> list[str]:
        if self.cors_origins == "*":
            return ["*"]
        return [origin.strip() for origin in self.cors_origins.split(",")]


settings = Settings()
