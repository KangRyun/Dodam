"""내부 대화 질문 생성 서비스 (S15P11B209-183).

역할: BE 내부 계약 요청 → GMS 대화 LLM 호출(제한적 재시도) → 계약 응답 조립.

루프 위치 확정(2026-07-23, BE 283 머지 근거):
- 대화 루프(질문 반복·질문 수 상한·세션 잠금·폴백 템플릿)는 BE
  ConversationQuestionService가 소유한다.
- 이 서버는 상태 없는 '질문 1건 생성기' — 세션 상태를 들고 있지 않고,
  요청에 담긴 문맥(recentMessages·detectedObjects)만 사용한다.
  근거 정리: _workspace/183_ai_loop-decision.md

재시도 예산(BE read timeout 15초 안쪽):
- 시도당 GMS timeout 4s × 최대 3회(최초 1 + 재시도 2) + 지수 백오프(0.5s + 1.0s)
  = 최악 13.5s < 15s. 초과하면 BE가 READ_TIMEOUT으로 끊고 폴백 템플릿을 저장한다.
- 일시 오류(연결 실패·타임아웃·5xx)만 재시도한다. 4xx(키 오류·잘못된 요청·429)는
  즉시 실패. reason: 4xx는 다시 보내도 같은 결과라 예산만 소모하고,
  429는 짧은 백오프 재시도가 오히려 부하를 키운다.
  (대안 검토: 429만 1회 재시도 — 트래픽이 커지면 재검토. 지금은 BE 폴백이 있어 불필요.)

가드레일:
- 로그에는 request_id·에러 유형·시도 횟수만 남긴다.
  프롬프트(아이 발화 포함)·GMS 키·생성된 질문 원문은 절대 로그 금지.
"""

from __future__ import annotations

import logging
import re
import time

from openai import APIConnectionError, APIStatusError, OpenAIError

import config
import crisis_detection
import crisis_guidance
import llm_client
import prompt_injection
import prompts_registry  # 답변 칩 프롬프트 로딩·버전 추적 (S15P11B209-788)
import question_safety
from gms import get_client
from internal_contracts import (
    DetectedObject,
    QuestionOption,
    QuestionRequest,
    QuestionResponse,
    SafetyResult,
)

logger = logging.getLogger(__name__)

# 내부 계약 경로도 draft 경로(llm_client)와 같은 프롬프트 파일을 쓴다 — 버전도 그대로 따른다.
# 버전은 prompts_registry가 중앙 관리하는 통합 버전이다(S15P11B209-595).
# 이건 '대화 경로가 쓸 수 있는 파일 전부'의 버전이다. GMS를 실제로 부른 응답에는 이번에 고른
# 활동 변형만 담은 llm_client.prompt_version_for(activityType)를 싣는다(S15P11B209-786) —
# 두 변형을 모두 적으면 어느 쪽으로 뽑힌 결과인지 사후에 구분할 수 없다.
# 위기·인젝션 결정적 응답은 프롬프트를 쓰지 않으므로 이 전체 버전을 그대로 남긴다.
PROMPT_VERSION = llm_client.PROMPT_VERSION


class UpstreamError(Exception):
    """GMS 최종 실패(재시도 소진 또는 재시도 불가 오류).

    엔드포인트가 502로 매핑 → BE Type.OTHER → 폴백 템플릿 저장 경로.
    """

    def __init__(self, error_code: str, cause_type: str):
        super().__init__(error_code)
        self.error_code = error_code  # AI_UPSTREAM_UNAVAILABLE | AI_UPSTREAM_REJECTED | AI_EMPTY_COMPLETION
        self.cause_type = cause_type  # 원인 예외 클래스명(내용 아님 — 로그 안전)


class SafetyBlockedError(Exception):
    """안전 정책 차단. 엔드포인트가 422 AI_SAFETY_POLICY_BLOCKED로 매핑 →
    BE가 저장 없이 사용자 422로 종료하는 경로."""

    def __init__(self, block_reason_code: str, rule_version: str):
        super().__init__(block_reason_code)
        self.block_reason_code = block_reason_code
        self.rule_version = rule_version


# ── 프롬프트 조립 (S15P11B209-589) ──────────────────────────────
# 이전 placeholder는 무맥락 고정 시스템 프롬프트 + "[상황] 아이가 방금 그림을 그렸어요"
# 고정 문구를 써서 첫 질문이 매번 비슷하게 고정됐다(첫 질문 고정 현상).
# 이제 draft 경로가 이미 검증한 프롬프트(first_question.txt·conversations.txt)를 재사용해
# 그림 탐지 객체·대화 문맥 기반으로 생성한다 — 두 경로를 한 프롬프트로 통일.
# ⚠️ 내부 계약엔 아이 이름이 없다(개인정보 최소화) → 항상 "너"로 부른다.

# 연령(난이도)별 질문 규칙은 ai/prompts/conversation_tone.txt가 소유한다(S15P11B209-786).
# 원래 여기 코드 상수(_DIFFICULTY_RULES)였는데 프롬프트 파일로 옮겼다:
#   ① 아이에게 그대로 들려줄 문구인데 prompts_registry 버전 추적 밖이었다,
#   ② 이 블록을 붙이는 곳이 여기뿐이라 draft 경로엔 연령별 말투가 아예 없었다,
#   ③ 프롬프트 파일의 고정 '말투:' 절과 같은 말을 두 번 해 서로 어긋났다(구 PRESCHOOL
#      "10자 안팎"은 대화 프롬프트의 "반응한 다음 질문을 이어줘"와 동시에 만족할 수 없었다).
# 이제 llm_client가 프롬프트 조립 시 난이도 구획 하나를 골라 싣는다.


def _truncate_description(text: str | None) -> str | None:
    """그림 서술을 프롬프트에 넣기 전 길이 상한으로 자른다(S15P11B209-704).

    VLM 프롬프트가 2~4문장을 지시하므로 정상 범위는 손대지 않는다. 모델이 길게 답해
    [그림 분석 결과] 절이 다른 지시를 압도하는 경우만 막는다. 잘린 사실은 말줄임표로
    남긴다 — 잘랐다는 것을 숨기면 "왜 뒷부분을 안 봤지"를 나중에 추적할 수 없다.
    """
    if not text:
        return None
    stripped = text.strip()
    if not stripped:
        return None
    limit = config.QUESTION_DESCRIPTION_MAX_CHARS
    if len(stripped) <= limit:
        return stripped
    return stripped[:limit].rstrip() + "…"


def _drawing_analysis_text(req: QuestionRequest) -> str | None:
    """첫 질문 프롬프트의 {drawing_analysis} 재료를 만든다.

    그림 서술(VLM)이 있으면 서술을 먼저, 탐지 객체 목록을 뒤에 붙인다(S15P11B209-704).

    reason: 객체 이름만으로는 "왜 하늘을 검게 칠했어?"·"사람이 웃고 있네" 같은
      색·표정·구도 기반 질문이 나올 수 없다. 그 정보는 VLM 서술에만 있다.
      둘을 함께 주는 이유는 서술이 놓친 객체를 목록이 보완하고, 목록이 설명하지 못하는
      맥락을 서술이 채우기 때문이다.
    ⚠️ 서술이 없으면(BE 미전달·분석 실패) 기존 객체 목록 동작을 그대로 유지한다.
    """
    description = _truncate_description(req.drawing_description)
    objects = (
        ", ".join(o.object_name or o.object_code for o in req.detected_objects)
        if req.detected_objects
        else None
    )
    if description and objects:
        return f"{description}\n(그림에서 찾은 것: {objects})"
    return description or objects


def _format_objects_for_log(req: QuestionRequest) -> str:
    """프롬프트에 실제로 들어간 객체 문자열(S15P11B209-710).

    `_drawing_analysis_text`와 같은 값을 남긴다 — 이 줄이 "LLM이 무엇을 보고 질문했는가"에
    대한 유일한 확정 증거다. 상세 로그가 꺼져 있으면 개수만 남긴다(아동 그림 내용 보호).
    """
    material = _drawing_analysis_text(req)
    if material is None:
        return "(없음)"
    if not config.DETECTION_LOG_DETAIL:
        # ⚠️ 서술은 객체 이름보다 훨씬 구체적인 아동 그림 내용이다(색·표정·구도).
        #   상세 로그가 꺼져 있으면 **내용은 남기지 않되**, 서술이 들어갔다는 사실은 남긴다.
        #   그래야 "LLM이 무엇을 보고 질문했는가"를 나중에 내용 없이도 구분할 수 있다.
        parts = [f"{len(req.detected_objects)}건"] if req.detected_objects else []
        if _truncate_description(req.drawing_description):
            parts.append("서술있음")
        return "+".join(parts) if parts else "(없음)"
    return material


def _format_target_for_log(target: DetectedObject | None) -> str:
    """대상 객체를 로그 한 조각으로. 코드는 내부 Enum이라 상세 여부와 무관하게 남긴다."""
    if target is None:
        return "-"
    if not config.DETECTION_LOG_DETAIL:
        return target.object_code
    return f"{target.object_name or target.object_code}({target.confidence:.2f})"


def _last_child_index(req: QuestionRequest) -> int | None:
    """가장 최근 아이 발화(텍스트 있는 것)의 인덱스. 없으면 None(=첫 질문)."""
    for index in range(len(req.recent_messages) - 1, -1, -1):
        message = req.recent_messages[index]
        if (message.sender_type or "").upper() == "CHILD" and (message.text or "").strip():
            return index
    return None


# 인젝션으로 걸린 과거 발화를 원문 대신 넣는 중립 표시(S15P11B209-742).
_SANITIZED_UTTERANCE = "(아이의 말)"


def _history_dicts(messages: list) -> list[dict]:
    """recent_messages → llm_client._format_history가 받는 [{"role","content"}] 형태로.

    과거 아이 발화 중 프롬프트 인젝션에 걸리는 것은 원문 대신 중립 표시로 치환한다(S15P11B209-742).
    현재 발화의 인젝션은 generate가 앞단에서 막지만, 과거 발화는 BE에 저장돼 history로 다시
    흘러들 수 있어 여기서 한 번 더 걸러 원문이 LLM에 닿지 않게 한다.
    """
    turns: list[dict] = []
    for m in messages:
        if not (m.text or "").strip():
            continue
        is_child = (m.sender_type or "").upper() == "CHILD"
        content = m.text
        if is_child and prompt_injection.scan(m.text):
            content = _SANITIZED_UTTERANCE
        turns.append({"role": "user" if is_child else "assistant", "content": content})
    return turns


# ── HTP 주제·대상 지시 블록 (S15P11B209-713) ────────────────────
# 프롬프트가 '지금 무슨 주제인지'를 몰라 다른 주제 명사를 집어오던 버그(709 원인 4)를 막는다.
# activityType·drawingSubject를 프롬프트에 못박아 다른 주제로 새지 않게 하고, 고른 대상 하나만 묻게 한다.
#
# ⚠️ 무엇을 못 박는가 — S15P11B209-788 B의 핵심 구분:
#   HTP는 아이가 그릴 주제가 집·나무·사람으로 정해져 있다. 그래서 **'지금 어느 주제 단계인가'는
#   활동이 정한 사실**이고 아이가 뒤집을 수 없다(다른 주제로 새면 709 계열 재발).
#   그러나 **그 그림 안의 각 부분이 무엇인지는 아이가 정한다** — 탐지가 '문'이라 해도 아이가
#   창문이라 하면 창문이다. 예전 문구("아이는 '집'을 그렸어. 이건 정해진 사실이야")는 이 둘을
#   뭉쳐 못 박아, 공통 프롬프트(conversation_common)의 "무조건 아이 말을 믿어"와 정면 충돌했다.
#   718 부정 재질문은 아이가 **칩(CHIP_NO)** 으로 부정한 경우만 처리하므로, **말로 정정한 경로**가
#   그 충돌에 그대로 노출됐다.
_SUBJECT_KO = {"HOUSE": "집", "TREE": "나무", "PERSON": "사람"}


def _other_subjects(subject: str | None) -> str:
    """현재 주제를 뺀 나머지 HTP 주제 이름(S15P11B209-788 H).

    예전 문구는 "다른 주제(집·나무·사람)로 넘어가지 마"라고 세 주제를 통째로 나열해
    **현재 주제까지 금지 목록에 넣었다** — 집 단계에서 집을 묻지 말라고 읽힐 수 있었다.
    """
    return "·".join(name for code, name in _SUBJECT_KO.items() if code != subject)


# 지시 문구는 ai/prompts/activity_block.txt가 소유한다(S15P11B209-832). 코드 안 문자열이던
# 것을 옮긴 이유: GPT에 나가는 지시문인데 prompts_registry 버전 추적 밖이라, 788에서 문구를
# 크게 고쳐도 promptVersion이 그대로였다(conv-htp@2.1.0+bd5e3622 → 동일). 버전은 같은데
# 동작이 다른 상태여서 792 평가 하네스로 전후를 구분할 수 없었다.
ACTIVITY_BLOCK_PROMPT = "activity_block"


def _block(key: str, **values) -> str:
    """활동 블록 구획 하나를 치환해 돌려준다."""
    return prompts_registry.sections(ACTIVITY_BLOCK_PROMPT)[key].format(**values)


def _target_line(req: QuestionRequest, target_name: str) -> str:
    """대상 객체 지시 한 줄 — 첫 질문에서만 '이것만'으로 좁힌다(S15P11B209-788 C).

    target_name은 아이 발화와 무관하게 신뢰도 최고순으로 뽑힌다(_target_for_purpose).
    아이가 이미 말한 뒤에도 "이 하나에 대해서만 물어봐"를 붙이면, 대화 프롬프트의
    "방금 한 말에서 이어지는 질문을 해. 갑자기 주제를 바꾸지 마"와 동시에 지시되어
    프롬프트가 스스로 "바꿔라/바꾸지 마라"를 요구한다.
    """
    key = "TARGET_FIRST" if _last_child_index(req) is None else "TARGET_FOLLOW_UP"
    return _block(key, target=target_name)


def _activity_block(
    req: QuestionRequest,
    target: DetectedObject | None,
    *,
    reask_candidates: bool = False,
) -> str:
    """activityType·drawingSubject·대상 객체를 프롬프트 지시 블록으로 만든다.

    - HTP: '지금 어느 주제 단계인가'만 확정 사실로 못박아 다른 주제로 넘어가지 못하게 하고,
      그림 안의 각 부분 이름은 아이 말에 따르게 한다(S15P11B209-788 B).
      고른 대상이 있으면 그 하나만, 없으면 주제 그림 전체를 묻게 한다.
    - ART_DIARY: 주제 개념이 없고, 탐지 이름도 믿지 않게 한다 — sketch 가중치는 오탐이 잦아
      이름의 근거는 탐지 목록이 아니라 그림 서술과 아이 말이다.
    - activityType이 없으면(구 BE·주제 미전달) 주제 제약 없이 기존 동작을 유지한다.
    반복 방지: 이미 물어본 게 있으면 새로운 것을 묻도록 덧붙인다(대상 선택에서도 이미 배제됨).
    reask_candidates(S15P11B209-718): 아이가 탐지를 부정해 후보 칩으로 다시 묻는 경우, 보기 중에서
      고르도록 짧게 되묻는 지시를 덧붙인다(보기 내용은 칩으로 제시하므로 프롬프트엔 넣지 않는다).
    """
    subject_ko = _SUBJECT_KO.get(req.drawing_subject or "")
    target_name = (
        (target.object_name or target.object_code) if target is not None else None
    )
    lines: list[str] = []
    if req.activity_type == "HTP" and subject_ko:
        # 못 박는 것은 '활동 단계'다 — 그림 내용의 이름이 아니다(788 B).
        lines.append(
            _block(
                "HTP",
                subject=subject_ko,
                other_subjects=_other_subjects(req.drawing_subject),
            )
        )
        lines.append(
            _target_line(req, target_name)
            if target_name
            else _block("HTP_WHOLE", subject=subject_ko)
        )
    elif req.activity_type == "ART_DIARY":
        # 그림일기 탐지 모델(sketch)은 오탐이 잦다 — 이름의 근거는 탐지 목록이 아니라
        # 그림 서술과 아이 말이다(788 B, 활동별 판단).
        lines.append(_block("ART_DIARY"))
        if target_name:
            lines.append(_target_line(req, target_name))
    elif target_name:
        lines.append(_block("TARGET_ONLY", target=target_name))
    if reask_candidates:
        lines.append(_block("REASK_CANDIDATES"))
    if req.asked_object_codes:
        lines.append(_block("ASKED_ALREADY"))
    return "\n".join(lines)


def _build_messages(
    req: QuestionRequest,
    *,
    purpose: str | None = None,
    target: DetectedObject | None = None,
    reask_candidates: bool = False,
) -> list[dict]:
    """요청 문맥 → GMS messages. draft 프롬프트를 재사용해 컨텍스트 기반으로 생성한다.

    - 아이 발화가 아직 없으면: 첫 질문 프롬프트(그림 탐지 객체 기반).
    - 아이 발화가 있으면: 다음 질문 프롬프트(마지막 발화 + 그 이전 이력).
    연령대는 아이 나이를 넘기고, 난이도별 길이·어휘·말투 규칙을 덧붙인다.

    purpose·target을 넘기면 그대로 쓴다(generate가 응답과 동일한 값을 프롬프트에 싣기 위함).
    안 넘기면 여기서 계산한다 — _build_messages를 직접 호출하는 테스트 편의용(S15P11B209-713).
    """
    if purpose is None:
        purpose = _pick_question_purpose(req)
        if purpose == "OBJECT_DESCRIPTION":
            target = _target_for_purpose(req, purpose)

    age_band = str(req.child_age)
    drawing = _drawing_analysis_text(req)
    activity_block = _activity_block(req, target, reask_candidates=reask_candidates)
    last_child = _last_child_index(req)

    if last_child is None:
        system = llm_client.render_first_question_prompt(
            drawing,
            age_band=age_band,
            activity_block=activity_block,
            activity_type=req.activity_type,
            difficulty=req.difficulty,
            drawing_subject=req.drawing_subject,
        )
        trigger = llm_client.FIRST_QUESTION_TRIGGER
    else:
        utterance = req.recent_messages[last_child].text or ""
        history = _history_dicts(req.recent_messages[:last_child])
        system = llm_client.render_next_question_prompt(
            utterance,
            drawing_analysis=drawing,
            history=history,
            age_band=age_band,
            activity_block=activity_block,
            activity_type=req.activity_type,
            difficulty=req.difficulty,
            drawing_subject=req.drawing_subject,
        )
        trigger = llm_client.NEXT_QUESTION_TRIGGER

    return [
        {"role": "system", "content": system},
        {"role": "user", "content": trigger},
    ]


# ── 질문 목적 ↔ 대상 객체 ↔ 선택 Chip 정합성 (S15P11B209-594) ────
# 세 값이 서로 어긋나면 아동 화면에 엉뚱한 칩·객체가 붙는다. 목적을 먼저 정하고
# 대상 객체·칩을 그 목적에 맞춰 파생시켜 항상 일관되게 만든다.
#   - OBJECT_DESCRIPTION: 특정 객체를 묻는다 → 대상 객체 있음, 예/아니오/더 말하기 칩.
#   - DRAWING_CONTEXT: 그림 전체 맥락을 묻는다 → 대상 객체 없음, 실제/상상 칩.
#   - EXPRESSION: 마음·느낌을 묻는다 → 대상 객체 없음, 감정 칩.
#   - FOLLOW_UP: 아이 발화에 이어 묻는다 → 대상 객체 없음, 예/아니오/더 말하기 칩.
VALID_PURPOSES = {"OBJECT_DESCRIPTION", "DRAWING_CONTEXT", "EXPRESSION", "FOLLOW_UP"}

# 목적별 선택 Chip. 아동 화면에 그대로 노출되므로 쉽고 따뜻한 말만. code는 응답 안에서 유일.
_OPTIONS_BY_PURPOSE: dict[str, list[QuestionOption]] = {
    "OBJECT_DESCRIPTION": [
        QuestionOption(code="CHIP_YES", label="응, 맞아!"),
        QuestionOption(code="CHIP_NO", label="음, 아니야"),
        QuestionOption(code="CHIP_TELL_MORE", label="더 이야기해 줄래"),
    ],
    "DRAWING_CONTEXT": [
        QuestionOption(code="CHIP_REAL", label="진짜 있었던 일이야"),
        QuestionOption(code="CHIP_IMAGINE", label="상상해서 그렸어"),
        QuestionOption(code="CHIP_TELL_MORE", label="더 이야기해 줄래"),
    ],
    "EXPRESSION": [
        QuestionOption(code="CHIP_GOOD", label="좋아!"),
        QuestionOption(code="CHIP_SOSO", label="그냥 그래"),
        QuestionOption(code="CHIP_NOT_SURE", label="잘 모르겠어"),
    ],
    "FOLLOW_UP": [
        QuestionOption(code="CHIP_YES", label="응, 맞아!"),
        QuestionOption(code="CHIP_NO", label="음, 아니야"),
        QuestionOption(code="CHIP_TELL_MORE", label="더 이야기해 줄래"),
    ],
}


def _pick_question_purpose(req: QuestionRequest) -> str:
    """질문 목적 결정.

    아이가 이미 말했으면 그 말에 이어가는 FOLLOW_UP, 첫 질문이면 탐지 객체가 있을 때
    그 객체를 묻는 OBJECT_DESCRIPTION, 없으면 그림 전체를 묻는 DRAWING_CONTEXT.
    (EXPRESSION은 질문 내용 기반 분류가 필요해 후속 프롬프트 구조화 과제로 둔다.)
    """
    if any((m.sender_type or "").upper() == "CHILD" for m in req.recent_messages):
        return "FOLLOW_UP"
    if req.detected_objects:
        return "OBJECT_DESCRIPTION"
    return "DRAWING_CONTEXT"


def _options_for_purpose(purpose: str) -> list[QuestionOption]:
    """목적에 맞는 선택 Chip. 모르는 목적이면 무난한 예/아니오/더 말하기."""
    return list(_OPTIONS_BY_PURPOSE.get(purpose, _OPTIONS_BY_PURPOSE["FOLLOW_UP"]))


# 마음·느낌을 묻는 질문 표시어 (S15P11B209-650). 이 말이 있으면 EXPRESSION으로 보고 감정 칩을 붙인다.
# 목적 분류(_pick_question_purpose)는 EXPRESSION을 고르지 못했다 — 그건 생성 전엔 알 수 없고
# 생성된 문장 내용을 봐야 알 수 있어서다. 그래서 생성 후 문장으로 판별한다. 감정 칩이 안 어울리는
# 객체 질문("이 색 좋아?")까지 잡지 않도록 표시어를 마음·감정에 좁게 둔다.
_EMOTION_QUESTION_MARKERS = (
    "기분",
    "느낌",
    "마음",
    "행복",
    "슬펐",
    "슬퍼",
    "무서웠",
    "속상",
    "즐거웠",
    "설레",
)


def _is_expression_question(text: str) -> bool:
    """생성된 질문이 아이의 마음·느낌을 묻는지 간단 분류한다(감정 칩 정합용)."""
    return any(marker in text for marker in _EMOTION_QUESTION_MARKERS)


def _target_for_purpose(req: QuestionRequest, purpose: str) -> DetectedObject | None:
    """대상 객체는 특정 객체를 묻는 OBJECT_DESCRIPTION일 때만 붙인다(목적과 정합).

    요청의 detectedObjects는 BE가 이미 검증(objectCode·confidence·정규화 bbox)한 값이라
    그대로 되돌려도 계약을 통과한다.

    선택 규칙(S15P11B209-713):
    - 이미 물어본 객체(askedObjectCodes)는 후보에서 뺀다 → 같은 것을 두 번 묻지 않는다.
    - HTP면 현재 주제 그룹 객체(집 단계=HOUSE·HOUSE_*)를 먼저 고른다. 주제 객체가 없을 때만
      배경(SCENERY) 등 나머지에서 고른다(결정: 주제 우선·소진 후 배경). 집 단계에서 배경 나무가
      대뜸 대상이 되어 "이 나무는?"이 나오던 709 경로가 이걸로 대부분 사라진다.
    - 남은 후보 중 신뢰도 최고를 고른다. 후보가 없으면 None(호출부가 그림 전체 질문으로 전환).
    """
    if purpose != "OBJECT_DESCRIPTION" or not req.detected_objects:
        return None
    asked = set(req.asked_object_codes)
    available = [o for o in req.detected_objects if o.object_code not in asked]
    if not available:
        return None
    if req.activity_type == "HTP" and req.drawing_subject:
        subject = req.drawing_subject
        subject_objs = [
            o
            for o in available
            if o.object_code == subject or o.object_code.startswith(f"{subject}_")
        ]
        pool = subject_objs or available
    else:
        pool = available
    return max(pool, key=lambda o: o.confidence)


# ── 탐지 부정 시 후보 칩 재질문 (S15P11B209-718) ──────────────────
# 아이가 "아니야"(CHIP_NO)로 탐지를 부정하면, 이미 탐지된 다른 객체를 후보 칩으로 다시 묻는다.
# 신뢰도 하한(YOLO_CONF_THRESHOLD)은 건드리지 않는다 — 후보는 '이미 탐지된' detectedObjects에서만 뽑는다.
_NEGATION_CODE = "CHIP_NO"
_ESCAPE_CODE = "CAND_NONE"  # "이 중에 없어" — 후보를 모두 거부하는 탈출 칩
_MAX_CANDIDATES = 3


def _last_child_selected_codes(req: QuestionRequest) -> list[str]:
    """가장 최근 아이 메시지의 선택 칩 코드(없으면 빈 목록)."""
    for message in reversed(req.recent_messages):
        if (message.sender_type or "").upper() == "CHILD":
            return list(message.selected_option_codes or [])
    return []


def _negation_count(req: QuestionRequest) -> int:
    """아이가 최근 문맥에서 CHIP_NO로 부정한 횟수(연속 부정 방지 판단용)."""
    return sum(
        1
        for m in req.recent_messages
        if (m.sender_type or "").upper() == "CHILD"
        and m.selected_option_codes
        and _NEGATION_CODE in m.selected_option_codes
    )


def _candidate_options(req: QuestionRequest) -> list[QuestionOption]:
    """부정 재질문용 후보 칩 — 이미 탐지된 객체 중 아직 안 물어본 상위 3개 + 탈출 칩.

    라벨은 표시명(object_name, S15P11B209-711)을 쓴다 — 내부 코드·영문을 아동 화면에 노출하지
    않는다. 표시명이 없는 객체는 후보에서 뺀다(코드 노출 금지). 후보가 하나도 없으면 빈 목록.
    """
    asked = set(req.asked_object_codes)
    pool = [
        o
        for o in req.detected_objects
        if o.object_code not in asked and (o.object_name or "").strip()
    ]
    pool.sort(key=lambda o: o.confidence, reverse=True)
    top = pool[:_MAX_CANDIDATES]
    if not top:
        return []
    options = [
        QuestionOption(code=f"CAND_{index}", label=o.object_name)
        for index, o in enumerate(top, start=1)
    ]
    options.append(QuestionOption(code=_ESCAPE_CODE, label="이 중에 없어"))
    return options


# ── 질문 내용 맞춤 답변 칩 (S15P11B209-747, 방향 D 혼합) ─────────
# 목적별 고정 칩(_OPTIONS_BY_PURPOSE)은 질문 내용과 안 맞는다("무슨 색?"에 응/아니야). 그래서
# 질문 유형(색·무엇·누구·어디)을 규칙으로 분류해 맞춤 칩을 주고(B), 규칙에 안 걸리는 wh-질문은
# LLM 2차 호출로 후보를 받는다(A). 둘 다 없으면 목적별 generic으로 폴백. 어느 경로든 마지막에
# 열린 탈출 '더 이야기해 줄래'를 붙여 아이가 선택지에 갇히지 않게 한다.
_TELL_MORE = QuestionOption(code="CHIP_TELL_MORE", label="더 이야기해 줄래")
_COLOR_CHIPS = ["빨간색", "노란색", "파란색"]  # 큐레이션 안전 라벨(우리 값이라 안전검증 불필요)
_WHO_CHIPS = ["엄마", "아빠", "나", "친구"]
_WHERE_CHIPS = ["집 안", "집 밖", "방 안"]

_RE_COLOR = re.compile(r"무슨\s*색|어떤\s*색|색깔|색이(?:야|니|에요|예요)")
_RE_WHO = re.compile(r"누구|누가")
_RE_WHERE = re.compile(r"어디")
_RE_WHAT = re.compile(r"뭐야|뭐를|무엇|무슨\s*그림|어떤\s*그림|뭘\s*그렸")
# wh-의문사 — 있으면 예/아니오형이 아니다(규칙 미분류 시 LLM으로 넘긴다).
_RE_WH = re.compile(r"무엇|뭐|무슨|어떤|누구|누가|어디|왜|어떻게|언제|몇")


def _labeled_chips(labels: list[str], *, escape: str | None) -> list[QuestionOption]:
    """라벨 목록 → code 유일한 QuestionOption. 항상 열린 탈출로 끝낸다(escape 있으면 그것 + 더 이야기)."""
    chips = [
        QuestionOption(code=f"CHIP_C{i}", label=label)
        for i, label in enumerate(labels, start=1)
    ]
    if escape:
        chips.append(QuestionOption(code="CHIP_OTHER", label=escape))
    chips.append(_TELL_MORE)
    return chips


def _content_chips(text: str, req: QuestionRequest) -> list[QuestionOption] | None:
    """질문 유형을 규칙으로 분류해 맞춤 칩(B). 못 맞추면 None.

    색·누구·어디는 큐레이션 라벨, '무엇'은 이미 탐지된 객체 후보(718 로직 재사용)를 쓴다.
    감정(기분/느낌)은 상위에서 EXPRESSION(650)으로 처리하므로 여기서 다루지 않는다.
    """
    if _RE_COLOR.search(text):
        return _labeled_chips(_COLOR_CHIPS, escape="다른 색이야")
    if _RE_WHO.search(text):
        return _labeled_chips(_WHO_CHIPS, escape="다른 사람이야")
    if _RE_WHERE.search(text):
        return _labeled_chips(_WHERE_CHIPS, escape="다른 데야")
    if _RE_WHAT.search(text):
        return _candidate_options(req) or None  # 탐지 후보 + '이 중에 없어'
    return None


def _safe_chip_labels(raw_lines: list[str]) -> list[str]:
    """LLM이 준 후보 줄을 아동 안전 라벨로 정화한다(747 · 안전 파이프라인 596/597 재사용).

    각 줄을 question_safety로 판정·정화하고 차단·빈값·너무 긴 것은 버린다. 아동 화면에 그대로
    나가는 텍스트라 통과한 것만 라벨로 쓴다(최대 3개, 중복 제거).
    """
    labels: list[str] = []
    seen: set[str] = set()
    for line in raw_lines:
        cand = line.strip().lstrip("-·•0123456789. ").strip()
        if not cand or len(cand) > 12:
            continue
        verdict = question_safety.evaluate(cand)
        if verdict.blocked:
            continue
        clean = (verdict.sanitized_text or "").strip()
        if not clean or clean in seen:
            continue
        seen.add(clean)
        labels.append(clean)
        if len(labels) == 3:
            break
    return labels


def _llm_answer_chips(
    text: str, req: QuestionRequest, request_id: str
) -> list[QuestionOption] | None:
    """규칙에 안 걸린 wh-질문의 답변 후보를 2차 GMS 호출로 받는다(747, 방향 A).

    질문 프롬프트와 분리된 짧은 best-effort 호출이다 — 재시도 없이 한 번만, 실패하면 None을
    돌려 상위에서 generic 칩으로 폴백한다(질문 응답을 지연·차단시키지 않는다).
    받은 후보는 _safe_chip_labels로 아동 안전 정화 후 쓴다.

    프롬프트 문구는 ai/prompts/answer_chips.txt에 있다(S15P11B209-788 부수). 코드 상수로
    두면 아동 화면에 나갈 칩을 만드는 프롬프트가 prompts_registry 버전 추적 밖에 남는다.
    """
    system = prompts_registry.load("answer_chips").format(
        age_band=req.child_age, question=text
    )
    try:
        client = get_client().with_options(
            timeout=config.QUESTION_LLM_TIMEOUT_SEC, max_retries=0
        )
        resp = client.chat.completions.create(
            model=config.LLM_MODEL,
            messages=[
                {"role": "system", "content": system},
                {"role": "user", "content": "답 3개를 줄바꿈으로 줘."},
            ],
            temperature=0.4,
        )
        raw = resp.choices[0].message.content or ""
    except OpenAIError as e:
        # 칩 생성 실패는 질문 응답을 막지 않는다 — 유형만 남기고 generic으로 폴백.
        logger.warning(
            "답변 칩 생성 실패(폴백): type=%s request_id=%s", type(e).__name__, request_id
        )
        return None
    labels = _safe_chip_labels(raw.splitlines())
    return _labeled_chips(labels, escape=None) if labels else None


def _is_consistent(
    purpose: str,
    target: DetectedObject | None,
    options: list[QuestionOption] | None,
    option_allowed: bool,
) -> bool:
    """목적·대상·칩·응답 방식이 서로 정합한지 검증한다(BE isContractValidFor 사전 방어).

    - 목적은 계약 허용값이어야 한다.
    - 대상 객체는 OBJECT_DESCRIPTION일 때만 허용(다른 목적엔 붙지 않는다).
    - OPTION 허용 시 칩은 비어 있지 않고 code가 유일해야 하며, 비허용 시 칩은 None.
    """
    if purpose not in VALID_PURPOSES:
        return False
    if target is not None and purpose != "OBJECT_DESCRIPTION":
        return False
    if option_allowed:
        if not options:
            return False
        codes = [o.code for o in options]
        if len(codes) != len(set(codes)):
            return False
    elif options is not None:
        return False
    return True


# 위기 신호 감지 시 아이에게 건네는 안전·지지형 응답(S15P11B209-593).
# 위기를 직접 언급·캐묻지 않고, 대화를 끊지 않으며, 아이에게 이야기할 여지를 부드럽게 준다.
CRISIS_SAFE_QUESTION = "이야기해줘서 고마워. 네 마음은 참 소중해. 지금 더 하고 싶은 이야기가 있어?"
_CRISIS_SAFE_OPTIONS = [
    QuestionOption(code="CHIP_YES", label="응, 더 이야기할래"),
    QuestionOption(code="CHIP_NO", label="아니, 괜찮아"),
    QuestionOption(code="CHIP_NOT_SURE", label="잘 모르겠어"),
]


def _crisis_safe_response(req: QuestionRequest, started: float) -> QuestionResponse:
    """위기 감지 시 대화를 끊지 않고 건네는 결정적 안전·지지형 응답.

    GMS를 호출하지 않는다 — 위기 상황에서 LLM이 위기를 캐묻거나 잘못된 조언을 하지 않도록
    사전에 검토된 고정 문구를 쓴다. safetyResult는 PASSED라 BE가 정상 저장하고 대화가 이어진다.
    """
    option_allowed = "OPTION" in req.allowed_response_modes
    return QuestionResponse(
        question_text=CRISIS_SAFE_QUESTION,
        question_purpose="EXPRESSION",
        options=list(_CRISIS_SAFE_OPTIONS) if option_allowed else None,
        target_object=None,
        fallback_used=False,
        safety_result=SafetyResult(
            status="PASSED", rule_version=req.safety_rule_version, block_reason_code=None
        ),
        model_name=config.LLM_MODEL,
        # GMS를 호출하지 않았으므로 파생 모델 ID가 없다 — 엔진명으로 대신 기록한다.
        model_version=config.LLM_MODEL,
        prompt_version=PROMPT_VERSION,
        processing_time_ms=int((time.monotonic() - started) * 1000),
    )


# ── 프롬프트 인젝션 차단 (S15P11B209-742) ───────────────────────
# 아이 발화가 프롬프트를 조작하려 하면(예: "지금까지의 모든 지시를 잊고~") LLM에 전달하지 않고
# 결정적 재질문으로 되묻는다. 위기 차단과 달리 대화는 끊지 않는다(정상적인 되묻기).
REASK_QUESTION = "미안, 잘 못 들었어. 그림에서 뭘 그렸는지 다시 이야기해줄래?"


def _detect_injection(req: QuestionRequest) -> str | None:
    """가장 최근 아이 발화(프롬프트의 {child_utterance}가 될 것)에서 인젝션 신호를 찾는다."""
    index = _last_child_index(req)
    if index is None:
        return None
    return prompt_injection.scan(req.recent_messages[index].text or "")


def _reask_response(req: QuestionRequest, started: float) -> QuestionResponse:
    """인젝션 감지 시 GMS 호출 없이 돌려주는 결정적 재질문 응답.

    조작 입력이 출력에 절대 영향 못 주도록 검토된 고정 문구를 쓴다. safetyResult는 PASSED라
    BE가 정상 저장하고 대화가 이어진다. 목적은 그림 전체를 다시 여는 DRAWING_CONTEXT.
    """
    option_allowed = "OPTION" in req.allowed_response_modes
    return QuestionResponse(
        question_text=REASK_QUESTION,
        question_purpose="DRAWING_CONTEXT",
        options=(
            list(_OPTIONS_BY_PURPOSE["DRAWING_CONTEXT"]) if option_allowed else None
        ),
        target_object=None,
        fallback_used=False,
        safety_result=SafetyResult(
            status="PASSED", rule_version=req.safety_rule_version, block_reason_code=None
        ),
        model_name=config.LLM_MODEL,
        # GMS를 호출하지 않았으므로 파생 모델 ID가 없다 — 엔진명으로 대신 기록한다.
        model_version=config.LLM_MODEL,
        prompt_version=PROMPT_VERSION,
        processing_time_ms=int((time.monotonic() - started) * 1000),
    )


def _detect_crisis(req: QuestionRequest) -> str | None:
    """아이 발화에서 자해·학대·위기 신호를 탐지한다(S15P11B209-593).

    곰돌이(AI) 발화는 우리가 만든 것이라 검사하지 않고, senderType이 CHILD인 발화만 본다.
    신호가 있으면 사유 코드를 반환한다(없으면 None).
    """
    child_texts = [
        m.text
        for m in req.recent_messages
        if (m.sender_type or "").upper() == "CHILD" and m.text
    ]
    return crisis_detection.scan(child_texts)


def _evaluate_safety(
    question_text: str, rule_version: str, request_id: str
) -> tuple[SafetyResult, str]:
    """생성된 질문을 안전 판정 파이프라인에 통과시킨다(S15P11B209-596).

    question_safety.evaluate가 형식 정화 + 진단표현·위기 소재 차단을 순서대로 판정한다.
    - 차단이면 SafetyBlockedError를 던진다 → 엔드포인트가 422 AI_SAFETY_POLICY_BLOCKED로
      매핑(BE는 저장 없이 폴백 템플릿으로 대체).
    - 통과면 (PASSED SafetyResult, 정화된 질문 텍스트)를 돌려준다 — 정화본을 아동 화면에 쓴다.

    ⚠️ 차단 시에도 질문 원문은 로그에 남기지 않는다 — 사유 코드만.
    """
    verdict = question_safety.evaluate(question_text)
    if verdict.blocked:
        logger.warning(
            "생성 질문 안전 차단: reason=%s request_id=%s",
            verdict.block_reason_code,
            request_id,
        )
        raise SafetyBlockedError(
            verdict.block_reason_code or "UNSPECIFIED", rule_version
        )
    safety = SafetyResult(
        status="PASSED", rule_version=rule_version, block_reason_code=None
    )
    return safety, verdict.sanitized_text


# ── GMS 호출 + 제한적 재시도 ────────────────────────────────────
def _is_retryable(error: OpenAIError) -> bool:
    """일시 오류(재시도 가치 있음)인지 분류.

    - APIConnectionError: 연결 실패·타임아웃(APITimeoutError는 하위 클래스) → 재시도
    - APIStatusError 5xx: 게이트웨이/서버 일시 장애 → 재시도
    - 그 외(4xx: 인증·요청 오류·429 포함): 재시도해도 같은 결과 → 즉시 실패
    """
    if isinstance(error, APIConnectionError):
        return True
    if isinstance(error, APIStatusError):
        return error.status_code >= 500
    return False


def _call_gms_with_retry(messages: list[dict], request_id: str) -> tuple[str, str]:
    """GMS 질문 생성 호출. 성공 시 (질문 텍스트, 실제 서빙 모델명)을 반환한다.

    - with_options(timeout=4s, max_retries=0):
      공용 클라이언트의 60s timeout과 SDK 자체 재시도(기본 2회)를 이 경로에서만 끈다.
      reason: SDK 내부 재시도가 살아 있으면 우리 백오프와 겹쳐 BE 15s 예산을 넘는다.
    - 백오프: base × 2^(재시도 차수-1) → 0.5s, 1.0s.
    """
    client = get_client().with_options(
        timeout=config.QUESTION_LLM_TIMEOUT_SEC,
        max_retries=0,
    )
    total_attempts = config.QUESTION_LLM_MAX_RETRIES + 1
    last_error: OpenAIError | None = None
    for attempt in range(1, total_attempts + 1):
        if attempt > 1:
            time.sleep(config.QUESTION_LLM_BACKOFF_BASE_SEC * (2 ** (attempt - 2)))
        try:
            resp = client.chat.completions.create(
                model=config.LLM_MODEL,
                messages=messages,
                temperature=0.6,  # 아동 대화는 튀지 않게 다소 낮게(llm_client와 동일 기준)
            )
            text = resp.choices[0].message.content or ""
            served_model = getattr(resp, "model", "") or ""
            return text, served_model
        except OpenAIError as e:
            # ⚠️ messages(아이 발화 포함 가능)는 로그 금지 — 유형·시도 횟수·request_id만.
            logger.warning(
                "GMS 질문 생성 실패: type=%s attempt=%d/%d request_id=%s",
                type(e).__name__,
                attempt,
                total_attempts,
                request_id,
            )
            if not _is_retryable(e):
                raise UpstreamError("AI_UPSTREAM_REJECTED", type(e).__name__) from e
            last_error = e
    raise UpstreamError(
        "AI_UPSTREAM_UNAVAILABLE",
        type(last_error).__name__ if last_error else "Unknown",
    ) from last_error


# ── 진입점 ──────────────────────────────────────────────────────
def generate(req: QuestionRequest, request_id: str) -> QuestionResponse:
    """질문 1건 생성 — BE isContractValidFor를 통과하는 응답을 조립한다.

    Raises:
        UpstreamError: GMS 최종 실패(→ 502, BE 폴백 템플릿 경로).
        SafetyBlockedError: 안전 정책 차단(→ 422, BE 사용자 422 경로).
    """
    started = time.monotonic()

    # 위기 신호(자해·학대·위기 의도)는 대화를 끊지 않고 안전·지지형 응답으로 이어간다
    # (S15P11B209-593). 아이에게 dead-end(422)를 주는 대신, 위기를 캐묻지 않는 결정적
    # 안전 응답을 돌려주고 위기 사실은 서버 경보 로그(사유 코드)로 남긴다.
    crisis_reason = _detect_crisis(req)
    if crisis_reason:
        # ⚠️ 아이 발화 원문은 남기지 않는다 — 사유 코드·request_id만.
        logger.warning(
            "위기 신호 감지 — 안전 응답으로 지속: reason=%s request_id=%s",
            crisis_reason,
            request_id,
        )
        # 같은 위기라도 보호자에게는 제대로 된 안내를 전한다(S15P11B209-598). 문구 생성 규칙은
        # crisis_guidance가 검토된 템플릿으로 만든다. 보호자에게 '띄우는' BE 배선(알림/화면 필드)은
        # 계약 확장이 필요한 공동 후속이라, 지금은 안내 준비 사실만 서버 신호로 남긴다(원문 없음).
        alert = crisis_guidance.guidance_for(crisis_reason)
        if alert is not None:
            logger.warning(
                "보호자 위기 안내 준비: severity=%s reason=%s request_id=%s",
                alert.severity,
                alert.reason_code,
                request_id,
            )
        else:
            # 보호자에게 자동 전달하지 않는 사유(학대 진술 등)는 안내가 없다 — 그렇다고 신호를
            # 조용히 흘리면 아무도 모른다. 전문가 검토 경로로 남긴다는 사실을 로그에 남긴다
            # (S15P11B209-890). 여기서도 아이 발화 원문은 남기지 않는다.
            note = crisis_guidance.expert_note_for(crisis_reason)
            if note is not None:
                logger.warning(
                    "보호자 자동 안내 보류 — 전문가 검토 경로: severity=%s reason=%s "
                    "expert_review=%s request_id=%s",
                    note.severity,
                    note.reason_code,
                    note.requires_expert_review,
                    request_id,
                )
        return _crisis_safe_response(req, started)

    # 프롬프트 인젝션(맥락 파괴 시도)은 LLM에 전달하지 않고 결정적 재질문으로 되묻는다
    # (S15P11B209-742). 위기와 달리 대화를 끊지 않는다 — 정상적인 "다시 말해줄래?"로 이어간다.
    injection_reason = _detect_injection(req)
    if injection_reason:
        # ⚠️ 아이 발화 원문은 남기지 않는다 — 사유 코드·request_id만.
        logger.warning(
            "프롬프트 인젝션 차단 — 재질문: reason=%s request_id=%s",
            injection_reason,
            request_id,
        )
        return _reask_response(req, started)

    # 목적·대상을 GMS 호출 전에 정해 프롬프트에 그대로 싣는다(S15P11B209-713) — 질문 문장과
    # 응답 targetObject가 같은 객체를 가리키게 하고, HTP면 주제를 벗어난 명사가 안 나오게 한다.
    option_allowed = "OPTION" in req.allowed_response_modes
    purpose = _pick_question_purpose(req)
    target = _target_for_purpose(req, purpose)
    if purpose == "OBJECT_DESCRIPTION" and target is None:
        # 주제 객체가 없거나 후보를 모두 물어봤으면 특정 객체 대신 그림 전체를 묻는다.
        purpose = "DRAWING_CONTEXT"

    # 탐지 부정 처리(S15P11B209-718). 아이가 방금 고른 칩으로 분기한다.
    #   - 탈출 칩("이 중에 없어") → 그림 전체를 다시 여는 질문.
    #   - 부정("아니야") → 이미 탐지된 다른 객체를 후보 칩으로 재질문. 단 연속 부정(2회 이상)이면
    #     후보를 또 들이밀지 않고 열린 질문으로 넘어간다(아이가 계속 부정당하는 경험 방지, 9절).
    candidate_options: list[QuestionOption] | None = None
    reask_candidates = False
    selected_codes = _last_child_selected_codes(req)
    if _ESCAPE_CODE in selected_codes:
        purpose, target = "DRAWING_CONTEXT", None
    elif _NEGATION_CODE in selected_codes:
        cand = (
            _candidate_options(req)
            if option_allowed and _negation_count(req) < 2
            else []
        )
        if cand:
            purpose, target = "FOLLOW_UP", None
            candidate_options = cand
            reask_candidates = True
        else:
            purpose, target = "DRAWING_CONTEXT", None

    messages = _build_messages(
        req, purpose=purpose, target=target, reask_candidates=reask_candidates
    )
    text, served_model = _call_gms_with_retry(messages, request_id)
    text = text.strip()
    if not text:
        # 빈 질문은 아동 화면에 내보낼 수 없다 → 실패로 취급해 BE 폴백 템플릿에 맡긴다.
        raise UpstreamError("AI_EMPTY_COMPLETION", "EmptyCompletion")

    # 안전 판정 파이프라인 통과 후 정화된 질문을 쓴다(차단이면 여기서 422로 올린다).
    safety, text = _evaluate_safety(text, req.safety_rule_version, request_id)
    if not text:
        # 정화 후 남는 게 없으면(기호뿐이었으면) 빈 출력 — 폴백 템플릿에 맡긴다.
        raise UpstreamError("AI_EMPTY_COMPLETION", "EmptyCompletion")

    # 생성된 질문이 마음·느낌을 묻는 문장이면 EXPRESSION으로 재분류해 감정 칩을 붙인다
    # (S15P11B209-650: 칩을 '질문 내용'과 맞춘다). 목적은 생성 전에 정하지만 감정 질문 여부는
    # 문장을 봐야 알 수 있어 여기서 보정한다. 부정 후보 재질문(718) 중에는 그 칩을 유지한다.
    if candidate_options is None and _is_expression_question(text):
        purpose, target = "EXPRESSION", None

    # 칩·정합성은 위(프롬프트 조립 전)에서 정한 목적·대상을 그대로 쓴다 — 프롬프트에 실은 것과
    # 응답 targetObject가 어긋나지 않게 한다(S15P11B209-713). 부정 재질문이면 후보 칩(718)을 쓴다.
    # OPTION 비허용이면 반드시 null — 빈 배열도 계약 위반이다(isContractValidFor).
    if not option_allowed:
        options = None  # OPTION 비허용 → 칩 없음(빈 배열도 계약 위반)
    elif candidate_options is not None:
        options = candidate_options  # 부정 재질문 후보(718)
    elif _NEGATION_CODE in selected_codes or _ESCAPE_CODE in selected_codes:
        # 부정/탈출 뒤 열린 질문(718) — 아이가 거부·탈출한 뒤라 후보를 다시 들이밀지 않고
        # 목적별 generic 칩을 쓴다(747의 '무엇→후보' 규칙이 재제시하는 것을 막는다).
        options = _options_for_purpose(purpose)
    elif purpose == "EXPRESSION":
        options = _options_for_purpose(purpose)  # 감정 칩(650)
    else:
        # 질문 내용 맞춤 칩(747, 방향 D): 규칙(B) → LLM 2차(A) → 목적별 generic 폴백.
        options = _content_chips(text, req)
        if options is None and _RE_WH.search(text):
            # 2차 GMS 호출은 BE 15s 예산 안에서만 — 이미 많이 썼으면 건너뛰고 generic으로.
            if time.monotonic() - started < config.QUESTION_LLM_TIMEOUT_SEC * 2:
                options = _llm_answer_chips(text, req, request_id)
        if options is None:
            options = _options_for_purpose(purpose)
    if not _is_consistent(purpose, target, options, option_allowed):
        # 정합성이 깨진 조합은 아동 화면에 내보내지 않는다 → 실패로 돌려 BE 폴백에 맡긴다.
        raise UpstreamError("AI_INCONSISTENT_RESPONSE", "Consistency")

    # 생성된 질문 원문은 남기지 않는다(가드레일). 대신 "어떤 재료로 만들었는가"를 남겨
    # 분석 로그의 [필터] 줄과 drawingSessionId로 이어붙일 수 있게 한다.
    # activityType·drawingSubject를 함께 남겨 어느 HTP 단계였는지 로그만으로 판별한다
    # (S15P11B209-712). 값이 없으면(그림일기·주제 미전달 요청) "-"로 남긴다.
    logger.info(
        "[질문] request_id=%s drawingSessionId=%s basisAnalysisId=%s "
        "activityType=%s drawingSubject=%s purpose=%s target=%s | %s",
        request_id,
        req.drawing_session_id,
        req.basis_analysis_id if req.basis_analysis_id is not None else "-",
        req.activity_type or "-",
        req.drawing_subject or "-",
        purpose,
        _format_target_for_log(target),
        _format_objects_for_log(req),
    )

    return QuestionResponse(
        question_text=text,
        question_purpose=purpose,
        options=options,
        target_object=target,
        fallback_used=False,  # AI 서버 자체 폴백 없음 — 폴백 템플릿은 BE 소유
        safety_result=safety,
        model_name=config.LLM_MODEL,
        # modelVersion: GMS가 실제 서빙한 모델 ID(예: gpt-4o-mini-2024-07-18) — 재현성 기록.
        model_version=served_model or config.LLM_MODEL,
        # 이번 생성이 '실제로 쓴' 활동 변형만 담는다(S15P11B209-786).
        prompt_version=llm_client.prompt_version_for(req.activity_type),
        processing_time_ms=int((time.monotonic() - started) * 1000),
    )
