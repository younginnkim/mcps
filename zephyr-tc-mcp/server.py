# /// script
# requires-python = ">=3.10"
# dependencies = ["fastmcp>=2.0", "httpx>=0.27", "beautifulsoup4>=4.12"]
# ///
"""
Zephyr-TC MCP — Jira 티켓(TVDEVTC-XXXX)에서 webOS Zephyr 테스트케이스를 가져오는 MCP 서버.

설계: get_tc(key) 는 2중 폴백으로 TC를 확보한다.
  ① Zephyr 스텝 API (ZAPI Squad — /rest/zapi/latest/teststep/{id})
  ② 첨부 파싱 (tc_quality_*.html 등 — 본문에 스텝/기대결과가 들어있음)
  ③ description

환경변수:
  JIRA_BASE   기본 https://jira.lge.com/issue  (jira.lge.com 은 컨텍스트 경로가 /issue!)
  JIRA_PAT    Jira Personal Access Token (필수) — jira MCP 의 JIRA_PERSONAL_TOKEN 과 동일 개념.
  JIRA_VERIFY_SSL  "0" 이면 인증서 검증 끔(사내 자가서명 대응). 기본 "1".
  MCP_TRANSPORT    기본 "stdio"(jira처럼 각자 로컬 실행). "http" 면 호스팅 모드.

실행(jira와 동일한 stdio 방식):
  claude mcp add zephyr-tc --env JIRA_PAT=xxxx -- uv run /abs/path/server.py
"""

import os
import sys
import re
import httpx
from bs4 import BeautifulSoup
from fastmcp import FastMCP
from fastmcp.server.dependencies import get_http_headers

# ⚠️ jira.lge.com 은 컨텍스트 경로가 /issue 다. REST 베이스에 반드시 포함!
JIRA_BASE = os.environ.get("JIRA_BASE", "https://jira.lge.com/issue").rstrip("/")
JIRA_PAT = os.environ.get("JIRA_PAT", "")
VERIFY_SSL = os.environ.get("JIRA_VERIFY_SSL", "1") != "0"
HOST = os.environ.get("HOST", "0.0.0.0")
PORT = int(os.environ.get("PORT", "9001"))

if not JIRA_PAT:
    # stdio 모드에서 stdout 으로 출력하면 MCP 프로토콜이 깨지므로 반드시 stderr 로.
    print("⚠️  JIRA_PAT 비어있음 — --env JIRA_PAT=... 로 본인 토큰을 넣으세요.", file=sys.stderr)

# Zephyr 스텝 API (ZAPI Squad). {id}=이슈 numeric id.
ZAPI_TESTSTEP = "/rest/zapi/latest/teststep/{id}"

mcp = FastMCP("zephyr-tc")


def _token() -> str:
    """Jira 토큰을 고른다.
    stdio 모드(jira처럼 각자 로컬): env JIRA_PAT 가 곧 그 사용자의 토큰.
    http 모드(호스팅): 요청 헤더 X-Jira-Token > Authorization: Bearer 로 요청자별 토큰.
    → 어느 모드든 토큰은 '실행/호출한 사용자' 것이 쓰인다."""
    try:
        h = get_http_headers()  # 키는 소문자로 정규화됨 (HTTP 컨텍스트에서만)
    except RuntimeError:
        h = {}  # stdio 등 HTTP 컨텍스트 밖
    tok = h.get("x-jira-token") or h.get("authorization", "").removeprefix("Bearer ").strip()
    return tok or JIRA_PAT


def _client() -> httpx.Client:
    tok = _token()
    headers = {"Authorization": f"Bearer {tok}", "Accept": "application/json"}
    return httpx.Client(headers=headers, timeout=30, verify=VERIFY_SSL, follow_redirects=True)


def _get_issue(c: httpx.Client, key: str) -> dict:
    r = c.get(
        f"{JIRA_BASE}/rest/api/2/issue/{key}",
        params={"fields": "summary,description,attachment,components,labels,status,assignee,issuetype"},
    )
    r.raise_for_status()
    return r.json()


def _parse_steps(payload: dict) -> list[dict]:
    """ZAPI(Squad) 응답을 공통 스텝 리스트로 정규화."""
    return [
        {"step": s.get("step"), "data": s.get("data"), "expected": s.get("result")}
        for s in payload.get("stepBeanCollection", []) or []
    ]


def _fetch_steps(c: httpx.Client, issue: dict) -> list[dict]:
    """ZAPI 스텝 API 호출. 200 + JSON + 스텝>0 일 때만 결과를 돌려준다.
    (안 되는 경로는 HTML 로그인 페이지를 200으로 주므로 content-type 검사가 필수)"""
    url = JIRA_BASE + ZAPI_TESTSTEP.format(id=issue["id"])
    try:
        r = c.get(url)
        if r.status_code == 200 and "application/json" in r.headers.get("content-type", ""):
            return _parse_steps(r.json())
    except Exception:
        pass
    return []


def _attachment_text(c: httpx.Client, fields: dict) -> tuple[str | None, str | None]:
    atts = fields.get("attachment") or []
    if not atts:
        return None, None
    # tc_quality_*.html 우선, 없으면 최신
    att = next((a for a in atts if a["filename"].lower().endswith((".html", ".htm", ".txt"))), atts[-1])
    try:
        raw = c.get(att["content"]).text
        text = BeautifulSoup(raw, "html.parser").get_text("\n", strip=True)
        text = re.sub(r"\n{3,}", "\n\n", text)
        return text, att["filename"]
    except Exception:
        return None, att["filename"]


@mcp.tool
def get_tc(key: str) -> dict:
    """Jira 티켓 키(예: TVDEVTC-74461)로 테스트케이스를 가져온다.
    스텝 API → 첨부(tc_quality 등) → description 순으로 폴백한다."""
    with _client() as c:
        issue = _get_issue(c, key)
        f = issue["fields"]
        out = {
            "key": key,
            "summary": f.get("summary"),
            "issue_type": (f.get("issuetype") or {}).get("name"),
            "status": (f.get("status") or {}).get("name"),
            "assignee": (f.get("assignee") or {}).get("displayName"),
            "components": [x["name"] for x in f.get("components", [])],
            "labels": f.get("labels", []),
            "description": f.get("description"),
            "attachments": [a["filename"] for a in f.get("attachment", [])],
            "steps": [],
            "raw_tc_text": None,
            "source": None,
        }
        # ① 스텝 API
        steps = _fetch_steps(c, issue)
        if steps:
            out["steps"], out["source"] = steps, "zephyr-api:zapi"
            return out
        # ② 첨부 파싱
        text, fname = _attachment_text(c, f)
        if text:
            out["raw_tc_text"], out["source"] = text, f"attachment:{fname}"
            return out
        # ③ description
        out["source"] = "description"
        return out


@mcp.tool
def get_tc_text(key: str) -> str:
    """get_tc 결과를 /tas-parse 입력용 평문 한 덩어리로 반환."""
    tc = get_tc(key)
    lines = [f"# {tc['key']} {tc.get('summary','')}",
             f"(source: {tc['source']}, components: {', '.join(tc['components'])})", ""]
    if tc["steps"]:
        for i, s in enumerate(tc["steps"], 1):
            lines.append(f"{i}. STEP: {s.get('step')}")
            if s.get("data"):
                lines.append(f"   DATA: {s['data']}")
            lines.append(f"   EXPECTED: {s.get('expected')}")
    elif tc.get("raw_tc_text"):
        lines.append(tc["raw_tc_text"])
    elif tc.get("description"):
        lines.append(tc["description"])
    return "\n".join(lines)


if __name__ == "__main__":
    transport = os.environ.get("MCP_TRANSPORT", "stdio")
    if transport == "http":
        mcp.run(transport="http", host=HOST, port=PORT)  # 호스팅 모드(선택)
    else:
        mcp.run()  # 기본: stdio — jira처럼 각 사용자 PC에서 로컬 실행
