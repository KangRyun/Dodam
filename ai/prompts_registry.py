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
    # 대화 프롬프트도 활동 유형별로 갈라진다(S15P11B209-786) — 대화의 '목적'이 다르다:
    #   HTP는 그림 자체가 궁금해 그림 안에서 좁혀 가고, 그림일기는 그림을 소재 삼아
    #   그날 일·아이 마음으로 넓혀 간다. 한 문장으로 두 목적을 시키면 어느 쪽도 안 된다.
    # 구 first_question(1.3.0)·conversations(1.4.0)를 갈라 만든 것이라 2.0.0에서 시작한다.
    # 2.1.0(HTP만): 첫 질문이 12/12 "오늘은 뭘 그렸어?"로 고정되던 것을 고쳤다(808 F-1).
    #   완성문을 예시로 두 번 적어 둔 것이 원인 — 모델이 규칙을 해석하는 대신 눈앞의 문장을
    #   복사했다. 세부가 있으면 반드시 그것을 묻게 하고, 질문 뱅크를 방향 힌트로 참조시킨다.
    "first_question_htp": "2.1.0",
    "first_question_diary": "2.0.0",
    "conversations_htp": "2.1.0",
    "conversations_diary": "2.0.0",
    # HTP 표준 사후질문(PDI)을 아동용으로 포장한 주제별 질문 뱅크(S15P11B209-811).
    # 현재 주제 구획 하나만 싣는다 — 셋을 다 실으면 주제 이탈(709 계열)이 다시 열린다.
    "htp_question_bank": "1.0.0",
    # 공유 규칙(이름·분석결과 취급·출력 형식)은 변형 뒤에 이어붙는다. 문장 수·길이는
    # 여기서 정하지 않고 conversation_tone에 위임한다(구 프롬프트의 "한 문장만"이
    # UPPER_ELEMENTARY "한두 문장"과 어긋나던 것을 소유자를 하나로 만들어 없앴다).
    "conversation_common": "1.0.0",
    # 구 question_service._DIFFICULTY_RULES를 프롬프트 파일로 옮긴 것(버전 추적·draft 경로 반영).
    #   구 PRESCHOOL "10자 안팎"은 대화 프롬프트의 "반응한 다음 질문을 이어줘"와 동시에
    #   만족할 수 없어, 반응/질문 몫을 나눠 "두 문장 이내"로 고쳤다.
    "conversation_tone": "1.0.0",
    # 1.1.0: "중립적으로 반응"(대화 프롬프트의 '따뜻하게 반응'과 모순) 제거,
    #   길이 규칙 제거(각 프롬프트·난이도 블록이 소유), 입력 취급·개인정보 규칙 추가.
    # 1.2.0(S15P11B209-811): 금지 규칙의 '적용 대상'을 아이 본인으로 좁혔다. 평가·감정·슬픈
    #   주제 금지가 그림 속 인물에까지 걸려 HTP 사후질문(PDI)을 통째로 막고 있었다.
    #   진단·점수화·개인정보·외부 접촉 금지는 예외 없는 절대 규칙으로 그대로 둔다.
    "guardrails": "1.2.0",
    # 그림 서술은 활동 유형별로 갈라진다 — HTP는 탐지 목록에 고정, 그림일기는 탐지를
    # 힌트로만 쓴다(sketch 가중치가 자유 그림을 자주 놓쳐 목록 고정이 서술을 죽였다).
    "drawing_description_htp": "1.0.0",
    "drawing_description_diary": "1.0.0",
    # 리포트도 활동 유형별로 갈라진다 — 근거 블록 구성이 다르고(주제별 vs 단일),
    # RAG 근거는 HTP 경로에만 실린다. 공통 규칙·JSON 스키마는 report_common이 소유한다.
    # S15P11B209-601: 진단 표현 금지 강화·한계 고지·후속 질문 목적 명시(구 report 1.2.0 계승).
    "report_common": "1.3.0",
    "report_htp": "1.3.0",
    "report_diary": "1.3.0",
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
