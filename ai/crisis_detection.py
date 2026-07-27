"""아동 발화의 자해·학대·위기 의도 탐지 규칙 (S15P11B209-593).

아이가 대화 중 자해·학대·위기 신호를 드러내면 곰돌이 질문을 이어가지 않고 안전 차단으로
돌린다(422 AI_SAFETY_POLICY_BLOCKED). 실제 보호자 위기 안내는 후속(S15P11B209-598)에서
같은 사유 코드를 받아 처리한다.

설계 원칙:
- 임상 판정이 아니라 '명백한 신호'를 규칙(정규식)으로 잡는 1차 감지다. 놓치는 것보다
  사람에게 넘기는 쪽을 우선하되, 상상 놀이 표현("게임에서 죽었어", "괴물이 죽었어")까지
  잡지 않도록 표현을 좁힌다. 그래서 자해는 '1인칭 의도'(죽고 싶어), 학대는 '가해 주체+폭력'
  형태로 요구한다.
- 우선순위: 자해 > 학대 > 위기. 여러 신호가 섞이면 더 위중한 것을 사유로 돌린다.

가드레일: 아이 발화 원문은 로그로 남기지 않는다 — 매칭된 사유 코드만 남긴다.
"""

from __future__ import annotations

import re

# 사유 코드(BE SafetyResult.blockReasonCode로 전달) — 후속 위기 안내가 이 값으로 분기한다.
SELF_HARM_RISK = "SELF_HARM_RISK"
ABUSE_DISCLOSURE = "ABUSE_DISCLOSURE"
CRISIS_INTENT = "CRISIS_INTENT"

# ── 자해·자살 의도(1인칭 의도 위주) ─────────────────────────────
_SELF_HARM = [
    r"죽고\s*싶",
    r"죽어\s*버리",
    r"죽어야\s*지",
    r"죽을\s*래",
    r"죽는\s*게\s*나",
    r"사라지고\s*싶",
    r"없어지고\s*싶",
    r"살기\s*싫",
    r"살고\s*싶지\s*않",
    r"태어나지\s*말",
    r"자해",
    r"자살",
    r"손목\s*을?\s*긋",
    r"칼로\s*(나|내|찌)",
]

# ── 학대(가해 주체 + 폭력 행위) ─────────────────────────────────
_ABUSE = [
    # 가족·보호자·어른 주체 + 때림·꼬집음·발로 참 등
    r"(아빠|엄마|아버지|어머니|삼촌|이모부|고모부|할아버지|할머니|형|오빠|누나|언니|선생님)"
    r".{0,10}(때려|때렸|때린|때리|맞았|밀쳐|꼬집|발로\s*(차|찼|찬)|목을\s*(조|졸))",
    r"맞아서\s*(아파|무서|피)",
    r"매일\s*맞",
    r"자꾸\s*때려",
    r"때려서\s*(무서|아파)",
    # 성적 학대 신호(민감) — 은밀한 신체 접촉 표현.
    r"몰래\s*만졌",
    r"이상한\s*데\s*를?\s*만졌",
    r"거기\s*를?\s*만졌",
]

# ── 위기(강한 정서적 고립·도피) — 좁게 유지해 과잉 차단 방지 ────
_CRISIS = [
    r"도망치고\s*싶",
    r"숨고\s*싶은데\s*무서",
    r"무서워서\s*집에\s*(못|안)",
    r"아무도\s*날?\s*안\s*(좋아|사랑)",
    r"다\s*(없어졌으면|사라졌으면)",
]

_RULES: list[tuple[str, list[re.Pattern]]] = [
    (SELF_HARM_RISK, [re.compile(p) for p in _SELF_HARM]),
    (ABUSE_DISCLOSURE, [re.compile(p) for p in _ABUSE]),
    (CRISIS_INTENT, [re.compile(p) for p in _CRISIS]),
]


def detect(text: str) -> str | None:
    """한 발화에서 위기 신호를 찾는다. 우선순위(자해>학대>위기) 순으로 첫 매칭 코드 반환.

    신호가 없으면 None. 반환값은 사유 '코드'라 로그에 남겨도 원문이 새지 않는다.
    """
    if not text or not text.strip():
        return None
    for reason_code, patterns in _RULES:
        if any(rx.search(text) for rx in patterns):
            return reason_code
    return None


def scan(texts) -> str | None:
    """여러 발화(아이 발화들)를 검사해 가장 위중한 신호 코드를 반환한다(없으면 None).

    우선순위가 높은 자해가 하나라도 있으면 학대·위기보다 먼저 반환한다.
    """
    found: set[str] = set()
    for text in texts:
        code = detect(text)
        if code is not None:
            found.add(code)
    for reason_code, _ in _RULES:  # _RULES는 위중도 순
        if reason_code in found:
            return reason_code
    return None
