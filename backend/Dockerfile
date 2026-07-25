FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Preload the EasyOCR Thai+English models at build time so the first request at
# runtime does not have to download them (the models are large). Best-effort:
# if the network is unavailable during build, models download lazily on first use.
RUN python -c "import easyocr; easyocr.Reader(['th','en'], gpu=False)" || \
    echo "WARN: could not preload EasyOCR models at build; will download on first use"

COPY app ./app
COPY seed.py .
COPY alembic.ini .
COPY alembic ./alembic

EXPOSE 8000

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
