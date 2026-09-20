FROM python:3.11-slim

WORKDIR /app

# ฟอนต์ไทย: seed วาดใบประกาศตัวอย่างด้วยฟอนต์นี้ ถ้าไม่มี ตัวอักษรไทยจะกลายเป็นกล่อง
# และ OCR จะอ่านไม่ออก (fonts-thai-tlwg เป็นฟอนต์เสรีของ TLWG)
RUN apt-get update \
    && apt-get install -y --no-install-recommends fonts-thai-tlwg \
    && rm -rf /var/lib/apt/lists/*

# torch/torchvision แบบ CPU-only — ติดตั้ง "ก่อน" requirements.txt เสมอ
#
# easyocr ต้องการ torch แต่ไม่ pin เวอร์ชัน pip จึงดึงรุ่นล่าสุดจาก PyPI ซึ่งบน Linux มาพร้อม
# CUDA + nvidia-* 15 ตัวและ triton (~2.5 GB ตอนโหลด บวมเป็นหลายสิบ GB ตอนแตกไฟล์ → build ล้ม
# "No space left on device") ทั้งที่ระบบรัน EasyOCR แบบ CPU ล้วน (gpu=False) ไม่มี GPU ให้ใช้
# ติดตั้งจาก CPU index ก่อน แล้ว pip install -r requirements.txt จะเห็นว่า torch ครบแล้วและไม่ดึงซ้ำ
#
# เวอร์ชันตรงกับที่ image เดิมใช้ (torch 2.14.0 / torchvision 0.29.0 — มี wheel +cpu ของ cp311 บน index นี้)
# OCR จึงรันบน torch รุ่นเดียวกับที่เคยผ่านเทสมา ตัดออกแค่ส่วน GPU ไม่ใช้รุ่นเก่ากว่านี้เพราะ
# image ใช้ numpy 2.x (torch < 2.3 คอมไพล์กับ numpy 1.x แล้ว tensor.numpy() จะพัง)
# เปลี่ยนเวอร์ชันได้ที่นี่ที่เดียว: --build-arg TORCH_VERSION=... TORCHVISION_VERSION=...
# (ไม่ pin ใน requirements.txt เพราะไฟล์นั้นใช้ติดตั้งบนเครื่อง dev ด้วย ที่ไม่ควรถูกบังคับเป็น CPU)
ARG TORCH_VERSION=2.14.0
ARG TORCHVISION_VERSION=0.29.0
RUN pip install --no-cache-dir \
        torch==${TORCH_VERSION} torchvision==${TORCHVISION_VERSION} \
        --index-url https://download.pytorch.org/whl/cpu

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Preload the EasyOCR Thai+English models at build time so the first request at
# runtime does not have to download them (the models are large). Best-effort:
# if the network is unavailable during build, models download lazily on first use.
RUN python -c "import easyocr; easyocr.Reader(['th','en'], gpu=False)" || \
    echo "WARN: could not preload EasyOCR models at build; will download on first use"

COPY app ./app
COPY seed.py .
COPY seed_criteria.py .
COPY seed_evidence.py .
# หลักฐานเดโมของหน้าตรวจหลักฐาน — ต้องรันในคอนเทนเนอร์ที่มีฟอนต์ไทย + easyocr + MinIO
COPY seed_evidence_demo.py .
COPY wipe_data.py .
# สคริปต์ตรวจความครบเกณฑ์เทียบสถานะจากไฟล์นำเข้า (เฟส 6) — รันในคอนเทนเนอร์ที่ต่อ DB จริง
COPY check_completion.py .
COPY alembic.ini .
COPY alembic ./alembic

EXPOSE 8000

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
