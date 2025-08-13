# ===== Stage 1: build web UI from submodule =====
FROM node:20-alpine AS webui
WORKDIR /webui
# Копируем только webui из твоего репо aw-server
COPY aw-server/aw-webui/ ./
ARG BUILD_SHA=nogit
ENV GIT_SHA=$BUILD_SHA
RUN npm ci && npm run build

# ===== Stage 2: python + aw-server =====
FROM python:3.11-slim

ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    XDG_DATA_HOME=/var/lib/aw

RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential libpq-dev curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN python -m pip install -U pip wheel \
 && pip install gunicorn psycopg2-binary

# Копируем твои форки
COPY aw-core/   /app/aw-core/
COPY aw-server/ /app/aw-server/

# Кладём собранный webui в статику сервера (ПРАВИЛЬНЫЙ ПОРЯДОК)
COPY --from=webui /webui/dist/ /app/aw-server/aw_server/static/

# Ставим пакеты (editable)
RUN pip install -e /app/aw-core \
 && pip install -e /app/aw-server

EXPOSE 5600
HEALTHCHECK --interval=15s --timeout=3s --retries=10 \
  CMD curl -fsS http://127.0.0.1:5600/api/0/info >/dev/null || exit 1

ENV GUNICORN_WORKERS=4 \
    GUNICORN_TIMEOUT=60

# Если wsgi.py лежит в корне репо aw-server:
WORKDIR /app/aw-server
CMD ["bash","-lc","exec gunicorn --workers ${GUNICORN_WORKERS} --timeout ${GUNICORN_TIMEOUT} --bind 0.0.0.0:5600 wsgi:app"]

# Если у тебя wsgi по пути aw-server/aw_server/wsgi.py — используй:
# CMD ["bash","-lc","exec gunicorn --workers ${GUNICORN_WORKERS} --timeout ${GUNICORN_TIMEOUT} --bind 0.0.0.0:5600 aw_server.wsgi:app"]
