#!/bin/bash
# elemental-ui-migration CasePack(case-02313548) 내용 업데이트 스크립트
# 기존 stdio 기반 안내를 HTTP MCP 서버(http://10.157.70.184:8000/mcp) 기준으로 갱신한다.
#
# 사용법: ./update-casepack.sh <username> <password>

set -euo pipefail

HUB_URL="http://10.157.71.52:5000"
CASE_ID="case-02313548"
MCP_URL="http://10.157.70.184:8000/mcp"
USERNAME="${1:?Usage: $0 <username> <password>}"
PASSWORD="${2:?Usage: $0 <username> <password>}"
COOKIE_JAR=$(mktemp)
PAYLOAD=$(mktemp)
trap 'rm -f "$COOKIE_JAR" "$PAYLOAD"' EXIT

echo "=== ASF MCP Hub CasePack 업데이트 ==="
echo "서버:     $HUB_URL"
echo "케이스:   $CASE_ID"
echo "MCP URL:  $MCP_URL"
echo "사용자:   $USERNAME"
echo ""

# 1) 로그인 (JSON API)
echo "[1/3] 로그인 중..."
LOGIN_RESP=$(curl -s -c "$COOKIE_JAR" -X POST "$HUB_URL/api/v1/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"$USERNAME\",\"password\":\"$PASSWORD\"}" \
  -w "\n%{http_code}")

HTTP_CODE=$(echo "$LOGIN_RESP" | tail -1)
LOGIN_BODY=$(echo "$LOGIN_RESP" | sed '$d')

if [ "$HTTP_CODE" != "200" ]; then
  echo "로그인 실패 (HTTP $HTTP_CODE). 계정 정보를 확인하세요."
  echo "$LOGIN_BODY"
  exit 1
fi
echo "로그인 성공!"

# 2) 업데이트 페이로드 생성 (Python으로 JSON 안전하게 구성 — 이스케이프 불필요)
echo "[2/3] 페이로드 생성 중..."
python3 - "$PAYLOAD" "$MCP_URL" <<'PYEOF'
import json, sys

payload_path = sys.argv[1]
mcp_url = sys.argv[2]

guide_document = f"""# elemental-ui-migration-skill 셋업 가이드

## 개요

Flutter 앱 코드를 Plover(`package:plover`) / Elutter(`package:elutter`)에서 Elemental UI(`package:elemental`)로
자동 마이그레이션하는 Claude Code 스킬 + 원격 HTTP MCP 서버입니다.

- **Skill**: `/migrate-from-plover [dart_file_or_directory]`
- **MCP 서버**: `elemental-ui-migration-mcp` (Node.js, Streamable HTTP — Docker로 원격 운영)
- **MCP 도구**: `getWidgetDetail(name)` — Plover 위젯의 마이그레이션 상세 정보
  (target 이름, breaking change, deprecated 여부, paramChanges) 반환

> ⚠️ 이전 버전은 로컬 stdio 방식이었으나, 현재는 **HTTP 서버로 원격 운영**됩니다.
> 클라이언트는 빌드/설치 없이 URL 한 줄만 등록하면 바로 사용 가능합니다.

---

## 1. 클라이언트 설정 (사용자용)

### 방법 1: CLI 명령어 (추천)

```bash
claude mcp add -s user -t http elemental-ui-migration-mcp {mcp_url}
```

> **옵션 설명:**
> - `-s user`: 사용자 전역 설정 (모든 프로젝트에서 사용 가능)
> - `-t http`: HTTP 전송 방식 (Streamable HTTP)
> - `elemental-ui-migration-mcp`: MCP 서버 이름
> - `{mcp_url}`: MCP 서버 URL

설정 확인:
```bash
claude mcp list
```

삭제하려면:
```bash
claude mcp remove -s user elemental-ui-migration-mcp
```

### 방법 2: 설정 파일 직접 편집 (`~/.claude.json`)

```json
{{
  "mcpServers": {{
    "elemental-ui-migration-mcp": {{
      "type": "http",
      "url": "{mcp_url}"
    }}
  }}
}}
```

### 2-1. Skill 설치

MCP 도구만으로는 마이그레이션이 실행되지 않습니다. 슬래시 커맨드(`/migrate-from-plover`)를
제공하는 스킬을 함께 설치해야 합니다.

```bash
# 1) 저장소 클론
git clone https://github.com/younginnkim/elemental-ui-migration-skill.git

# 2) 스킬 정의를 Claude Code 스킬 디렉토리에 링크 (또는 복사)
ln -s "$(pwd)/elemental-ui-migration-skill/skills/migrate-from-plover" \\
  ~/.claude/skills/migrate-from-plover
```

### 연결 확인

Claude Code 실행 후:

```
# 서버 연결 상태 확인
/mcp
```

정상 연결 시:
```
elemental-ui-migration-mcp: connected
```

마이그레이션할 Flutter 프로젝트에서 `/migrate-from-plover` 자동완성이 노출되면 정상.

---

## 2. 사용법

```
/migrate-from-plover lib/views/home_view.dart   # 단일 파일
/migrate-from-plover lib/views/                  # 디렉토리
/migrate-from-plover lib/                        # lib 전체
/migrate-from-plover                             # IDE 열린 파일 또는 lib/ fallback
```

### 동작 흐름 (5단계)

| Step | 내용 |
|---|---|
| 1 | `pubspec.yaml`에서 `plover` 제거 + `elemental` 추가 → `flutter pub get` → `flutter analyze --format=machine`으로 Plover 사용 위치 정확히 수집 |
| 2 | import 교체(`package:plover/plover.dart` → `package:elemental/widgets.dart`), 위젯/enum 이름 교체, breaking change 파라미터 처리, 제거된 named parameter 자동 주석 + `// TODO(migrate)` 마킹 |
| 3 | App Foundation: `runApp(...)` → `EAppMain.run(EApp(child: ...))` 또는 `EApp` 삽입, `MaterialApp` 파라미터를 `EApp`으로 이동 |
| 4 | TV 포커스 규칙 검증 (focus-passthrough, no-nested-efocusable, delegate-focus-events, popup-focus-restore) |
| 5 | 리포트(수정 파일 수, 교체 식별자 수, 잔여 TODO 수, 잔여 UNDEFINED_NAMED_PARAMETER 수) |

---

## 3. MCP 도구

### `getWidgetDetail(name)`

Plover 위젯/클래스 1개의 마이그레이션 상세 정보를 반환합니다.
스킬이 Step 1~4에서 컴파일러가 식별한 unique 식별자별로 호출합니다.

**입력:**
- `name` (string) — Plover 위젯/클래스 이름 (예: `WButton`, `WVirtualList`, `WSpinner`)

**반환:**
```json
{{
  "plover": "WButton",
  "elutter": "EButton",
  "breakingChange": true,
  "deprecated": false,
  "deprecatedNote": null,
  "notes": "...",
  "paramChanges": {{
    "removed": ["..."],
    "renamed": {{ "oldName": "newName" }},
    "added": ["..."],
    "notes": "..."
  }}
}}
```

매핑이 없으면 `error`와 이름이 유사한 후보(`suggestions`)를 반환합니다.
매핑 데이터는 `elemental-ui-migration-mcp/src/mapping.json`에 정의되어 있고, 빌드 시 `build/`로 복사됩니다.

---

## 4. 트러블슈팅

| 증상 | 해결 |
|---|---|
| `elemental-ui-migration-mcp: failed` / Not Connected | 서버 URL 확인, `curl http://10.157.70.184:8000/health`로 응답 확인 |
| MCP 도구가 안 보임 | Claude Code에서 `/mcp` 입력하여 재연결 |
| `/migrate-from-plover` 자동완성에 안 뜸 | `skills/migrate-from-plover/SKILL.md`가 `~/.claude/skills/`에 링크/복사됐는지 확인 |
| `No mapping found for "WXxx"` | `mapping.json`에 신규 위젯 누락 — PR로 추가 필요 |
| version solving failed | 스킬이 `elemental` 요구 버전을 5회 재시도. 5회 후에도 실패하면 `pubspec.yaml` 수동 조정 |
| 잔여 `UNDEFINED_NAMED_PARAMETER` > 0 | Step 2-5의 자동 주석 처리가 누락된 케이스 — 해당 라인 수동 검토 |
| 연결 타임아웃 | 방화벽에서 8000 포트가 열려 있는지 확인 |

---

## 5. 저장소

- **GitHub**: https://github.com/younginnkim/elemental-ui-migration-skill
- **Skill 정의**: `skills/migrate-from-plover/SKILL.md`
- **MCP 서버**: `elemental-ui-migration-mcp/` (TypeScript, `@modelcontextprotocol/sdk` 기반)
- **매핑 데이터**: `elemental-ui-migration-mcp/src/mapping.json`
"""

payload = {
    "title": "Elemental UI Migration Skill — Plover 위젯을 Elemental UI로 자동 마이그레이션",
    "summary": (
        "Flutter 앱 코드를 Plover(package:plover)에서 Elemental UI(package:elemental)로 "
        "자동 마이그레이션하는 Claude Code 스킬 + HTTP MCP 서버. /migrate-from-plover 슬래시 "
        "커맨드로 실행하면 컴파일러 에러를 기반으로 import·위젯·enum·breaking change 파라미터를 "
        "자동 교체하고, deprecated 위젯과 EApp/EAppMain 진입점, TV 포커스 규칙까지 처리합니다. "
        "MCP 서버는 원격 HTTP(http://10.157.70.184:8000/mcp)로 운영되어 클라이언트는 URL 한 줄만 "
        "등록하면 바로 사용 가능합니다."
    ),
    "platform": "webOS",
    "problem_statement": (
        "Plover 위젯 라이브러리는 Elemental UI(elemental)로 통합·재편되면서 위젯 이름 변경, "
        "enum 이름 변경, 파라미터 제거/이름변경 같은 breaking change가 다수 발생했습니다. 수동으로 "
        "마이그레이션할 경우: (1) 어느 위젯이 어떤 위젯으로 매핑되는지 매번 문서를 뒤져야 하고, "
        "(2) deprecated 위젯의 대체 위젯 파라미터까지 매핑해야 하며, (3) 제거된 named parameter는 "
        "컴파일 에러로만 드러나서 누락되기 쉽고, (4) 앱 진입점(runApp)과 TV 포커스 규칙은 Plover에는 "
        "없던 새 패턴이라 별도 검토가 필요합니다. 프로젝트당 수십~수백 파일에 적용해야 하므로 시간 "
        "소모가 매우 큽니다."
    ),
    "solution_approach": (
        "Claude Code 스킬(/migrate-from-plover) + 원격 HTTP MCP 서버 조합으로 마이그레이션을 "
        "자동화합니다. 핵심 아이디어: (1) 컴파일러(flutter analyze --format=machine) 출력을 단일 "
        "진실 공급원으로 사용해 Plover 사용 위치(URI_DOES_NOT_EXIST, UNDEFINED_CLASS, "
        "UNDEFINED_IDENTIFIER, UNDEFINED_NAMED_PARAMETER)를 정확히 식별. (2) MCP 서버의 "
        "getWidgetDetail(name) 도구가 위젯별 target 이름·breaking change·deprecated 여부·"
        "deprecatedNote·paramChanges(removed/renamed/added)를 반환하는 SSOT. (3) 스킬은 5단계로 "
        "구성: Plover 사용 감지 → 위젯/import/enum 교체 + breaking change 파라미터 처리 → "
        "EApp/EAppMain 진입점 변환 → TV 포커스 규칙 검증 → 리포트. (4) 자동 매핑이 불가능한 경우 "
        "// TODO(migrate): 주석으로 표시해 수동 검토 지점을 명시. MCP 서버는 Docker로 빌드해 "
        "HTTP(Streamable HTTP)로 원격 운영하며 클라이언트는 URL만 등록합니다."
    ),
    "tags": ["MCP", "flutter", "migration", "plover", "elemental-ui", "claude-code", "docker", "http"],
    "keywords": ["마이그레이션", "플로버", "엘리멘탈", "위젯", "flutter", "getWidgetDetail",
                 "breaking-change", "스킬", "MCP서버", "포커스"],
    "author": "younginn.kim",
    "team": "SW Platform",
    "guide_document": guide_document,
    "git_references": [
        {
            "repo_url": "https://github.com/younginnkim/elemental-ui-migration-skill.git",
            "branch": "main",
        }
    ],
}

with open(payload_path, "w", encoding="utf-8") as f:
    json.dump(payload, f, ensure_ascii=False)

print(f"  페이로드 작성 완료 ({len(guide_document)} chars guide_document)")
PYEOF

# 3) CasePack 업데이트 (PUT)
echo "[3/3] CasePack 업데이트 중..."
RESPONSE=$(curl -s -b "$COOKIE_JAR" -X PUT "$HUB_URL/api/v1/casepacks/$CASE_ID" \
  -H "Content-Type: application/json" \
  --data @"$PAYLOAD" \
  -w "\n%{http_code}")

UP_CODE=$(echo "$RESPONSE" | tail -1)
UP_BODY=$(echo "$RESPONSE" | sed '$d')

echo "$UP_BODY" | python3 -m json.tool 2>/dev/null || echo "$UP_BODY"

if [ "$UP_CODE" = "200" ]; then
  echo ""
  echo "업데이트 완료!"
  echo "  CasePack ID: $CASE_ID"
  echo "  URL: $HUB_URL/casepacks/$CASE_ID"
else
  echo ""
  echo "업데이트 실패 (HTTP $UP_CODE). 응답을 확인하세요."
  echo "  (엔드포인트가 PATCH일 수 있습니다. 200이 아니면 -X PUT 을 -X PATCH 로 바꿔 재시도)"
  exit 1
fi
