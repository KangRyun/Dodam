"""생성 질문 품질 판정 (S15P11B209-918, 954).

question_safety(596)와 역할이 다르다. 저쪽은 **아이에게 해로운** 문장을 막고 차단하면
BE가 폴백 템플릿으로 대체한다. 여기서 보는 것은 해롭지는 않지만 **말이 안 되는** 문장이다.

  "이 머리는 누구의 머리야?"   ← 그림 속 사람의 머리를 두고 소유자를 묻는다(918)
  "손은 누구 거야?"
  "머리는 어떤 모양이야?"      ← 그림을 보면 이미 아는 것을 아이에게 되묻는다(954)

이런 문장이 나오는 경로: 대상 지시가 부위 하나로 좁혀지고(activity_block TARGET_FIRST),
사람 질문 뱅크의 "혹시 누구를 생각하면서 그린 거야?" 방향이 그 부위에 얹힌다. 둘 다
각자는 정상 규칙이라 프롬프트만으로는 완전히 못 막는다 — 그래서 사후에 한 번 더 본다.

⚠️ 차단하지 않는다. 어색한 질문을 422로 올리면 BE가 폴백 템플릿("오늘은 뭘 그렸어?")으로
   대체해 대화가 더 나빠진다. 대신 호출자가 다른 각도의 질문으로 **교체**한다
   (question_service._quality_replacement). 판정은 규칙 기반이고 LLM을 다시 부르지 않는다.

가드레일: 질문 원문은 로그로 남기지 않는다 — 사유 코드만.
"""

from __future__ import annotations

import re

# 사유 코드. 로그·평가에서 이 값으로 분기한다.
POSSESSIVE_BODY_PART = "POSSESSIVE_BODY_PART"
REDUNDANT_VISUAL = "REDUNDANT_VISUAL"
MULTIPLE_QUESTIONS = "MULTIPLE_QUESTIONS"
# S15P11B209-999: 그림일기 실호출에서 관측된 위반을 사유별로 가른다. 전부 REDUNDANT_VISUAL
#   하나로 묶으면 무엇 때문에 교체됐는지 알 수 없어 원인별 개선이 막힌다.
VISUAL_EVALUATION = "VISUAL_EVALUATION"
CORRECTION_IGNORED = "CORRECTION_IGNORED"
UNGROUNDED_EMOTION = "UNGROUNDED_EMOTION"
IDENTITY_FALLBACK = "IDENTITY_FALLBACK"
BODY_PART_ACTOR = "BODY_PART_ACTOR"

# 그림 속 사람의 부위 이름. htp_labels의 PERSON_* 표시명과 같은 어휘이되, 자유 그림에서
# 사람 부위가 잡히는 경우도 있어 활동유형과 무관하게 본다.
# 부위 이름은 question_service 도 같은 어휘를 쓴다(999) — 두 곳이 갈리면 한쪽만 고쳐진다.
BODY_PARTS = (
    "머리카락", "머리", "얼굴", "몸통", "상체", "하체", "어깨",
    "팔", "다리", "손", "발", "눈", "코", "입", "귀", "목",
)
_BODY_PARTS = BODY_PARTS  # 기존 이름을 쓰던 곳을 위해 남겨 둔다.
_PART = "|".join(BODY_PARTS)

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


# ── 이미 아는 것을 되묻는 질문 (S15P11B209-954) ──────────────────
# VLM 그림 서술은 색·모양·크기·개수·위치를 이미 읽어 냈고, 아이는 방금 무엇을 그렸는지
# 말했다. 그런데 프롬프트는 그 세부를 '질문 소재'로 써 왔다 — 그 결과가 이것이다.
#
#   아이: "머리를 그렸어!"  →  도담: "어떤 머리를 그린 거야?" / "머리는 어떤 모양이야?"
#
# 아이에게는 자기가 방금 한 말을 다시 설명하라는 요구로 들린다. 그림 분석은 질문 소재를
# 고르는 자료가 아니라 **이미 답을 아는 질문을 제외하는** 자료여야 한다.
#
# ⚠️ 표현만 보고 무조건 막지 않는다. "무슨 색이야?"가 늘 나쁜 게 아니라, **그 답을 이미
#    알고 있을 때만** 나쁘다. 그림 서술도 없고 아이도 아직 아무 말을 안 했으면 우리는 정말
#    모르는 상태라(activity_block ART_DIARY_OPEN) 그대로 물어봐도 된다.
# ⚠️ HTP에는 적용하지 않는다(호출자가 활동으로 가른다). 지붕 모양·나무 크기는 PDI 표준이
#    실제로 묻는 항목이라, 여기서 걸러 내면 htp_question_bank가 통째로 죽는다.

# 질문이 어느 시각 축을 묻는가. 축마다 '답이 이미 나와 있는지' 보는 곳이 다르다.
_AXIS_PATTERNS = (
    ("COLOR", re.compile(r"무슨\s*색|어떤\s*색|색깔|색이(?:야|니|에요|예요)")),
    (
        "SHAPE",
        re.compile(r"(?:어떤|무슨)\s*(?:모양|모습|생김새)|어떻게\s*생겼|어떻게\s*보여"),
    ),
    ("COUNT", re.compile(r"몇\s*(?:개|명|마리|송이|채|그루|번)")),
    ("PLACE", re.compile(r"어디에?\s*(?:그렸|그린|있|놓|칠했)")),
    ("SIZE", re.compile(r"얼마나\s*(?:커|크|작)|(?:어떤|무슨)\s*크기")),
)

# 축별 '답이 이미 적혀 있다'는 증거. 그림 서술·아이 발화에서 찾는다.
_AXIS_EVIDENCE = {
    "COLOR": re.compile(
        r"빨[간강]|파[란랑]|노[란랑]|검[은정]|하얀|흰|초록|녹색|분홍|보라|주황"
        r"|갈색|회색|남색|하늘색|색"
    ),
    "SHAPE": re.compile(r"동그|둥[근글]|네모|세모|곱슬|뾰족|길쭉|납작|모양|생김새"),
    "COUNT": re.compile(r"\d|여러|많[은이]|[한두세네]\s*(?:개|명|마리|채|그루|송이)"),
    "PLACE": re.compile(r"가운데|왼쪽|오른쪽|위쪽|아래쪽|위에|아래에|옆에|뒤에|앞에|구석"),
    "SIZE": re.compile(r"커다|조그|크기|큰\s|작은\s|크게|작게"),
}

# "어떤 머리야?" · "어떤 머리를 그린 거야?" — 아이가 방금 말한 것을 표현만 바꿔 되묻는 꼴.
# 낱말을 잡아 두었다가, 그 낱말이 이미 나온 것일 때만 걸러 낸다.
_KIND_RE = re.compile(
    r"(?:어떤|무슨)\s*(?P<noun>[가-힣]{2,6}?)(?:을|를|이|가|은|는)?\s*"
    r"(?:야|이야|니|인지|그렸|그린|그리)"
)

# 질문 낱말을 서술과 대조할 때 무시할 말. 이 말들이 서술에 있다고 해서 '이미 아는 대상'이
# 되지는 않는다 — 어느 질문에나 붙는 껍데기다.
_STOPWORDS = frozenset(
    {
        "그림", "이건", "이거", "그거", "저거", "여기", "저기", "거기",
        "지금", "그때", "무슨", "어떤", "어떻게", "어디", "누구", "누가",
        "얼마나", "이런", "그런", "정말", "진짜", "그리고", "이야기",
        "모양", "모습", "색깔", "생김새", "크기", "있어", "있니", "그렸",
    }
)


def _visual_axis(text: str) -> str | None:
    """질문이 묻는 시각 축(없으면 None)."""
    for axis, rx in _AXIS_PATTERNS:
        if rx.search(text):
            return axis
    return None


def _known_material(drawing_description: str | None, child_texts) -> str:
    """우리가 이미 알고 있는 것 — 그림 서술 + 아이가 지금까지 한 말."""
    parts = [drawing_description or ""]
    parts += [(t or "") for t in (child_texts or ())]
    return " ".join(p.strip() for p in parts if p and p.strip())


def _subject_known(text: str, known: str) -> bool:
    """질문이 가리키는 대상이 이미 나온 것인가.

    조사가 붙으므로 한글 덩어리의 앞부분부터 잘라 가며 대조한다("머리는" → "머리").
    """
    for run in re.findall(r"[가-힣]+", text):
        for length in range(len(run), 1, -1):
            token = run[:length]
            if token in _STOPWORDS:
                continue
            if token in known:
                return True
    return False


def find_redundant(
    question_text: str,
    *,
    drawing_description: str | None = None,
    child_texts=(),
) -> str | None:
    """그림·아이 말로 이미 답을 아는 질문이면 사유 코드를, 아니면 None.

    Args:
        question_text: 생성된 질문.
        drawing_description: VLM 그림 서술(프롬프트에 실은 것과 같은 값).
        child_texts: 이 대화에서 아이가 한 말들.
    """
    text = (question_text or "").strip()
    if not text:
        return None
    known = _known_material(drawing_description, child_texts)
    if not known:
        # 서술도 없고 아이도 아직 말이 없다 — 우리가 정말 모르는 상태라 물어봐도 된다.
        return None

    # ① 아이가 방금 말한 낱말을 그대로 되묻는다("머리를 그렸어" → "어떤 머리야?").
    for match in _KIND_RE.finditer(text):
        noun = match.group("noun")
        if noun not in _STOPWORDS and noun in known:
            return REDUNDANT_VISUAL

    axis = _visual_axis(text)
    if axis is None:
        return None
    # ② 질문이 가리키는 대상을 이미 안다 → 그 대상의 겉모습도 그림에 다 있다.
    if _subject_known(text, known):
        return REDUNDANT_VISUAL
    # ③ 대상을 못 집어냈어도 그 축의 답이 서술에 이미 적혀 있다("빨간 지붕" → 색).
    if _AXIS_EVIDENCE[axis].search(known):
        return REDUNDANT_VISUAL
    # ④ 대상을 생략한 질문("어떤 모양이야?")은 방금까지 이야기하던 것을 가리킨다.
    #    아이가 이미 무언가를 말했다면 그 대상은 확정돼 있고, 겉모습은 그림에 보인다.
    if any((t or "").strip() for t in (child_texts or ())):
        return REDUNDANT_VISUAL
    return None


# ── 그림 칭찬·감정 단정·정정 무시 (S15P11B209-999) ───────────────
# 실호출에서 나온 문장들이다:
#   "머리가 까맣게 칠해져서 멋지네! 그때 뭐 하고 있었어?"   → 색 언급 + 그림 평가
#   "머리가 까맣게 칠해져서 신기하네. 그때 어떤 기분이었어?" → 평가 + 정정 직후 감정 점프
# 셋 다 프롬프트로 먼저 막지만, 모델이 넘어올 때를 위해 마지막 그물을 둔다.

# 그림·솜씨를 평가하는 말. 아이 자신이나 사건을 두고 하는 말("재밌었겠다")은 여기가 아니다 —
# 그건 감정 단정 쪽에서 본다.
_EVALUATION = re.compile(
    r"(?:멋지|멋있|예쁘|이쁘|귀엽|근사|훌륭|대단|잘\s*그렸|잘\s*했|신기하)"
)

# 아이가 말하지 않은 마음을 우리가 붙이는 말. 물음이 아니라 단정이라 더 세게 막는다.
_ASSERTED_EMOTION = re.compile(
    r"(?:속상|무서웠|무서웠겠|재밌었겠|재미있었겠|슬펐|기뻤|화났|신났|외로웠|힘들었)"
    r"\s*(?:겠|구나|네|었구나|였구나)"
)

# 마음을 묻는 말. 그 자체로는 정상이라, 부르는 쪽에서 '지금 물어도 되는 자리인가'를 판단한다.
_EMOTION_QUESTION = re.compile(r"(?:기분|느낌|마음|어땠어|어땠니)")

# 정체를 묻는 말. 기본 탐색 질문으로 쓰지 않는다(999).
#   '누구 이야기야?'도 정체 질문이다 — 2026-08-07 실호출에서 아이가 "이거 나야"라고 말한
#   직후에 돌아왔다. 방금 들은 답을 그대로 되묻는 꼴이라 여기서 함께 본다.
#   ⚠️ '누구한테·누구랑·누구에게'는 사건 속 상대를 묻는 말이라 걸리지 않는다(뒤에 조사가 온다).
_IDENTITY_QUESTION = re.compile(
    r"(?:누구|누가)\s*(?:야|니|일까|였어|예요)|누구\s*(?:의\s*)?이야기|뭐야|무엇이야|뭘까"
)


def find_visual_evaluation(question_text: str) -> str | None:
    """그림·솜씨를 평가하는 말이 섞였으면 사유 코드를 돌려준다.

    잘 그렸다·못 그렸다를 말하지 않는 것은 공통 규칙이 이미 정하고 있다. 여기서는 그 규칙이
    지켜지지 않은 문장을 골라낸다 — 평가는 아이가 다음에 할 말을 '잘 그리기'로 옮긴다.
    """
    return VISUAL_EVALUATION if _EVALUATION.search(question_text or "") else None


def find_asserted_emotion(question_text: str) -> str | None:
    """아이가 말하지 않은 마음을 단정하면 사유 코드를 돌려준다."""
    return UNGROUNDED_EMOTION if _ASSERTED_EMOTION.search(question_text or "") else None


def is_emotion_question(question_text: str) -> bool:
    """마음을 묻는 질문인가. 물어도 되는 자리인지는 부르는 쪽이 정한다."""
    return bool(_EMOTION_QUESTION.search(question_text or ""))


def is_identity_question(question_text: str) -> bool:
    """정체를 묻는 질문인가('누구야'·'뭐야')."""
    return bool(_IDENTITY_QUESTION.search(question_text or ""))


def find_stale_label(question_text: str, stale_labels) -> str | None:
    """아이가 아니라고 한 탐지 이름을 다시 쓰면 사유 코드를 돌려준다.

    아이가 고쳐 준 이름을 우리가 흘리면, 아이는 자기 말이 전달되지 않았다고 느낀다.
    """
    text = question_text or ""
    for label in stale_labels or ():
        if label and label in text:
            return CORRECTION_IGNORED
    return None


# 사건·행동을 묻는 말. 부위 이름 바로 뒤에 붙으면 부위가 이야기의 주인공이 된다.
_ACTS = (
    r"뭐\s*하|무엇을\s*하|뭘\s*하|무슨\s*일|어떤\s*일|어떻게\s*됐|무슨\s*이야기"
    r"|어디\s*갔|뭐\s*했|무엇을\s*했"
)
# 부위와 사건 표현 사이에 부사가 끼어도 같은 문장이다("그 머리는 **지금** 뭐 하고 있어?").
#   문장 부호는 넘지 않는다 — 넘으면 앞 문장의 부위와 뒤 문장의 사건이 엮인다.
_BODY_PART_ACTOR = re.compile(
    rf"(?:{_PART})\s*(?:은|는|이|가|로|으로|에서|에게|한테|을|를)?[^.!?]{{0,8}}?(?:{_ACTS})"
)


def find_body_part_actor(question_text: str, part: str | None) -> str | None:
    """바로잡아 준 신체 부위를 사건의 주인공으로 삼은 질문이면 사유 코드를 돌려준다.

    2026-08-07 실호출: 아이가 "덤불 아니고 내 머리야"라고 바로잡자 "그 머리로 무슨 일이
    있었어?"·"그 머리는 지금 뭐 하고 있어?"가 돌아왔다. 프롬프트의 정정 처리 규칙
    ("그 대상이 무엇을 하는지 물어봐")이 부위에도 그대로 적용된 결과다 — 부위는 스스로
    무엇을 하지 않아서 아이가 답할 수 없다. 이야기는 그 부위를 가진 **사람**에게 붙는다.

    ⚠️ part 가 주어질 때만 본다. 아이가 부위를 바로잡은 그 턴에만 적용한다는 뜻이다 —
       "손으로 뭐 했어?"처럼 아이가 먼저 연 이야기까지 잡으면 정상 대화가 끊긴다.
    """
    if not part or part not in (question_text or ""):
        return None
    return BODY_PART_ACTOR if _BODY_PART_ACTOR.search(question_text or "") else None


# ── 한 번에 질문 하나 (S15P11B209-954) ───────────────────────────
# 연령별 말하기 규칙이 이미 "한 번에 한 가지만"이라고 적고 있지만, 반응 + 질문 구조에서
# 모델이 질문을 하나 더 얹는 일이 있다. 아이는 둘 중 무엇에 답할지 고르지 못한다.
# 뒤를 잘라 **앞의 공감과 첫 질문만** 남긴다 — 통째로 버리면 반응까지 사라진다.

# 문장 끝 뒤에서 자른다. 뒤따르는 공백은 함께 먹는다(공백이 없어도 잘린다).
_SENTENCE_SPLIT = re.compile(r"(?<=[.!?])\s*")
# "이 사람은 누구야, 그리고 뭐 하고 있었어?" — 물음표는 하나인데 물음은 둘.
_CONJOINED = re.compile(r"^(?P<head>.+?)[,·]?\s*(?:그리고|또)\s+(?P<tail>.+\?)$")
_WH = re.compile(r"무엇|뭐|무슨|어떤|누구|누가|어디|왜|어떻게|언제|몇")


def _conjoined_match(text: str):
    """접속사로 이어 붙인 두 물음이면 매치를 돌려준다(아니면 None)."""
    match = _CONJOINED.match(text.strip())
    if match and _WH.search(match.group("head")) and _WH.search(match.group("tail")):
        return match
    return None


def find_multiple_questions(question_text: str) -> str | None:
    """질문이 둘 이상이면 사유 코드를, 아니면 None."""
    text = question_text or ""
    if text.count("?") >= 2:
        return MULTIPLE_QUESTIONS
    return MULTIPLE_QUESTIONS if _conjoined_match(text) else None


def to_single_question(
    question_text: str,
    *,
    drawing_description: str | None = None,
    child_texts=(),
) -> str:
    """앞의 반응과 질문 하나만 남긴다(질문이 하나면 그대로).

    ⚠️ 무조건 '첫' 질문을 남기지 않는다. 2026-08-06 gpt-4o-mini 실측에서 모델이 질문을 둘
    낼 때 **약한 질문을 먼저, 좋은 질문을 뒤에** 두는 경우가 나왔다:

      "그림 속에 있는 집은 어떤 집이야? 여기서 무슨 일이 있었어?"

    앞을 남기면 이미 아는 것을 되묻는 쪽만 살아남아, 이 판정기가 막으려던 것을 우리가
    직접 골라 내보내는 꼴이 된다. 그래서 이미 답을 아는 질문은 건너뛰고 고른다.
    """
    text = (question_text or "").strip()
    if not text:
        return text
    if text.count("?") >= 2:
        sentences = [s for s in _SENTENCE_SPLIT.split(text) if s]
        questions = [s for s in sentences if s.rstrip().endswith("?")]
        chosen = next(
            (
                q
                for q in questions
                if find_redundant(
                    q,
                    drawing_description=drawing_description,
                    child_texts=child_texts,
                )
                is None
            ),
            questions[0] if questions else None,
        )
        if chosen is not None:
            # 반응은 고른 질문 앞의 것만 쓴다 — 뒤쪽 문장은 버린 질문에 딸린 말이다.
            lead = []
            for sentence in sentences:
                if sentence is chosen:
                    break
                if not sentence.rstrip().endswith("?"):
                    lead.append(sentence)
            text = " ".join([*lead, chosen]).strip()
    match = _conjoined_match(text)
    if match:
        head = match.group("head").rstrip(" ,·")
        return head if head.endswith("?") else head + "?"
    return text


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

    print()
    description = "검은색 곱슬머리를 한 사람이 있어요."
    said = ["머리를 그렸어"]
    for s in [
        "어떤 머리를 그린 거야?",  # 아이 말 되묻기 → 검출
        "머리는 어떤 모양이야?",  # 이미 보이는 것 → 검출
        "이 사람은 누구야?",  # 정상(그림만 보고는 모른다)
        "여기서 무슨 일이 있었어?",  # 정상
    ]:
        verdict = find_redundant(s, drawing_description=description, child_texts=said)
        print(f"{verdict or 'PASS':<22} {s}")
