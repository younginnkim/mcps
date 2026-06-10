#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

# 1) venv
if [ ! -d .venv ]; then
  python3 -m venv .venv
  ./.venv/bin/pip install -q -r requirements.txt
fi

# 2) 환경변수 (.env 있으면 로드)
[ -f .env ] && source .env

if [ -z "${JIRA_PAT:-}" ]; then
  echo "JIRA_PAT 이 비어있습니다. .env 를 채우거나 export JIRA_PAT=... 하세요." >&2
  exit 1
fi

# 3) 실행
exec ./.venv/bin/python server.py
