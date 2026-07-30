"""아동 발화의 프롬프트 인젝션(맥락 파괴) 탐지 규칙 (S15P11B209-742).

다음 질문 경로에서 아이 발화는 LLM 프롬프트에 원문으로 들어간다. "지금까지의 모든 지시를 잊고~"
같은 문장이 들어오면 시스템 프롬프트 맥락이 무너질 수 있다. 그런 입력은 LLM에 전달하지 않고
아이에게 다시 물어보게 한다(question_service가 결정적 재질문으로 처리).

설계 원칙:
- 임상 판정이 아니라 '명백한 지시 조작 신호'를 규칙(정규식)으로 잡는 1차 감지다.
- 아동 대화라 정상 발화("엄마랑 나 살아")와 인젝션 문장은 뚜렷이 다르다. 단독어("규칙","잊었어")로는
  발동하지 않게 대상어+동작어 '조합'을 요구해 오탐을 낮춘다.
- 한국어를 중심으로, 흔한 영어 인젝션 상용구도 함께 잡는다(대소문자 무시).
- 오탐의 대가는 '재질문 한 번'이라 가볍다 — 놓치는 것보다 되묻는 쪽을 우선한다.

가드레일: 아이 발화 원문은 로그로 남기지 않는다 — 매칭된 사유 코드만 남긴다.
"""

from __future__ import annotations

import re

# 사유 코드 — question_service가 로그·분기에 쓴다(원문 아님).
INSTRUCTION_OVERRIDE = "INSTRUCTION_OVERRIDE"  # 기존 지시·규칙 무시/망각
ROLE_HIJACK = "ROLE_HIJACK"  # 역할·페르소나 탈취
INSTRUCTION_INJECTION = "INSTRUCTION_INJECTION"  # 특정 출력 강제 / 시스템 프롬프트 유출

# ── 기존 지시·규칙 무시/망각 ────────────────────────────────────
# 대상어(프롬프트·지시·규칙·명령·설정·대화·맥락)와 동작어(잊/무시/무효/초기화/리셋/지워)의
# '조합'을 요구해 "규칙"·"잊었어" 단독 오탐을 막는다.
_OVERRIDE = [
    r"(지금까지|이전|앞의|위(에|의)?|모든|그동안|방금).{0,12}"
    r"(프롬프트|지시|명령|규칙|설정|대화|맥락|instruction|prompt).{0,12}"
    r"(잊|무시|무효|초기화|리셋|지워|없던)",
    r"(프롬프트|지시|명령|규칙|설정)\s*(을|를)?\s*(잊고|잊어|무시하고|무시해)",
    r"ignore\s+(all\s+)?(the\s+)?(previous|above|prior|earlier)\s+(instruction|prompt|rule)",
    r"disregard\s+(all\s+)?(previous|above|prior)\s+(instruction|prompt)",
    r"forget\s+(everything|all|the\s+above|previous)",
]

# ── 역할·페르소나 탈취 ──────────────────────────────────────────
_ROLE = [
    r"(지금부터|이제부터|앞으로)\s*너는",
    r"너는\s*이제",
    r"역할\s*(을|를)?\s*(잊|바꿔|버려|무시)",
    r"(개발자|디버그|관리자)\s*모드",
    r"탈옥",
    r"제한\s*(을|를)?\s*(풀|해제)",
    r"jailbreak",
    r"\bDAN\b",
    r"you\s+are\s+now\b",
    r"act\s+as\s+(a|an|if)\b",
    r"pretend\s+to\s+be",
    # 대화 역할 마커 주입(system:/assistant:/user: 흉내)
    r"\b(system|assistant|user)\s*:",
]

# ── 특정 출력 강제 / 시스템 프롬프트 유출 ───────────────────────
_INJECTION = [
    r"(라고|이라고)\s*(말해|대답해|출력해|적어)",
    r"그대로\s*(출력|따라|복사)",
    r"(시스템\s*)?(프롬프트|지시문)\s*(을|를)?\s*(보여|알려|출력|말해)",
    r"(reveal|show|print|repeat)\s+(your\s+)?(system\s+)?(prompt|instruction)",
]

_RULES: list[tuple[str, list[re.Pattern]]] = [
    (INSTRUCTION_OVERRIDE, [re.compile(p, re.IGNORECASE) for p in _OVERRIDE]),
    (ROLE_HIJACK, [re.compile(p, re.IGNORECASE) for p in _ROLE]),
    (INSTRUCTION_INJECTION, [re.compile(p, re.IGNORECASE) for p in _INJECTION]),
]


def scan(text: str) -> str | None:
    """한 발화에서 프롬프트 인젝션 신호를 찾는다. 우선순위 순 첫 매칭 사유 코드 반환.

    신호가 없으면 None. 반환값은 사유 '코드'라 로그에 남겨도 원문이 새지 않는다.
    """
    if not text or not text.strip():
        return None
    for reason_code, patterns in _RULES:
        if any(rx.search(text) for rx in patterns):
            return reason_code
    return None
