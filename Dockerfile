# ===== Stage 1: build web UI from aw-server/aw-webui =====
FROM node:20-alpine AS webui
WORKDIR /webui
# копируем package.json/lock для кэширования npm ci
COPY aw-server/aw-webui/package*.json ./
ENV NODE_ENV=production
ARG BUILD_SHA=nogit
ENV GIT_SHA=$BUILD_SHA
RUN npm ci --include=dev
# копируем остальное и собираем
COPY aw-server/aw-webui/ ./
RUN npm run build

# ===== Stage 2: python + aw-server =====
FROM python:3.11-slim

ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 

# системные зависимости для сборки и psycopg2
RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential libpq-dev libffi-dev curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# отдельный непривилегированный пользователь
# RUN addgroup --system aw && adduser --system --home /var/lib/aw --ingroup aw aw

# # сразу после ENV PYTHONUNBUFFERED... добавь/исправь:
# ENV HOME=/var/lib/aw \
#     XDG_DATA_HOME=/var/lib/aw \
#     XDG_CONFIG_HOME=/var/lib/aw/.config \
#     XDG_CACHE_HOME=/var/lib/aw/.cache

# # гарантируем существование и права
# RUN mkdir -p /var/lib/aw /var/lib/aw/.config /var/lib/aw/.cache \
#  && chown -R aw:aw /var/lib/aw


WORKDIR /app

# базовые питон-зависимости
RUN python -m pip install -U pip wheel \
 && pip install --no-cache-dir gunicorn psycopg2-binary
# если нужна асинхронщина — раскомментируй:
# RUN pip install --no-cache-dir gevent

# копируем исходники
COPY aw-core/   /app/aw-core/
COPY aw-server/ /app/aw-server/

# кладём собранный веб-интерфейс в статику aw-server
COPY --from=webui /webui/dist/ /app/aw-server/aw_server/static/

# устанавливаем пакеты (editable)
RUN pip install --no-cache-dir -e /app/aw-core \
 && pip install --no-cache-dir -e /app/aw-server



EXPOSE 5600

HEALTHCHECK --interval=15s --timeout=3s --retries=10 \
  CMD curl -fsS http://127.0.0.1:5600/api/0/info >/dev/null || exit 1

# дефолтные переменные для gunicorn (переопределяются в compose)
ENV GUNICORN_WORKERS=4 \
    GUNICORN_TIMEOUT=120 \
    GUNICORN_WORKER_CLASS=sync \
    GUNICORN_MAX_REQUESTS=1000 \
    GUNICORN_MAX_REQUESTS_JITTER=100 \
    AW_HOST=0.0.0.0

#USER aw
WORKDIR /app/aw-server

# предполагается фабрика create_app() в aw-server/wsgi.py.
# Если у тебя экспортируется готовый app — замени на "wsgi:app"
CMD ["bash","-lc","exec gunicorn 'wsgi:create_app()' \
    --bind 0.0.0.0:5600 \
    --workers ${GUNICORN_WORKERS} \
    --threads ${GUNICORN_THREADS} \
    --timeout ${GUNICORN_TIMEOUT} \
    --worker-class ${GUNICORN_WORKER_CLASS} \
    --max-requests ${GUNICORN_MAX_REQUESTS} \
    --max-requests-jitter ${GUNICORN_MAX_REQUESTS_JITTER} \
    --preload \
    --access-logfile -"]
