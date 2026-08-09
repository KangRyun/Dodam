"""생성된 답변 사후 검사 — LLM 호출 없이 규칙(정규식·키워드)만으로 검증·정화한다.

프롬프트의 가드레일은 '부탁' 수준이라 모델이 어길 수 있다. 이 모듈은 그 출력을
한 번 더 걸러 준다. 두 종류로 나눠 다룬다:

  1) 정화 가능한 형식 문제(sanitize)
     - TTS로 그대로 읽히는 이모지·별표·괄호 같은 기호 → 조용히 제거.
  2) 심각한 내용 위반(fallback)
     - 진단·심리해석·검사 채점 표현 등 → 답변을 버리고 안전한 기본 질문으로 교체.

LLM을 다시 부르지 않으므로 지연·비용이 없고 결정적(deterministic)이다.
대신 의미까지 이해하진 못하니 '완벽한 필터'가 아니라 '명백한 사고 방지'용이다.

가드레일: 아이 발화·모델 원문은 로그로 남기지 않는다 — 위반 '코드'만 남긴다.
"""

from __future__ import annotations

import logging
import re

logger = logging.getLogger(__name__)

# 내용 위반 시 대체할 안전한 기본 질문(맥락 없이도 무해하게 성립).
FALLBACK_QUESTION = "이 그림에서 제일 마음에 드는 건 뭐야?"

# ── 1) 형식 정화: TTS로 읽으면 곤란한 것들 ──────────────────────

# 이모지·기호류(대략적 범위). TTS가 "별", "괄호 열고" 식으로 읽지 않도록 제거.
_EMOJI = re.compile(
    "["
    "\U0001F300-\U0001FAFF"  # 그림문자·기호·픽토그램
    "\U00002600-\U000027BF"  # 기타 기호·딩뱃
    "\U0001F1E6-\U0001F1FF"  # 국기
    "\U0000FE00-\U0000FE0F"  # 변이 선택자
    "\U00002190-\U000021FF"  # 화살표
    "]+",
    flags=re.UNICODE,
)

# 마크다운·장식 기호. 문장 뜻은 안 바꾸고 기호만 턴다.
_MARKUP = re.compile(r"[*_#`~>|\[\]{}()<>]")

# 여러 공백/줄바꿈 → 한 칸으로.
_WS = re.compile(r"\s+")


def sanitize(text: str) -> str:
    """읽기용으로 안전하게 정화한다(뜻은 보존, 장식 기호만 제거)."""
    text = _EMOJI.sub("", text)
    text = _MARKUP.sub("", text)
    text = _WS.sub(" ", text)
    return text.strip()


# ── 2) 내용 위반: 있으면 답변을 버리고 fallback ────────────────

# 진단·심리해석·검사 채점을 시사하는 표현. 아동에게 절대 나가면 안 되는 부류.
# (부분일치. 아동 대화 답변에 자연스럽게 나올 리 없는 단어 위주로 최소화.)
_FORBIDDEN = [
    r"진단",
    r"심리\s*(검사|상태|분석)",
    r"정서\s*(상태|불안|안정)",
    r"성격\s*(유형|특성|검사)",
    r"성향",
    r"무의식",
    r"트라우마",
    r"우울|불안장애",
    r"HTP|에이치티피",
    r"검사\s*결과",
    r"채점|점수",
    r"이\s*그림은\s*.{0,10}(의미|상징|나타)",  # "이 그림은 ~를 의미해/상징해"
    r"(이런|이러한)\s*아이는",                 # "이런 아이는 ~"
]
_FORBIDDEN_RE = [re.compile(p) for p in _FORBIDDEN]


def find_violations(text: str) -> list[str]:
    """내용 위반 패턴을 찾아 매칭된 패턴 문자열 목록을 반환한다(없으면 빈 목록).

    반환값은 '패턴'이지 원문 조각이 아니다 — 로그에 남겨도 아이 발화가 새지 않는다.
    """
    return [rx.pattern for rx in _FORBIDDEN_RE if rx.search(text)]


# ── 통합 진입점 ─────────────────────────────────────────────────


def enforce(text: str, *, fallback: str = FALLBACK_QUESTION) -> str:
    """생성 답변을 검사·정화해 안전한 문자열을 돌려준다(LLM 호출 없음).

    순서:
      1) 형식 정화(이모지·기호 제거).
      2) 내용 위반이 있으면 정화본을 버리고 fallback으로 교체.
      3) 정화 후 빈 문자열이 되면(기호뿐이었으면) fallback.

    Args:
        text: 모델이 생성한 원본 답변.
        fallback: 위반/공백 시 대체할 안전한 문장.

    Returns:
        아이에게 내보내도 되는 최종 문자열.
    """
    cleaned = sanitize(text)

    violations = find_violations(cleaned)
    if violations:
        # ⚠️ 원문·정화본은 남기지 않는다 — 어떤 규칙에 걸렸는지 '패턴'만.
        logger.warning("답변 가드레일 위반으로 fallback 사용: %s", violations)
        return fallback

    if not cleaned:
        logger.warning("정화 후 빈 답변 — fallback 사용")
        return fallback

    return cleaned


if __name__ == "__main__":
    # 스모크 테스트:  cd ai && python answer_check.py
    logging.basicConfig(level=logging.INFO)

    samples = [
        "우와, 멋진 집이네! 누가 살고 있어? 😊",          # 이모지 제거만
        "이 그림은 불안을 의미해요.",                       # 내용 위반 → fallback
        "이런 아이는 외로운 성향이 있어요.",                 # 내용 위반 → fallback
        "**멋지다!** (집 그림) 누구랑 살아?",               # 기호 제거만
        "🎨🌟",                                            # 정화 후 빈 문자열 → fallback
    ]
    for s in samples:
        print(f"IN : {s}")
        print(f"OUT: {enforce(s)}")
        print("-" * 40)
