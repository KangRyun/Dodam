"""프롬프트 파일 로딩·버전 관리 중앙화 (S15P11B209-595).

각 클라이언트(llm_client·vlm_client·report_client·question_service)가 흩어져 관리하던
프롬프트 로딩·버전 문자열을 한곳으로 모은다. 분석·질문 결과에 promptVersion을 저장해
"어떤 프롬프트로 뽑힌 결과인지" 재현·추적할 수 있게 한다.

버전 = 수동 semver + 내용 해시(예: "1.1.0+ab12cd34").
- semver: 프롬프트를 의미 있게 바꿀 때 _PROMPT_SEMVER에서 올린다.
- 내용 해시: 파일 내용에서 자동 계산한다. semver를 깜빡 안 올려도 내용이 바뀌면
  해시가 달라져 결과 추적이 끊기지 않는다(이중 안전장치).

파일명은 ai/prompts/<name>.txt. torch·GMS 의존성이 없어 어디서든 import된다.
"""

from __future__ import annotations

import hashlib
from functools import lru_cache
from pathlib import Path

PROMPT_DIR = Path(__file__).parent / "prompts"

# 프롬프트 파일별 의미 버전(semver). 프롬프트를 의미 있게 바꾸면 여기 값을 올린다.
# ⚠️ 키를 추가/삭제하면 verify_prompt_files()가 파일과의 불일치를 잡는다.
_PROMPT_SEMVER: dict[str, str] = {
    "first_question": "1.1.0",
    "conversations": "1.1.0",
    "guardrails": "1.0.0",
    "drawing_description": "1.0.0",
    "report": "1.1.0",  # S15P11B209-600: 관찰 사실 ↔ AI 해석 근거 분리 규칙 추가
}

_UNKNOWN_SEMVER = "0.0.0"


@lru_cache(maxsize=None)
def load(name: str) -> str:
    """ai/prompts/<name>.txt 를 읽어 캐시한다(서버 기동 중 파일은 안 바뀐다고 가정)."""
    return (PROMPT_DIR / f"{name}.txt").read_text(encoding="utf-8").strip()


@lru_cache(maxsize=None)
def content_hash(name: str) -> str:
    """프롬프트 내용의 짧은 SHA-256 해시(앞 8자리). 내용이 바뀌면 값이 달라진다."""
    return hashlib.sha256(load(name).encode("utf-8")).hexdigest()[:8]


def version(name: str) -> str:
    """단일 프롬프트의 버전 문자열: "<semver>+<content_hash>"."""
    semver = _PROMPT_SEMVER.get(name, _UNKNOWN_SEMVER)
    return f"{semver}+{content_hash(name)}"


def composite_version(*names: str) -> str:
    """여러 프롬프트를 함께 쓰는 경로(예: 질문 생성)의 통합 버전.

    "name@<version>" 을 프롬프트 이름순으로 정렬해 이어붙인다 — 어떤 파일 조합·내용으로
    생성됐는지 한 문자열로 재현 가능하게 한다.
    """
    return ";".join(f"{name}@{version(name)}" for name in sorted(names))


def verify_prompt_files() -> list[str]:
    """semver 표와 실제 프롬프트 파일의 불일치를 돌려준다(빈 리스트면 일치).

    - 표에 있는데 파일이 없으면 "<name>: missing file"
    - prompts 폴더에 있는데 표에 없으면 "<name>: unversioned"
    스모크/기동 점검에서 호출해 프롬프트 추가 시 버전 등록 누락을 즉시 잡는다.
    """
    problems: list[str] = []
    for name in _PROMPT_SEMVER:
        if not (PROMPT_DIR / f"{name}.txt").exists():
            problems.append(f"{name}: missing file")
    for path in PROMPT_DIR.glob("*.txt"):
        if path.stem not in _PROMPT_SEMVER:
            problems.append(f"{path.stem}: unversioned")
    return problems
