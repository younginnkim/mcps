#!/usr/bin/env bash
# Docker 없이 서버에 직접 띄울 때 사용하는 스크립트.
# (Docker로 띄울 거면 docker-compose up -d 사용)
set -euo pipefail
cd "$(dirname "$0")"

export PORT="${PORT:-8000}"

echo "[run.sh] installing deps..."
npm ci

echo "[run.sh] building..."
npm run build

echo "[run.sh] starting on port ${PORT}..."
exec node build/index.js
