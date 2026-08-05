"""생성 질문 품질 판정 (S15P11B209-918).

question_safety(596)와 역할이 다르다. 저쪽은 **아이에게 해로운** 문장을 막고 차단하면
BE가 폴백 템플릿으로 대체한다. 여기서 보는 것은 해롭지는 않지만 **말이 안 되는** 문장이다.

  "이 머리는 누구의 머리야?"   ← 그림 속 사람의 머리를 두고 소유자를 묻는다
  "손은 누구 거야?"

이런 문장이 나오는 경로: 대상 지시가 부위 하나로 좁혀지고(activity_block TARGET_FIRST),
사람 질문 뱅크의 "혹시 누구를 생각하면서 그린 거야?" 방향이 그 부위에 얹힌다. 둘 다
각자는 정상 규칙이라 프롬프트만으로는 완전히 못 막는다 — 그래서 사후에 한 번 더 본다.

⚠️ 차단하지 않는다. 어색한 질문을 422로 올리면 BE가 폴백 템플릿("오늘은 뭘 그렸어?")으로
   대체해 대화가 더 나빠진다. 대신 호출자가 같은 대상에 대한 시각 속성 질문으로 **교체**한다
   (question_service._quality_replacement). 판정은 규칙 기반이고 LLM을 다시 부르지 않는다.

가드레일: 질문 원문은 로그로 남기지 않는다 — 사유 코드만.
"""

from __future__ import annotations

import re

# 사유 코드. 로그·평가에서 이 값으로 분기한다.
POSSESSIVE_BODY_PART = "POSSESSIVE_BODY_PART"

# 그림 속 사람의 부위 이름. htp_labels의 PERSON_* 표시명과 같은 어휘이되, 자유 그림에서
# 사람 부위가 잡히는 경우도 있어 활동유형과 무관하게 본다.
_BODY_PARTS = (
    "머리카락", "머리", "얼굴", "몸통", "상체", "하체", "어깨",
    "팔", "다리", "손", "발", "눈", "코", "입", "귀", "목",
)
_PART = "|".join(_BODY_PARTS)

# 소유격 질문만 좁게 잡는다. 넓게 잡으면 정상 문항까지 걸린다 —
# htp_question_bank의 "이 나무를 보면 누가 생각나?"·"혹시 누구를 생각하면서 그린 거야?"는
# '누구' 뒤에 소유 표지(의·거·것)가 없어서 아래 두 패턴 어디에도 걸리지 않는다.
_PATTERNS = (
    # "머리는 누구의 머리야?" · "손은 누구 거야?" — 부위 뒤에 소유를 묻는 말이 붙는다.
    re.compile(rf"(?:{_PART})\s*(?:은|는|이|가)?\s*누구\s*(?:의|거|것)"),
    # "누구의 머리야?" · "누구 발이야?" — 소유를 먼저 묻고 부위가 뒤에 온다.
    re.compile(rf"누구\s*(?:의|)\s*(?:{_PART})\s*(?:야|이야|니|인가|인지)"),
)


def find_awkward(question_text: str) -> str | None:
    """문맥상 어색한 질문이면 사유 코드를, 아니면 None을 돌려준다."""
    text = question_text or ""
    if any(rx.search(text) for rx in _PATTERNS):
        return POSSESSIVE_BODY_PART
    return None


# 종성이 있는 한글 음절 뒤에는 '은', 없으면 '는'. 교체 문장을 만들 때 쓴다 —
# 조사를 틀리면 아이에게 읽어 주는 문장이 어색해진다(TTS로도 그대로 나간다).
def eun_neun(word: str) -> str:
    """단어 끝 글자에 맞는 주제 조사('은'/'는'). 한글이 아니면 '는'."""
    if not word:
        return "는"
    last = word[-1]
    if not ("가" <= last <= "힣"):
        return "는"
    has_final = (ord(last) - ord("가")) % 28 != 0
    return "은" if has_final else "는"


if __name__ == "__main__":
    # 스모크 테스트:  cd ai && python question_quality.py
    samples = [
        "이 머리는 누구의 머리야?",  # 소유격 → 검출
        "머리카락은 누구 거야?",  # 소유격 → 검출
        "누구의 발이야?",  # 소유격(역순) → 검출
        "그림 속 사람의 머리는 어떤 모양이야?",  # 정상
        "이 나무를 보면 누가 생각나?",  # 정상(질문 뱅크 문항)
        "혹시 누구를 생각하면서 그린 거야?",  # 정상(질문 뱅크 문항)
    ]
    for s in samples:
        print(f"{find_awkward(s) or 'PASS':<22} {s}")
