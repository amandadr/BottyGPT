FROM python:3.12-slim AS builder

ENV PIP_NO_CACHE_DIR=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

RUN apt-get update && \
    apt-get install -y --no-install-recommends build-essential gcc g++ && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /tmp/build
COPY requirements.txt .

RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

RUN pip install --upgrade pip setuptools wheel && \
    pip install -r requirements.txt && \
    pip check


FROM python:3.12-slim AS final

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/opt/venv/bin:$PATH" \
    FLASK_APP=app.py

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        curl \
        libgl1 \
        libglib2.0-0 \
        poppler-utils \
        tini && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN groupadd --gid 10001 appuser && \
    useradd --uid 10001 --gid appuser --create-home --shell /usr/sbin/nologin appuser

COPY --from=builder /opt/venv /opt/venv
COPY . /app/application

RUN mkdir -p /app/application/inputs/local /app/indexes /app/inputs /app/vectors && \
    chown -R appuser:appuser /app

EXPOSE 7091
USER appuser

CMD ["tini", "--", "gunicorn", "-w", "1", "--timeout", "120", "--bind", "0.0.0.0:7091", "--preload", "application.wsgi:app"]
