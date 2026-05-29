#!/usr/bin/env bash
# MCP 매핑/소스를 수정한 뒤 Docker로 재배포 + 검증하는 스크립트.
#
# 사용법:
#   ./deploy.sh            # 빌드 검증 + 재배포 + 스모크 테스트
#   ./deploy.sh --no-test  # 스모크 테스트 생략
#   PORT=8000 ./deploy.sh  # 포트 지정 (기본 8000)
#
# 동작:
#   1) TypeScript 컴파일로 소스 에러 선검출 (도커 빌드 전에 빠르게 실패)
#   2) docker compose up -d --build  (이미지 재빌드 + 컨테이너 교체)
#   3) /health 가 healthy 될 때까지 대기
#   4) initialize / tools/list / tools/call 스모크 테스트
set -euo pipefail
cd "$(dirname "$0")"

PORT="${PORT:-8000}"
RUN_TEST=1
[[ "${1:-}" == "--no-test" ]] && RUN_TEST=0

step() { printf '\n\033[1;36m▶ %s\033[0m\n' "$1"; }
ok()   { printf '\033[1;32m✔ %s\033[0m\n' "$1"; }
die()  { printf '\033[1;31mX %s\033[0m\n' "$1" >&2; exit 1; }

# ── 1. 소스 컴파일 검증 (도커 빌드보다 빠르게 실패) ──────────────
step "TypeScript 컴파일 검증"
if [[ ! -d node_modules ]]; then
  echo "  node_modules 없음 → npm ci"
  npm ci
fi
npm run build >/dev/null || die "TypeScript 컴파일 실패 — 소스를 고친 뒤 다시 실행하세요."
ok "컴파일 통과"

# ── 2. 도커 재배포 ──────────────────────────────────────────────
step "Docker 재배포 (build + up)"
docker compose up -d --build
ok "컨테이너 기동"

# ── 3. 헬스체크 대기 ────────────────────────────────────────────
step "헬스체크 대기 (http://localhost:${PORT}/health)"
for i in $(seq 1 30); do
  if curl -fsS --max-time 2 "http://localhost:${PORT}/health" >/dev/null 2>&1; then
    ok "서버 응답 OK"
    break
  fi
  [[ $i -eq 30 ]] && die "30초 내 헬스체크 실패 — 'docker compose logs' 확인"
  sleep 1
done

# ── 4. 스모크 테스트 ────────────────────────────────────────────
if [[ $RUN_TEST -eq 1 ]]; then
  step "MCP 프로토콜 스모크 테스트"
  H=(-H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream')
  url="http://localhost:${PORT}/mcp"
  # SSE 응답에서 data 라인만 추출하는 헬퍼
  call() { curl -fsS "${H[@]}" -X POST "$url" -d "$1" | sed -n 's/^data: //p'; }

  call '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' \
    | python3 -c "import sys,json;d=json.load(sys.stdin);print('  tools:',[t['name'] for t in d['result']['tools']])" \
    || die "tools/list 실패"

  call '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"getWidgetDetail","arguments":{"name":"WButton"}}}' \
    | python3 -c "import sys,json;d=json.load(sys.stdin);t=json.loads(d['result']['content'][0]['text']);print('  getWidgetDetail(WButton) ->',t['elutter'],'| breaking:',t['breakingChange'])" \
    || die "tools/call 실패"
  ok "스모크 테스트 통과"
fi

printf '\n\033[1;32m=== 배포 완료 ===\033[0m\n'
docker compose ps
