# Zephyr-TC MCP

Jira 티켓(`TVDEVTC-XXXX`)에서 webOS Zephyr 테스트케이스를 가져오는 MCP 서버.
TAS 파이프라인의 "TC 자동 수집" 앞단으로 쓴다.

## 동작 방식 — `get_tc(key)` 3중 폴백
1. **Zephyr 스텝 API** (Squad/Scale/커스텀 — `STEP_ENDPOINTS` 후보 순차 시도)
2. **첨부 파싱** (`tc_quality_*.html` 등 — 본문에 스텝/기대결과 포함)
3. **description**

→ 스텝 API가 막혀도 ②/③으로 항상 TC 텍스트를 확보한다.

## 설치 (jira MCP 와 동일한 방식 — 각자 자기 PC에서 로컬 실행)
이 MCP 는 **stdio** 로 동작한다. jira MCP 가 `uvx mcp-atlassian` + `JIRA_PERSONAL_TOKEN` 으로
각 사용자가 자기 PC에서 자기 토큰으로 돌리는 것과 똑같다. 호스팅 서버/IP 가 필요 없다.

**1) 코드 받기**
```sh
git clone <이 repo> ~/zephyr-tc-mcp
```
( `uv` 가 의존성을 자동 설치하므로 venv/pip 수동 작업 불필요. `uv` 없으면: `curl -LsSf https://astral.sh/uv/install.sh | sh` )

**2) 본인 Jira 토큰 발급**
`jira.lge.com → 프로필 → Personal Access Tokens` 에서 발급.

**3) Claude 에 등록 (본인 토큰을 env 로 — jira/hlm 과 같은 스타일)**
```sh
claude mcp add -s user zephyr-tc \
  -e JIRA_PAT=<본인_PAT> \
  -e JIRA_VERIFY_SSL=0 \
  -- uv run --no-project ~/zephyr-tc-mcp/server.py
```
> hlm 명령과 차이: 변수명이 `JIRA_PAT`(우리 서버용), 명령이 로컬 파일이라 경로 필요,
> `uv` 의 `--no-project` 플래그를 claude 가 삼키지 않도록 `--` 구분자 필수.
Claude Code 재시작 → `/mcp` 로 `zephyr-tc ✔ Connected` 확인.

> 토큰은 **각자 자기 `~/.claude.json`** 에만 저장된다(서버에 안 남음). 각 호출은 그 사용자 신분으로 Jira 를 본다.

### (선택) 호스팅 모드 — 내 PC 1대로 팀에 제공
`MCP_TRANSPORT=http ./run.sh` 로 `0.0.0.0:9001` 에 띄우고, 팀원은
`claude mcp add --transport http zephyr-tc http://<내IP>:9001/mcp --header "X-Jira-Token: <본인_PAT>"` 로 등록.
다만 내 PC가 꺼지면 팀 전체가 멈추므로 위 stdio 방식을 권장.

## 제공 도구
| 도구 | 용도 |
|---|---|
| `get_tc(key)` | TC 메타+스텝+첨부본문 (3중 폴백) |
| `get_tc_text(key)` | `/tas-parse` 입력용 평문 한 덩어리 |
| `search_tc(jql, limit)` | JQL로 TC 검색 |
| `list_attachments(key)` | 첨부 목록 |
| `discover_step_endpoint(key)` | **이 Jira에서 동작하는 스텝 API 경로 자동 탐색** |

## 스텝 API 경로 확정하기 (중요)
이 인스턴스가 ZAPI(Squad)인지 Scale인지 모르면, 먼저:
```
"TVDEVTC-74461 의 discover_step_endpoint 돌려줘"
```
→ baseline(serverInfo) 연결 확인 + 후보별 status/looks_like_steps 리포트.
동작하는 경로를 `server.py` 의 `STEP_ENDPOINTS` 맨 위로 올리면 끝.

가장 확실한 방법: 브라우저로 TC 열고 **F12 → Network(Fetch/XHR)** 에서 스텝 로드 요청 URL 확인 → 그 경로를 `STEP_ENDPOINTS` 에 추가.

## 사용 예
```
"TVDEVTC-74461 TC 가져와"                → get_tc
"TVDEVTC-74461 TC 텍스트로 줘"           → get_tc_text  (이걸 /tas-parse 에 투입)
"project=TVDEVTC component=com.webos.app.home 최근 TC 찾아"  → search_tc
```

## 다음 단계
`get_tc_text` 출력을 그대로 `/tas-parse` 에 넣으면:
**Zephyr-TC MCP(수집) → /tas-parse → /tas-appgen → /tas-tasgen → /tas-verify**
