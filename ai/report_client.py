"""GMS 관찰 리포트 생성 클라이언트 — 활동 집계·감정·대표 발화 → 보호자용 관찰 초안.

BE 계약(report.dto.ObservationGenerationRequest → ObservationGenerationResult)에 맞춰
최종 분석 요청을 받아 관찰 리포트 결과를 만든다. 실제 소비자는 BE AiObservationClient이며,
지금은 MockAiObservationClient가 고정 fixture를 쓴다 — HTTP 배선은 후속 이슈.

역할 분담:
- LLM(GMS)이 생성하는 것: 정성적 관찰 문구(요약·긍정신호·주의점·근거·안내·후속질문·특징·대화요약·안내·질문).
- 서버가 고정으로 채우는 것: disclaimer·limitations(안전 문구는 LLM에 맡기지 않는다)·
  model 정보·request_id 에코·emotion_source(요청에서 결정)·representative_utterance 에코.
- 코드가 판정하는 것: status. 조립은 언제나 AI_DRAFT 로 두고, 2차 패스(_self_review)를 통과한
  리포트만 AI_REVIEWED 로 올린다.

AI 자체검토(2026-08-05): 이 서비스에는 리포트를 읽는 사람 전문가가 없다 — 실측으로 확인했다
(ObservationReviewStatus 값이 AI_DRAFT 하나뿐 · 다른 상태로 가는 전이 코드 0건 ·
report 패키지에 EXPERT 읽기 경로 0건 · 운영 report_observed_features 97건 전량 EXPERT_ONLY).
그 자리를 AI 스스로가 대신한다: 생성 → 규칙 필터(report_safety) → LLM 자체검토 → 통과분만
AI_REVIEWED. 사람이 필요한 자리(위기 대응·상담 권유)는 그대로 사람에게 남긴다 —
crisis_detection·crisis_guidance 와 expertReviewRequired 가 그 경로다.

가드레일:
- 진단·점수화 금지는 프롬프트가 강제하고, 안전 문구(disclaimer/limitations)는 코드가 상수로 보장한다.
- 대표 발화·표현 감정 등 아이 표현은 로그로 남기지 않는다(실패 로그에 에러 유형만).
- RAG 근거(S15P11B209-614): 배포된 인덱스에서 관찰 어휘·일반 지식을 검색해 프롬프트 보조
  근거로 싣고, 출처(ragReferences)와 KB Version을 응답에 기록한다. 검색 실패는 차단이
  아니라 기능 저하 — RAG 없이 생성한다(정책: docs/ai/rag-corpus-policy.md).
  ⚠️ RAG는 HTP 리포트에서만 검색한다. 그림일기 프롬프트는 [전문 자료 근거]를 근거 목록에
  두지 않으므로 검색해도 쓰이지 않는다 — RAG_NOT_APPLICABLE로 표시하고 건너뛴다.

프롬프트 구성: 활동별 자기완결 파일 하나(report_htp | report_diary)를 그대로 쓴다
(2026-08-07 공용 report_common 폐기 — 각 파일이 작성 규칙·JSON 스키마까지 소유).
활동 판별은 subject_summaries[].drawing_subject 유무로 추론한다(계약에 activityType 없음).

형식 지표(S15P11B209-836): 그리기 소요시간·멈춤·지우기 등은 요청의 behaviorMetrics 로 들어온다.
계약 확장 전에는 전달 수단이 없어 [형식적 분석] 블록이 운영 경로에서 한 번도 실리지 않았다 —
프롬프트는 그 블록을 전제로 쓰여 있는데 데이터가 도착하지 않던 상태였다.
"""

from __future__ import annotations

import json
import logging

from openai import OpenAIError
from prometheus_client import Counter as PrometheusCounter

import config
import diary_report_v2
import internal_contracts as contracts
import interpretation_gate  # 경향 카드 구조 게이트 (S15P11B209-888)
import prompts_registry  # 프롬프트 파일 로딩·버전 관리 중앙화 (S15P11B209-595)
import report_safety
from gms import get_client
from rag import Chunk, RagUnavailableError, retrieve
from rag import knowledge_base_version as rag_knowledge_base_version

logger = logging.getLogger(__name__)

# ── 활동 유형별 리포트 프롬프트 ─────────────────────────────────
# 하나의 report.txt로 두 활동을 처리하던 것을 갈랐다. 근거 블록 구성이 다르기 때문이다:
#   - HTP: 주제별 [집 그림 관찰]·[집 그림 문답] … + [전문 자료 근거](RAG)
#   - 그림일기: 단일 [그림 관찰](740) 또는 [그림 관찰 서술](레거시 draft 인자). RAG 없음.
# 구 report.txt는 근거 화이트리스트가 "[그림 관찰 서술]·[형식적 분석]·[활동 데이터]만"이라
# 실제로 주입되는 주제별 블록·RAG 블록이 목록에서 빠져 있었다 — 뒤쪽 상세 설명과 정면 모순이라
# 모델이 화이트리스트를 곧이곧대로 읽으면 RAG 근거와 그림 내용을 통째로 버린다.
# 작성 규칙·JSON 스키마도 활동별 파일이 각자 소유한다(2026-08-07 사용자 결정, S15P11B209-993) —
# 공용 report_common은 폐기했다. 한 활동에 맞춘 수정이 다른 활동에 실리는 경로를 구조에서
# 제거하고, "주제가 나뉘지 않으면 null" 같은 조건문 없이 각 파일이 자기 활동만 말하게 한다.
# ⚠️ 두 파일의 레거시 JSON 키는 같은 BE 계약을 향한다. 그림일기만 하위호환 가능한
#    optional diarySignals를 추가하며, 테스트가 그 한 가지 확장만 허용한다.
_REPORT_HTP = "report_htp"
_REPORT_DIARY = "report_diary"
# AI 자체검토(2-pass) 프롬프트. 생성 프롬프트와 함께 '한 번의 리포트 생성'을 이루므로
# 버전 조합에도 함께 들어간다 — 검토 기준이 바뀌면 결과가 바뀌는데 태그가 그대로면 재현이 깨진다.
_REPORT_REVIEW = "report_review"
# 그림일기 V2는 반복·일반론·유도 답 과장까지 추가로 검토한다. HTP 담당 프롬프트와
# 검토 의미를 바꾸지 않기 위해 별도 자산으로 분리한다.
_REPORT_REVIEW_DIARY = "report_review_diary"

# 활동 변형별 조합 — 라벨은 저장 태그에 그대로 실리는 고정 어휘다(S15P11B209-819).
_COMBOS: dict[str, tuple[str, ...]] = {
    "htp": (_REPORT_HTP, _REPORT_REVIEW),
    "diary": (_REPORT_DIARY, _REPORT_REVIEW_DIARY),
}

# 두 변형을 함께 담은 통합 버전 — 어떤 파일 조합으로 생성됐는지 한 문자열로 남긴다.
PROMPT_VERSION = prompts_registry.short_version(
    "report-all", _REPORT_HTP, _REPORT_DIARY, _REPORT_REVIEW, _REPORT_REVIEW_DIARY
)


def version_manifest() -> dict[str, str]:
    """축약 태그 → 정본 조합 버전. 저장된 다이제스트를 되짚는 수단이다(S15P11B209-819).

    저장 값은 포인터라, 이 매핑이 로그·버전 엔드포인트로 노출돼야 재현성이 유지된다.
    """
    return {
        prompts_registry.short_version(label, *names): prompts_registry.composite_version(
            *names
        )
        for label, names in _COMBOS.items()
    }

# 그림일기에는 RAG 근거를 싣지 않는다(결정: HTP 전용). 코퍼스는 활동유형 중립이지만,
# 전문 자료 인용이 필요한 쪽은 '검사처럼 읽히기 쉬운' HTP 리포트다 — 거기서만 관찰 어휘를
# 보조받고, 가벼운 그림일기 리포트는 활동 데이터만으로 담백하게 쓴다.
RAG_NOT_APPLICABLE = "RAG_NOT_APPLICABLE"

# 안전 문구는 LLM이 빠뜨리거나 바꾸면 안 되는 필수 고지 — 서버가 상수로 보장한다.
# (BE MockAiObservationClient와 동일 문구를 써서 두 구현의 고지가 일관되게.)
DISCLAIMER = (
    "본 결과는 아동 발달 진단이 아니라 그림 활동 관찰 기록입니다. "
    "우려되는 점이 있으면 전문가와 상담하세요."
)
LIMITATIONS = (
    "본 리포트는 제한된 활동 데이터를 바탕으로 한 관찰 기록이며, "
    "아동의 발달 상태를 단정하지 않습니다."
)
# 후속 질문이 비었거나 진단성 표현이 섞였을 때 대체할 안전 기본값(S15P11B209-601).
# 보호자가 아이에게 그대로 건네도 무해한, 진단이 아닌 '집에서 나눌 대화'용 질문.
DEFAULT_FOLLOW_UP_QUESTION = "오늘 그림에서 어떤 부분이 제일 마음에 들었어?"

# ── 검토 상태 (2026-08-05) ───────────────────────────────────────
# 이 서비스에는 리포트를 읽는 사람 전문가가 없다(4계층 실측: ObservationReviewStatus 값이
# AI_DRAFT 하나뿐 · 전이 코드 0건 · EXPERT 읽기 경로 0건 · 운영 관찰 특징 97건 전량 EXPERT_ONLY).
# 그 자리를 AI 자체검토가 대신한다 — 통과분만 AI_REVIEWED 로 올려 보호자 경로를 연다.
#
# ⚠️ BE 계약 의존: BE ObservationReviewStatus enum 에 AI_REVIEWED 가 추가되고,
#    AnalysisObservationResult 가 하드코딩(AI_DRAFT) 대신 이 값을 받아야 실효가 생긴다.
#    그 전까지 AI_REVIEWED 를 보내도 BE는 AI_DRAFT 로 저장하므로 **동작은 지금과 같다**
#    (모든 관찰 카드가 EXPERT_ONLY 로 강등된 채 저장된다) — 배포 순서에 안전하다.
REVIEW_STATUS_DRAFT = "AI_DRAFT"
REVIEW_STATUS_REVIEWED = "AI_REVIEWED"

_VALID_SCOPES = {"EXPERT_ONLY", "REVIEWED_GUARDIAN"}


def _load(name: str) -> str:
    """프롬프트 로딩은 prompts_registry로 중앙화했다(S15P11B209-595)."""
    return prompts_registry.load(name)


def _is_htp(req: contracts.ObservationGenerationRequest) -> bool:
    """이 요청이 HTP 활동인지 판별한다.

    계약(ObservationGenerationRequest)에 activityType 필드가 없어 subject_summaries로 추론한다 —
    HTP는 drawingSubject가 반드시 채워지고(AnalysisRequest·QuestionRequest와 같은 검증 규칙),
    그림일기는 None, 구 BE(subject_summaries 미전달)는 빈 목록이다. 뒤의 둘은 모두
    '단일 그림 + RAG 없음' 경로라 그림일기 프롬프트가 그대로 맞는다.
    """
    return any(s.drawing_subject is not None for s in req.subject_summaries)


def _prompt_names(is_htp: bool) -> tuple[str, ...]:
    """이번 생성이 쓰는 프롬프트 이름(자기완결 활동 파일 하나)."""
    return ((_REPORT_HTP if is_htp else _REPORT_DIARY),)


def _review_prompt_name(is_htp: bool) -> str:
    """활동별 자체검토 프롬프트. 그림일기 품질 규칙을 HTP에 흘리지 않는다."""
    return _REPORT_REVIEW if is_htp else _REPORT_REVIEW_DIARY


def _system_prompt(is_htp: bool) -> str:
    """리포트 지침 system 프롬프트 — 활동별 자기완결 파일 하나를 그대로 쓴다(993 공용 제거).

    파일 안 순서는 이전 조립 순서를 그대로 물려받았다: 역할·근거 화이트리스트·블록
    사용법이 앞, 사실/해석 분리·작성 규칙·출력 JSON 스키마가 뒤 — 출력 형식을 맨 끝에
    두어야 모델이 형식을 놓치지 않는다.

    ⚠️ 공용 guardrails.txt(대화용)는 append 하지 않는다 — 그 파일은 "정서를 진단·해석하지 마"를
    전제로 한 대화 응답용이라, 리포트의 '요소별 감정 해석' 지침과 충돌한다. 리포트의 안전 기준
    (장애명·진단명·점수·낙인 금지, 과도한 부정 금지, 걱정 신호는 attentionPoints로만)은
    각 활동 파일이 자체적으로 담는다.
    """
    (variant,) = _prompt_names(is_htp)
    return _load(variant)


def _emotion_source(req: contracts.ObservationGenerationRequest) -> str:
    """표현 감정의 출처를 요청 값으로 결정한다(LLM이 아니라 규칙 기반).

    선택 감정 카드가 있으면 SELECTED, 말로 표현했으면 STATED, 둘 다 없으면 INFERRED.
    """
    if req.selected_emotions:
        return "SELECTED"
    if req.expressed_emotion_text and req.expressed_emotion_text.strip():
        return "STATED"
    return "INFERRED"


def _fmt_minutes(ms: int | None) -> str | None:
    """밀리초를 '약 N분' 문구로. None이면 None.

    분 단위로 반올림한다 — 0.1분(6초) 자리까지 적으면 집계가 갖지 않은 정밀도를
    관찰 사실처럼 보이게 한다(구 구현의 "약 10.0분"). 1분 미만은 반올림하면 "약 0분"이 되어
    아예 안 그린 것처럼 읽히므로 따로 적는다.
    """
    if ms is None:
        return None
    if ms < 60_000:
        return "1분 미만"
    return f"약 {round(ms / 60000)}분"


# 블록 머리에 붙는 '이 수치가 무엇의 값인가' 단서 (S15P11B209-838).
#   HTP는 BE가 집·나무·사람 세 단계를 합산해 보낸다 — 한 장 기준으로 읽히면 안 된다.
#   truncated는 배치 상한에 걸려 세션 앞부분만 집계한 값이라 활동 전체로 읽히면 안 된다.
_SCOPE_NOTE_HTP = "집·나무·사람 세 장을 합친 활동 전체 기준"
_SCOPE_NOTE_TRUNCATED = "저장된 캔버스 입력 구간까지만 집계 — 활동 전체가 아닐 수 있어요"


def _format_behavior(
    behavior: contracts.BehaviorMetrics | None, *, is_htp: bool = False
) -> str:
    """형식적 분석 지표를 프롬프트 [형식적 분석] 블록으로. 없으면 빈 문자열.

    None인 항목은 줄 자체를 넣지 않는다 — 0("0번")과 구분하기 위해서다. 집계하지 못한 값을
    0으로 적으면 "멈춤 없이 그렸다"는 관찰 사실로 읽힌다(BE StrokeBehaviorSummary 와 같은 원칙).

    도구·색 변경(2026-08-05): 계약으로 받고도 싣지 않던 두 값을 싣는다. 앱이 도구·색 변경을
    보내기 시작해 BE 집계에 실제 값이 담기게 됐고, 받아 놓고 버리면 프롬프트 1행이 약속한
    지표 목록과 실제 블록이 계속 어긋난다. 대신 해석 남용은 프롬프트가 세 조항으로 막는다 —
    관찰 사실로만 적기 · [형식적 분석] 전체를 신호 하나로 세기 · 0이 몰린 것을 해석하지 않기
    (report_common 2.1.0). 이 블록만으로 "독립 신호 2개" 조건이 채워지지 않게 하는 것이 핵심이다.

    획 수·색 가짓수·주제별 시간(S15P11B209-975): 캔버스 과정 데이터가 이미 쌓여 있는데
    리포트에 닿지 않던 지표를 싣는다. 지표가 늘면 해석 재료도 늘어 위험이 함께 커지므로,
    새 지표의 금지 규칙은 report_common 2.3.0 에 카테고리 서술로 적었다 — 여기(코드 문자열)에
    지시문을 적으면 prompts_registry 버전 추적 밖이라 "크게 고쳤는데 promptVersion 그대로"가
    재발한다(323 교훈). 이 함수가 만드는 것은 **데이터 줄뿐이다.**
    ⚠️ stroke_count 는 지우개 획을 포함한 전체 획 수라 erase_count 와 세는 대상이 겹친다.
       그래서 여기서 비율을 계산해 적지 않는다 — 두 실측값을 그대로 놓고, 표현은 모델이
       프롬프트 규칙 안에서 한다(파생 필드를 계약에 싣지 않는 것과 같은 원칙).

    필압은 강약 값(average_pressure)이 있을 때만 적는다. pressure_available 은 기기가 필압을
    측정할 수 있는지일 뿐 아이에 대한 관찰이 아니라서, "측정됨"·"측정 불가(미지원 기기)"를
    적으면 관찰 내용이 0인 줄이 해석 재료처럼 놓인다. BE도 이 필드를 감정 근거로 쓰지 말라고
    명시했다.
    ⚠️ average_pressure 는 **구조적으로 항상 None** 이다 — BE record StrokeBehaviorSummary 에
       그 필드 자체가 없다(drawingDurationMs·activeDrawingMs·pauseCount·undoCount·eraseCount·
       toolChangeCount·colorChangeCount·pressureAvailable·truncated 뿐). 즉 필압 줄은 운영에서
       한 번도 나온 적이 없고 나올 수도 없다. 아래 분기는 스모크/계약 확장 대비로만 남긴다.
       프롬프트가 필압을 약속하던 문구와 "측정 불가면 언급하지 않는다"는 죽은 규칙은 지웠다.
    """
    if behavior is None:
        return ""

    notes = []
    if is_htp:
        notes.append(_SCOPE_NOTE_HTP)
    if behavior.truncated:
        notes.append(_SCOPE_NOTE_TRUNCATED)
    header = "[형식적 분석]" + (f" ({' / '.join(notes)})" if notes else "")

    lines = [header]
    total = _fmt_minutes(behavior.drawing_duration_ms)
    active = _fmt_minutes(behavior.active_drawing_ms)
    if total:
        lines.append(f"- 총 소요시간: {total}")
    if active:
        lines.append(f"- 실제 그린 시간: {active}")
    subjects = _format_subject_durations(behavior.subject_durations)
    if subjects:
        lines.append(subjects)
    if behavior.stroke_count is not None:
        lines.append(f"- 전체 획 수: {behavior.stroke_count}획 (지우개로 그은 획 포함)")
    if behavior.pause_count is not None:
        # 배치 경계로 세는 추정값이라 상한도 하한도 아니다(BE javadoc) — 단정 표기를 피한다.
        # 0에 "약"을 붙이면 문장이 이상해지므로 그때만 숫자를 그대로 쓴다.
        count = (
            "0번" if behavior.pause_count == 0 else f"약 {behavior.pause_count}번"
        )
        lines.append(f"- 멈춤 횟수: {count} (추정값)")
    if behavior.erase_count is not None:
        lines.append(f"- 지우기 횟수: {behavior.erase_count}회")
    if behavior.undo_count is not None:
        lines.append(f"- 되돌리기 횟수: {behavior.undo_count}회")
    if behavior.tool_change_count is not None:
        lines.append(f"- 도구 바꾼 횟수: {behavior.tool_change_count}회")
    if behavior.color_change_count is not None:
        lines.append(f"- 색 바꾼 횟수: {behavior.color_change_count}회")
    if behavior.colors_used_count is not None:
        lines.append(f"- 사용한 색: {behavior.colors_used_count}가지")
    if behavior.average_pressure is not None:
        lines.append(f"- 필압: 평균 {behavior.average_pressure:.2f} (0~1)")

    # 머리말만 남았다면 적을 관찰이 없다는 뜻 — 빈 블록을 실으면 모델이 채우려 든다.
    if len(lines) == 1:
        return ""
    return "\n".join(lines) + "\n\n"


# 주제 코드 → 한국어 라벨. question_service._SUBJECT_KO와 같은 어휘 — 어긋나면 질문과
# 리포트가 같은 그림을 다른 이름으로 부른다.
_SUBJECT_KO = {"HOUSE": "집", "TREE": "나무", "PERSON": "사람"}


def _subject_label(subject: str | None) -> str:
    """주제 라벨. HTP는 '집 그림'·'나무 그림'·'사람 그림', 그림일기(None)는 '그림'."""
    name = _SUBJECT_KO.get(subject or "")
    return f"{name} 그림" if name else "그림"


def _format_subject_durations(
    durations: list[contracts.SubjectDuration],
) -> str | None:
    """주제별 그리기 시간 한 줄 (S15P11B209-975). 비교가 성립하지 않으면 None.

    ⚠️ **전부 아니면 전무다.** 이 줄의 쓸모는 "어느 그림에 시간을 더 썼는가"라는 비교인데,
       비교는 실린 주제가 전부일 때만 참이다. 세 장 중 두 장만 실린 줄을 보고 모델이
       "집을 가장 오래 그렸어요"라고 적으면 그건 관찰이 아니라 없는 사실이다. 그래서 한
       항목이라도 라벨을 모르거나 시간이 없으면 **남은 것만 적지 않고 줄 전체를 뺀다.**
       BE도 같은 이유로 세 단계를 다 집계했을 때만 이 목록을 보낸다(837 전부-아니면-전무).

    시간은 drawing_duration_ms(그 주제에 머문 전체 시간)만 쓴다. 없을 때 active_drawing_ms 로
    대체하지 않는다 — 한 줄 안에서 두 가지 다른 측정이 섞이면 그 비교는 이미 거짓이다.

    그림일기는 목록이 비어 있어 None 이 된다(주제 구분 자체가 없다).
    """
    if not durations:
        return None

    parts = []
    for duration in durations:
        name = _SUBJECT_KO.get(duration.drawing_subject or "")
        minutes = _fmt_minutes(duration.drawing_duration_ms)
        if not name or not minutes:
            return None
        parts.append(f"{name} {minutes}")
    return "- 주제별 그리기 시간: " + " · ".join(parts)


# ── 탐지 기하 → 관찰 사실 (S15P11B209-839) ─────────────────────
# HTP 임상 리포트의 형식적 분석 1단계가 크기·위치다. 정규화 bbox 에서 바로 계산된다
# (같은 접근: 이은정·황세진, 미술치료연구 2023 — 객체검출 위치·크기로 형식적 해석 산출).
# ⚠️ 여기서 만드는 것은 '관찰 사실'뿐이다. 크기가 작다/크다에 의미를 붙이는 일은 하지 않는다.
_POSITION_COLS = ("왼쪽", "가운데", "오른쪽")
_POSITION_ROWS = ("위쪽", "가운데", "아래쪽")


def _third(value: float) -> int:
    """0~1 좌표를 3분할 인덱스로. 화면을 9칸으로 나눠 위치를 말하기 위한 것."""
    if value < 1 / 3:
        return 0
    if value < 2 / 3:
        return 1
    return 2


def _has_box(obj: contracts.SubjectDetectedObject) -> bool:
    """위치를 말할 수 있는 탐지인가 — bbox 네 값이 **전부** 있어야 한다.

    2026-08-05 운영 결함 이후 기하 4필드가 optional 이 됐다(BE 906이 {evidenceSourceId,
    objectCode} 만 보내 422가 났다). 일부만 있는 경우도 위치를 말할 수 없다 —
    빠진 값을 0으로 치거나 있는 값만으로 추정하면 **없는 근거가 근거 자리에 들어간다**
    (area_ratio 를 width*height 로 대체 계산하지 말라는 BE 명시와 같은 원칙).
    """
    return None not in (obj.x, obj.y, obj.width, obj.height)


def _position_label(obj: contracts.SubjectDetectedObject) -> str:
    """bbox 중심점의 9분할 위치를 한국어로. 중앙이면 '한가운데'.

    ⚠️ 호출 전에 _has_box 로 걸러야 한다 — 좌표가 없으면 위치를 지어낼 방법이 없다.
    """
    col = _POSITION_COLS[_third(obj.x + obj.width / 2)]
    row = _POSITION_ROWS[_third(obj.y + obj.height / 2)]
    if col == "가운데" and row == "가운데":
        return "화면 한가운데"
    # 한 축만 가운데면 그 축은 말하지 않는다("화면 아래쪽 가운데"보다 "화면 아래쪽"이 자연스럽다).
    return "화면 " + " ".join(part for part in (row, col) if part != "가운데")


def _percent(ratio: float) -> str:
    """비율(0~1)을 '약 N%'로. 반올림이 0%가 되면 '1% 미만'으로 적는다."""
    percent = round(ratio * 100)
    return "1% 미만" if percent < 1 else f"약 {percent}%"


def _whole_object(
    summary: contracts.SubjectSummary,
) -> contracts.SubjectDetectedObject | None:
    """주제 전체를 감싸는 탐지(집 그림의 HOUSE 등). 그림일기(drawing_subject=None)는 없다."""
    if summary.drawing_subject is None:
        return None
    return next(
        (o for o in summary.detected_objects if o.object_code == summary.drawing_subject),
        None,
    )


def _geometry_facts(
    obj: contracts.SubjectDetectedObject,
    whole: contracts.SubjectDetectedObject | None,
    subject_name: str,
) -> list[str]:
    """이 탐지에 대해 **실제로 주어진** 관찰 사실만 모은다. 없으면 빈 목록.

    ⚠️ 값이 없으면 만들지 않는다. 좌표가 없으면 위치를 적지 않고, area_ratio 가 없으면
       크기를 적지 않는다(width*height 로 대체 계산 금지 — BE 명시).
       빈 목록이면 호출부가 그 항목을 블록에서 통째로 뺀다.
    """
    facts: list[str] = []
    if obj.area_ratio is not None:
        facts.append(f"종이의 {_percent(obj.area_ratio)}")
        # 부위:주제 비율 — '집에 비해 문이 작다' 같은 관계를 수치로 남긴다.
        if whole is not None and whole is not obj and whole.area_ratio:
            facts.append(f"{subject_name} 전체의 {_percent(obj.area_ratio / whole.area_ratio)}")
    if _has_box(obj):
        facts.append(_position_label(obj))
    return facts


def _geometry_line(
    obj: contracts.SubjectDetectedObject,
    whole: contracts.SubjectDetectedObject | None,
    subject_name: str,
) -> str | None:
    """탐지 하나 → 크기·위치 한 줄. 적을 관찰 사실이 없으면 None(그 항목을 빼라는 뜻).

    신뢰도가 확정 구간 미만이면 완화 문구를 앞에 붙인다 — 겨우 통과한 탐지가 확정 사실로
    적혀 보호자에게 나가면 안 된다(BE 요청). confidence 가 아예 없으면 판단할 근거가 없으므로
    완화하지도 제외하지도 않는다(구 detectedObjectCodes 경로와 같은 취급).
    """
    facts = _geometry_facts(obj, whole, subject_name)
    if not facts:
        return None

    hedge = ""
    if (
        obj.confidence is not None
        and obj.confidence < config.REPORT_GEOMETRY_CERTAIN_CONF
    ):
        hedge = "(희미해 확실하지 않아요) "
    return f"- {obj.object_code}: {hedge}{', '.join(facts)}"


def _format_geometry(summary: contracts.SubjectSummary, label: str) -> str:
    """주제 하나의 [OO 크기·위치] 블록. 쓸 탐지가 없으면 빈 문자열.

    두 가지를 뺀다:
    - 신뢰도가 REPORT_GEOMETRY_MIN_CONF 미만인 탐지 — 탐지 임계값(0.20)은 '박스를 남길지'의
      기준이라 리포트 문장의 근거 기준으로 쓰기엔 낮다.
    - **기하가 없는 탐지**(2026-08-05) — BE가 {evidenceSourceId, objectCode} 만 보내는 경우다.
      코드 이름만으로 크기·위치 블록에 줄을 세우면 '관찰된 수치'가 있는 것처럼 읽힌다.
      그 항목은 '탐지된 요소 코드' 줄로만 남고, 이 블록에는 오르지 않는다.

    전부 빠지면 블록 자체를 싣지 않는다 — _format_behavior 가 적을 지표가 없을 때
    빈 문자열을 돌려주는 것과 같은 원칙이다(빈 블록을 실으면 모델이 채우려 든다).
    """
    whole = _whole_object(summary)
    subject_name = _SUBJECT_KO.get(summary.drawing_subject or "", "그림")
    lines = [
        line
        for obj in summary.detected_objects
        if obj.confidence is None or obj.confidence >= config.REPORT_GEOMETRY_MIN_CONF
        if (line := _geometry_line(obj, whole, subject_name)) is not None
    ]
    if not lines:
        return ""
    return "\n".join([f"[{label} 크기·위치]", *lines])


def _format_subject_blocks(req: contracts.ObservationGenerationRequest) -> str:
    """주제별 [OO 관찰]·[OO 문답] 블록 (S15P11B209-740).

    HTP는 집·나무·사람 각 그림의 VLM 서술과 그 그림에서 나눈 문답이 블록으로 실린다.
    문답의 아이 답변은 '관찰된 사실' 근거로만 쓰이도록 활동별 프롬프트가 강제한다.
    탐지 요소 코드는 서술 검증 참고용 — 리포트 문장에 코드 원문 노출 금지(프롬프트 규칙).

    기하 정보(839)가 있으면 [OO 크기·위치] 블록이 뒤따른다. 없으면(구 BE·PIXEL 좌표뿐인
    주제) 지금까지처럼 코드 목록만 실린다.
    """
    parts: list[str] = []
    for summary in req.subject_summaries:
        label = _subject_label(summary.drawing_subject)
        description = (summary.drawing_description or "").strip() or (
            "(관찰 서술이 제공되지 않았어요)"
        )
        lines = [f"[{label} 관찰]", description]
        # 근거 식별자(886) — 이 서술을 근거로 쓸 때 옮겨 적을 값. 없으면 근거로 쓸 수 없다.
        if summary.observation_evidence_source_id:
            lines.append(
                f"- 근거 식별자: VLM_OBSERVATION:{summary.observation_evidence_source_id}"
            )
        if summary.detected_object_codes:
            lines.append(
                "- 탐지된 요소 코드(참고용): " + ", ".join(summary.detected_object_codes)
            )
        detected_refs = [
            f"{obj.object_code}={obj.evidence_source_id}"
            for obj in summary.detected_objects
            if obj.evidence_source_id
        ]
        if detected_refs:
            lines.append("- 요소별 근거 식별자(DETECTED_OBJECT): " + ", ".join(detected_refs))
        parts.append("\n".join(lines))
        geometry = _format_geometry(summary, label)
        if geometry:
            parts.append(geometry)
        if summary.qa_pairs:
            qa_lines = [f"[{label} 문답]"]
            for qa in summary.qa_pairs:
                # SKIPPED는 '아이가 스스로 넘겼다'는 관찰 사실이라 무응답과 구분해 표기한다.
                if (qa.answer_type or "").upper() == "SKIPPED":
                    answer = "(건너뛴 질문)"
                else:
                    answer = (qa.answer_text or "").strip() or "(답하지 않았어요)"
                    # 칩 답변은 아이가 보기에서 고른 것이다(994) — 모델이 "~라고 말했어요"로
                    # 옮기지 않도록 재료 단계에서 표시한다. 프롬프트 규칙과 한 쌍.
                    if (qa.answer_type or "").upper() == "OPTION":
                        answer += " (선택지에서 고른 답이에요)"
                line = f"- 질문: {qa.question}\n  답변: {answer}"
                # 근거 식별자(886) — 이 답변을 경향 카드 근거로 쓸 때 그대로 옮겨 적을 값이다.
                # 미확정 STT는 식별자를 싣지 않는다: 표시는 유지하되 근거로는 쓸 수 없게 만든다
                # (875 §6-1). "쓰지 마"라고 문장으로 부탁하는 것보다 재료를 주지 않는 편이 확실하다.
                if qa.answer_message_id is not None and not qa.stt_needs_confirmation:
                    line += f"\n  근거 식별자: QA_ANSWER:{qa.answer_message_id}"
                elif qa.stt_needs_confirmation:
                    line += "\n  (음성 인식 확인이 필요한 답변이라 근거로 쓸 수 없어요)"
                qa_lines.append(line)
            parts.append("\n".join(qa_lines))
    return "\n\n".join(parts) + "\n\n"


def _format_activity(
    req: contracts.ObservationGenerationRequest,
    drawing_description: str | None,
    behavior: contracts.BehaviorMetrics | None = None,
    rag_chunks: list[Chunk] | None = None,
) -> str:
    """[그림 관찰 서술](VLM) + [형식적 분석] + [전문 자료 근거] + 집계·감정·대표 발화.

    drawing_description 은 vlm_client.describe 산출물(그림 사실 묘사)이며, 있으면
    관찰 특징·요약의 근거가 된다. 없으면 그림 특징은 언급하지 않도록 안내 문구를 넣는다.
    behavior 는 소요시간·필압 등 형식적 지표이며, 있으면 관찰 보조 근거로 반영된다.
    rag_chunks(614)는 검색된 전문 자료 근거 — 있으면 어휘·일반 지식 보조로 실린다.

    subject_summaries(740)가 있으면 단일 [그림 관찰 서술] 대신 주제별 블록을 쓴다 —
    drawing_description(레거시 draft 경로 인자)과 동시에 오면 주제별 블록이 우선한다.
    """
    # 선택 감정은 코드 목록으로 실리는데, 근거로 쓰려면 어느 레코드에서 왔는지 알아야 한다(886).
    # 식별자가 함께 온 감정만 "코드(식별자)"로 적는다 — 없는 감정은 근거가 되지 못한다.
    emotion_ref_by_code = {
        ref.emotion_code: ref.evidence_source_id for ref in req.selected_emotion_refs
    }
    emotions = (
        ", ".join(
            f"{code}(EMOTION_SELECTION:{emotion_ref_by_code[code]})"
            if code in emotion_ref_by_code
            else code
            for code in req.selected_emotions
        )
        if req.selected_emotions
        else "없음"
    )
    metric_ref_line = (
        f"- 활동 기록 근거 식별자: ACTIVITY_METRIC:{req.activity_metric_source_id}\n"
        if req.activity_metric_source_id
        else ""
    )
    if req.subject_summaries:
        observation_block = _format_subject_blocks(req)
    else:
        description = (drawing_description or "").strip() or (
            "(그림 관찰 서술이 제공되지 않았어요)"
        )
        observation_block = f"[그림 관찰 서술]\n{description}\n\n"
    return (
        f"{observation_block}"
        f"{_format_behavior(behavior, is_htp=_is_htp(req))}"
        f"{_format_rag_block(rag_chunks or [])}"
        "[활동 데이터]\n"
        # 나이가 없으면 줄 자체를 뺀다 — "없음"으로 적으면 모델이 나이를 짐작해 채우는
        # 압력이 된다(1001). 프롬프트도 나이 없을 때 연령 언급을 금지한다.
        + (f"- 아이 나이: 만 {req.child_age}세\n" if req.child_age is not None else "")
        + f"- 질문 난이도: {req.question_difficulty or '정보 없음'}\n"
        f"- 제시한 질문 수: {req.question_count}\n"
        f"- 응답한 답변 수: {req.answered_count}\n"
        f"- 건너뛴 질문 수: {req.skipped_count}\n"
        f"- 음성 인식 실패 수: {req.unrecognized_speech_count}\n"
        f"- 아이가 선택한 감정: {emotions}\n"
        f"- 아이가 말한 감정: {req.expressed_emotion_text or '없음'}\n"
        f"- 대표 발화: {req.representative_utterance or '없음'}\n"
        f"{metric_ref_line}\n"
        "이 데이터로 규칙에 맞는 관찰 기록 JSON을 만들어줘."
    )


# ── RAG 근거 검색 (S15P11B209-614 — 정책: docs/ai/rag-corpus-policy.md) ──────
def _build_rag_query(
    req: contracts.ObservationGenerationRequest, drawing_description: str | None
) -> str:
    """검색 질의 텍스트 — 관찰 서술·탐지 객체·선택 감정로만 만든다.

    ⚠️ 질의의 본문은 VLM 관찰 서술 원문이다 — 서술 프롬프트(ai/prompts/drawing_description_*.txt)를
    고치면 이 질의가 바뀌고, 따라서 검색되는 청크와 RAG_SCORE_THRESHOLD 통과 여부도 바뀐다.
    서술이 색·크기·위치 같은 구체적 관찰 어휘를 담을수록 코퍼스(관찰 어휘·발달 일반 지식)와
    가까워진다. 서술을 한 문장으로 줄이는 변경은 질의를 죽여 RAG_LOW_SCORE를 상시화한다.

    ⚠️ 아이 발화(qaPairs.answerText·대표 발화·표현 감정 문구)는 넣지 않는다(정책 §1-1) —
    질의는 GMS로 나가는 표면이라 아동 개인 표현의 유출면을 늘리지 않는다.
    선택 감정은 고정 코드(HAPPY 등)라 개인 표현이 아니다.
    """
    parts: list[str] = []
    if req.subject_summaries:
        for summary in req.subject_summaries:
            if summary.drawing_description:
                parts.append(summary.drawing_description)
            parts.extend(summary.detected_object_codes)
    elif drawing_description:
        parts.append(drawing_description)
    # 관찰 재료(그림 서술·탐지 객체)가 없으면 질의를 만들지 않는다 — 감정 코드·난이도만으로
    # 검색하면 그림과 무관한 근거가 붙는다. 둘은 관찰 재료가 있을 때의 보강 신호로만 쓴다.
    if not parts:
        return ""
    if req.selected_emotions:
        parts.append("아이가 선택한 감정: " + ", ".join(req.selected_emotions))
    if req.question_difficulty:
        parts.append(f"연령 난이도: {req.question_difficulty}")
    return "\n".join(parts).strip()


# RAG 검색 결과 카운터 (S15P11B209-615). outcome: used | no_index | unavailable |
#   low_score | no_query | not_applicable. "성공/실패/저점수 비율"을 운영에서 볼 수 있게 한다 —
#   저점수 비율이 높으면 코퍼스가 얇거나 임계값(RAG_SCORE_THRESHOLD)이 높은 것.
#   not_applicable은 그림일기라 검색을 아예 시도하지 않은 경우 — 장애가 아니라 정책이다.
_RAG_SEARCH_COUNTER = PrometheusCounter(
    "dodam_rag_search_total",
    "관찰 리포트 RAG 검색 결과 (outcome별 누적)",
    labelnames=("outcome",),
)


def _search_rag(
    req: contracts.ObservationGenerationRequest, drawing_description: str | None
) -> tuple[list[Chunk], str | None]:
    """근거 청크 검색 → (청크 목록, 건너뛴 사유 코드).

    실패는 '차단'이 아니라 '기능 저하'다(548 폴백 정책과 정합) — 어떤 사유든
    리포트 생성은 계속되고, 사유는 응답(ragSkippedReason)과 메트릭에만 남는다.

    - RAG_NO_QUERY: 관찰 재료(서술·객체)가 없어 검색을 시도하지 않음
    - RAG_NO_INDEX: 인덱스 미배포(운영상 정상일 수 있는 상태)
    - RAG_UNAVAILABLE: 임베딩 호출 실패 등 검색 장애
    - RAG_LOW_SCORE: 검색은 됐지만 전부 임계값 미달 — 억지 근거를 싣지 않음
    """
    query = _build_rag_query(req, drawing_description)
    if not query:
        _RAG_SEARCH_COUNTER.labels(outcome="no_query").inc()
        return [], "RAG_NO_QUERY"
    try:
        chunks = retrieve(query)
    except RagUnavailableError as e:
        reason = "RAG_NO_INDEX" if e.reason == "NO_INDEX" else "RAG_UNAVAILABLE"
        _RAG_SEARCH_COUNTER.labels(outcome=reason.removeprefix("RAG_").lower()).inc()
        logger.info("RAG 근거 없이 리포트 생성 — reason=%s", reason)
        return [], reason
    if not chunks:
        _RAG_SEARCH_COUNTER.labels(outcome="low_score").inc()
        logger.info("RAG 근거 없이 리포트 생성 — reason=RAG_LOW_SCORE")
        return [], "RAG_LOW_SCORE"
    _RAG_SEARCH_COUNTER.labels(outcome="used").inc()
    return chunks, None


def _format_rag_block(chunks: list[Chunk]) -> str:
    """[전문 자료 근거] 블록. 근거가 없으면 빈 문자열(블록 자체를 싣지 않는다)."""
    if not chunks:
        return ""
    lines = ["[전문 자료 근거]"]
    for chunk in chunks:
        lines.append(f"- ({chunk.title}) {chunk.text}")
    return "\n".join(lines) + "\n\n"


def _rag_references(chunks: list[Chunk]) -> list[contracts.RagReference]:
    """청크 → 출처 목록(자료 단위 중복 제거, 검색 순위 순서 유지)."""
    seen: set[str] = set()
    references: list[contracts.RagReference] = []
    for chunk in chunks:
        if chunk.source_id in seen:
            continue
        seen.add(chunk.source_id)
        references.append(
            contracts.RagReference(source_id=chunk.source_id, title=chunk.title)
        )
    return references


def _extract_json(raw: str) -> dict:
    """모델 응답에서 JSON 객체만 뽑아 파싱한다(코드펜스·머리말이 섞여도 견디게).

    첫 '{' 부터 마지막 '}' 까지를 JSON으로 본다. 파싱 실패는 RuntimeError로 올린다.
    """
    text = raw.strip()
    start = text.find("{")
    end = text.rfind("}")
    if start == -1 or end == -1 or end < start:
        raise RuntimeError("리포트 응답을 해석하지 못했어요(형식 오류).")
    try:
        return json.loads(text[start : end + 1])
    except json.JSONDecodeError as e:
        # ⚠️ 응답 본문은 로그로 남기지 않는다 — 에러 유형만.
        logger.error("리포트 JSON 파싱 실패: %s", type(e).__name__)
        raise RuntimeError("리포트 응답을 해석하지 못했어요(형식 오류).") from e


def _scope(value) -> str:
    """visibility_scope 를 계약 허용값으로 강제한다. 모르는 값은 보수적으로 EXPERT_ONLY."""
    return value if value in _VALID_SCOPES else "EXPERT_ONLY"


def _feature(item: dict) -> contracts.ObservedFeatureDraft:
    """LLM이 만든 특징 dict 하나를 계약 모델로. 누락 필드는 빈 문자열로 채운다.

    두 가지를 보호자 노출 전에 규칙으로 걸러 EXPERT_ONLY로 강등한다:
    - 단정적 진단(591)·감정/성격 과잉 추론(592) 표현 → 격리.
    - '근거 없는 해석'(S15P11B209-600): description(AI 해석)이 있는데 evidenceSummary(관찰 사실)가
      비어 있으면, 사실에 근거하지 않은 억측이라 보호자에게 사실처럼 보이면 안 된다 → 격리.
    경향성 우려 소견·근거 있는 해석은 그대로 통과한다.
    """
    title = str(item.get("title", ""))
    description = str(item.get("description", ""))
    evidence = str(item.get("evidenceSummary", ""))
    scope = _scope(item.get("visibilityScope"))
    if scope != "EXPERT_ONLY" and report_safety.has_unsafe_expression(
        title, description, evidence
    ):
        # ⚠️ 원문은 로그로 남기지 않는다 — 격리 사실만.
        logger.warning("리포트 feature 과도 규정·단정 표현 격리 — EXPERT_ONLY 강등")
        scope = "EXPERT_ONLY"
    elif scope != "EXPERT_ONLY" and description.strip() and not evidence.strip():
        # 해석은 있는데 관찰 근거가 없다 — 사실/해석 분리 원칙 위반이라 보호자 노출 불가.
        logger.warning("리포트 feature 해석에 관찰 근거 없음 — EXPERT_ONLY 강등")
        scope = "EXPERT_ONLY"
    return contracts.ObservedFeatureDraft(
        feature_code=str(item.get("featureCode", "")),
        title=title,
        description=description,
        evidence_summary=evidence,
        visibility_scope=scope,
    )


# ── 경향 해석 조립 (S15P11B209-887) ──────────────────────────────
# 정본: docs/S15P11B209-875-report-api-contract.md v1.1 · 안전 예외는 보호자 계약 §4-1~§4-4(885).
#
# 여기서 하는 것은 **조립 위생**이다: 계약이 허용한 값인지, 참조가 실제로 존재하는지, 보호자에게
# 나갈 문장에 진단·낙인 표현이 없는지. 값을 고쳐 통과시키지 않고 **못 쓰는 것은 버린다.**
# ⚠️ "독립 근거 2건·아이 표현 1건" 같은 계수 게이트는 S15P11B209-888이 별도 모듈로 붙인다.
#    그때까지 이 조립은 카드 개수를 늘리는 방향으로 관대하지 않다(참조 없는 카드는 버린다).
_EVIDENCE_SOURCE_TYPES = frozenset(
    {
        "VISION",
        "CHILD_ANSWER",
        "SELECTED_EMOTION",
        "STATED_EMOTION",
        "ACTIVITY_METRIC",
        "REPEATED_SUBJECT",
        "LONGITUDINAL",
    }
)
_EVIDENCE_REF_KINDS = frozenset(
    {
        "QA_ANSWER",
        "DETECTED_OBJECT",
        "VLM_OBSERVATION",
        "EMOTION_SELECTION",
        "ACTIVITY_METRIC",
        "PRIOR_ACTIVITY",
    }
)
_INTERPRETATION_CATEGORIES = frozenset(
    {
        "RELATIONSHIP",
        "EMOTION",
        "SELF_EXPRESSION",
        "ACTIVITY_STYLE",
        "ADAPTATION",
    }
)
# LLM이 만들어도 되는 가이드 유형. DAILY_PARENTING(일상 육아 조언)·PROFESSIONAL_SUPPORT(상담 안내)는
#   검토된 문장 세트·고정 템플릿 소유라 여기 없다(875 §7-1 · S15P11B209-892). 오면 버린다 —
#   검토되지 않은 육아 조언·상담 안내가 보호자에게 나가는 것이 이 필드의 유일한 사고 유형이다.
_AI_GENERATED_GUIDE_TYPES = frozenset({"DRAWING_CONVERSATION", "HOME_OBSERVATION"})
# 가능성 어조 표지. 하나도 없으면 단정으로 읽히므로 카드를 내지 않는다(875 §3 "가능성 어조").
_TENTATIVE_MARKERS = ("수 있", "보입니다", "보여요", "경향", "듯", "가능성")


def _allowed_evidence_refs(
    req: contracts.ObservationGenerationRequest,
) -> frozenset[tuple[str, str]]:
    """요청에 실려 온 근거 식별자 집합 (S15P11B209-886).

    **AI가 참조할 수 있는 것은 여기 있는 것뿐이다.** kind 형식만 검사하면 그럴듯한 번호를
    지어내도 통과하므로, 실제로 받은 식별자인지 대조한다 — 이게 "BE 발급 ID만"의 실효 장치다.

    미확정 STT 문답은 애초에 넣지 않는다(875 §6-1) — 표시는 유지하되 근거가 될 수 없다.
    """
    refs: set[tuple[str, str]] = set()
    for summary in req.subject_summaries:
        if summary.observation_evidence_source_id:
            refs.add(("VLM_OBSERVATION", summary.observation_evidence_source_id))
        for obj in summary.detected_objects:
            if obj.evidence_source_id:
                refs.add(("DETECTED_OBJECT", obj.evidence_source_id))
        for qa in summary.qa_pairs:
            if qa.answer_message_id is not None and not qa.stt_needs_confirmation:
                refs.add(("QA_ANSWER", str(qa.answer_message_id)))
    for emotion in req.selected_emotion_refs:
        refs.add(("EMOTION_SELECTION", emotion.evidence_source_id))
    if req.activity_metric_source_id:
        refs.add(("ACTIVITY_METRIC", req.activity_metric_source_id))
    return frozenset(refs)


def _chip_answer_refs(
    req: contracts.ObservationGenerationRequest,
) -> frozenset[tuple[str, str]]:
    """선택형(OPTION) 답변의 근거 참조 집합 (S15P11B209-994).

    대화 답변 칩은 AI가 만든 보기 문장을 아이가 탭한 것이다 — 아이 표현으로 인정하되
    (게이트 통과 가능) 확신도에서는 발화가 아니라 '고른 것'(_CHOICE)으로 센다.
    실측(2026-08-07)에서 답변의 25.7%(131/510)가 칩이었다.
    """
    return frozenset(
        ("QA_ANSWER", str(qa.answer_message_id))
        for summary in req.subject_summaries
        for qa in summary.qa_pairs
        if qa.answer_message_id is not None
        and (qa.answer_type or "").upper() == "OPTION"
    )


def _blocked_evidence_refs(
    req: contracts.ObservationGenerationRequest,
) -> frozenset[tuple[str, str]]:
    """근거로 쓸 수 없는 참조 (S15P11B209-886). 게이트가 개수를 세기 전에 걸러낸다.

    미확정 STT 발화가 여기 들어간다 — 식별자를 프롬프트에서 빼는 것만으로도 대부분 막히지만,
    모델이 다른 곳에서 본 번호를 옮겨 적을 수 있어 이중으로 막는다.
    위기 발화(889)는 같은 집합에 합쳐진다.
    """
    return frozenset(
        ("QA_ANSWER", str(qa.answer_message_id))
        for summary in req.subject_summaries
        for qa in summary.qa_pairs
        if qa.answer_message_id is not None and qa.stt_needs_confirmation
    )


def _source_ref(
    raw, allowed: frozenset[tuple[str, str]] | None = None
) -> contracts.EvidenceSourceRef | None:
    """{kind, id} 하나를 계약 모델로. 모르는 kind·빈 id는 버린다(조합키·창작 차단).

    allowed 가 주어지면 **요청에 실려 온 식별자인지 대조**한다(886). 지어낸 번호는 형식이
    맞아도 통과하지 못한다.
    """
    if not isinstance(raw, dict):
        return None
    kind = str(raw.get("kind", "")).strip()
    ref_id = str(raw.get("id", "")).strip()
    if kind not in _EVIDENCE_REF_KINDS or not ref_id:
        return None
    if allowed is not None and (kind, ref_id) not in allowed:
        # ⚠️ 식별자 값은 로그로 남기지 않는다 — 종류만.
        logger.warning("요청에 없는 근거 식별자 참조 — 근거 제외(kind=%s)", kind)
        return None
    return contracts.EvidenceSourceRef(kind=kind, id=ref_id)


def _evidence_item(
    raw, allowed: frozenset[tuple[str, str]] | None = None
) -> contracts.ReportEvidenceItem | None:
    """근거 한 건을 계약 모델로. 배타 규칙(source_ref XOR derived_from)을 지키지 않으면 버린다.

    식별자가 없는 근거는 서버가 독립성을 검증할 수 없어 게이트를 무력화한다 → 버린다.
    """
    if not isinstance(raw, dict):
        return None
    try:
        evidence_id = int(raw.get("evidenceId"))
    except (TypeError, ValueError):
        return None
    source_type = str(raw.get("sourceType", "")).strip()
    text = str(raw.get("text", "")).strip()
    if source_type not in _EVIDENCE_SOURCE_TYPES or not text:
        return None
    source_ref = _source_ref(raw.get("sourceRef"), allowed)
    derived = [
        ref
        for ref in (_source_ref(d, allowed) for d in raw.get("derivedFrom") or [])
        if ref is not None
    ]
    # 배타 규칙: 정확히 하나. 둘 다 있거나 둘 다 없으면 무효(875 §4).
    if bool(source_ref) == bool(derived):
        return None
    return contracts.ReportEvidenceItem(
        evidence_id=evidence_id,
        source_type=source_type,
        text=text,
        source_ref=source_ref,
        derived_from=derived or None,
    )


def _evidence_items(
    data: dict, allowed: frozenset[tuple[str, str]] | None = None
) -> list[contracts.ReportEvidenceItem]:
    """근거 풀. evidence_id 중복은 첫 건만 남긴다(참조가 어느 쪽을 가리키는지 모호해진다)."""
    items: list[contracts.ReportEvidenceItem] = []
    seen: set[int] = set()
    for raw in data.get("evidenceItems") or []:
        item = _evidence_item(raw, allowed)
        if item is None or item.evidence_id in seen:
            continue
        seen.add(item.evidence_id)
        items.append(item)
    return items


def _public_interpretation(
    raw, known_ids: set[int]
) -> contracts.PublicInterpretation | None:
    """경향 해석 카드 하나를 계약 모델로. 아래에 걸리면 카드를 **내지 않는다**.

    - category가 계약 밖 / 필수 서술이 빔 / tendencyText가 단정 어조
    - 존재하지 않는 evidenceId 참조만 남음 → 근거 없는 카드가 된다
    표현 안전 필터(591·592)에 걸리면 카드를 빼고 전문가 검토를 올린다 — features와 달리
    카드에는 EXPERT_ONLY 자리가 없어서(875 §3) 강등할 곳이 없다. 조용히 사라지지 않게
    expertReviewRequired 로 신호를 남기는 것은 호출부(_assemble)가 한다.
    """
    if not isinstance(raw, dict):
        return None
    category = str(raw.get("category", "")).strip()
    title = str(raw.get("title", "")).strip()
    tendency = str(raw.get("tendencyText", "")).strip()
    scope = str(raw.get("scopeText", "")).strip()
    guide = str(raw.get("homeObservationGuide", "")).strip()
    if category not in _INTERPRETATION_CATEGORIES:
        return None
    if not (title and tendency and scope and guide):
        return None
    if not any(marker in tendency for marker in _TENTATIVE_MARKERS):
        logger.warning("경향 카드 단정 어조 — 카드 제외(category=%s)", category)
        return None
    refs = []
    for value in raw.get("evidenceRefs") or []:
        try:
            ref = int(value)
        except (TypeError, ValueError):
            continue
        if ref in known_ids and ref not in refs:
            refs.append(ref)
    if not refs:
        logger.warning("경향 카드 근거 참조 없음 — 카드 제외(category=%s)", category)
        return None
    if "confidence" in raw:
        # 모델이 등급을 자칭했다. 값은 읽지 않고 버린다 — 확신도는 근거의 종류로 코드가 정한다
        # (982, interpretation_gate.confidence_for). 프롬프트가 요구하지 않는 키라 이게 뜨면
        # 프롬프트가 밀린 신호이므로 남긴다. ⚠️ 값은 로그에 적지 않는다(등급도 판정 정보다).
        logger.warning("경향 카드에 모델이 확신도를 자칭 — 무시(category=%s)", category)
    return contracts.PublicInterpretation(
        category=category,
        title=title,
        tendency_text=tendency,
        scope_text=scope,
        home_observation_guide=guide,
        evidence_refs=refs,
        # confidence 는 여기서 채우지 않는다. 게이트(interpretation_gate.apply)가 통과 카드에만
        # 찍는다 — 조립 단계에서 채우면 게이트에 걸려 빠질 카드에도 등급이 붙는다.
    )


def _parent_guides(data: dict) -> list[contracts.ReportParentGuide]:
    """보호자 가이드. AI가 만들어도 되는 유형만 남기고 문장 단위로 안전 검사한다."""
    guides: list[contracts.ReportParentGuide] = []
    for raw in data.get("parentGuides") or []:
        if not isinstance(raw, dict):
            continue
        guide_type = str(raw.get("guideType", "")).strip()
        if guide_type not in _AI_GENERATED_GUIDE_TYPES:
            if guide_type:
                # 검토된 문장 세트·고정 템플릿 자리를 LLM이 채우려 한 경우다.
                logger.warning("검토 대상 가이드 유형을 LLM이 생성 — 제외(%s)", guide_type)
            continue
        items = [
            text
            for text in (str(i).strip() for i in raw.get("items") or [])
            if text and not report_safety.has_unsafe_expression(text)
        ]
        if items:
            guides.append(
                contracts.ReportParentGuide(guide_type=guide_type, items=items)
            )
    return guides


# '그린 것' 이름 길이 상한 (S15P11B209-911). 화면에서 쉼표로 이어 붙는 짧은 명사구 자리이고,
#   BE 컬럼 폭을 넘기면 조용히 잘려 이름이 중간에서 끊긴다.
_DRAWN_ITEM_NAME_MAX = 20
# 주제 하나당 상한. 관찰 서술은 2~4문장이라 그보다 많이 나오면 서술이 아니라 탐지 코드 목록을
#   옮겨 적은 것이다(그쪽은 이 목록의 근거가 아니다).
_DRAWN_ITEMS_PER_SUBJECT_MAX = 4


def _drawn_items(
    data: dict, req: contracts.ObservationGenerationRequest
) -> list[contracts.DrawnItem]:
    """'그린 것' 목록 — VLM 관찰 서술에 실제로 등장한 표현만 남긴다 (S15P11B209-911).

    보호자 리포트의 '그린 것' 줄은 지금까지 BE가 탐지 라벨(YOLO)을 그대로 나열해 채웠다.
    탐지 임계값은 0.20이고 그 목록엔 신뢰도 필터가 없어, 겨우 통과한 오탐 라벨이 보호자에게
    확정 사실로 나갔다. 이 목록이 그 자리를 대신한다(BE 배선은 S15P11B209-912).

    ⚠️ 프롬프트에 맡기지 않고 **코드가 서술 원문과 대조**한다(886의 식별자 대조와 같은 결).
       서술에 없는 이름은 버린다 — 모델이 '탐지된 요소 코드' 줄을 옮겨 적어도 통과하지 못한다.
       "쓰지 마"라고 부탁하는 것보다 통과시키지 않는 편이 확실하다.
       대조는 부분 문자열 포함이다. 한국어는 조사가 붙어 오므로("집이"·"문은") 어절 경계로
       맞출 수 없고, 그래서 짧은 이름이 다른 낱말의 조각으로도 통과할 수 있다("창문"만
       적힌 서술에서 "문"). 막는 대상은 **없는 대상을 지어내는 것**이라 이 느슨함은 감수한다 —
       조각 이름은 오분류일 뿐이고, 서술에 아예 없는 대상은 여기서 걸린다.

    주제 순서는 요청의 subject_summaries 순서를 따른다 — BE가 이 이름들을 쉼표로 이어 한 줄로
    보이므로 순서가 곧 문장이다.

    subject_summaries 가 없는 레거시 draft 경로(drawing_description 인자)는 대조할 원문이
    _assemble 에 없어 빈 목록이 된다. 운영 경로는 항상 주제별 블록으로 온다.
    """
    descriptions = {
        summary.drawing_subject: summary.drawing_description or ""
        for summary in req.subject_summaries
    }
    subject_order = {
        summary.drawing_subject: index
        for index, summary in enumerate(req.subject_summaries)
    }
    items: list[contracts.DrawnItem] = []
    seen: set[tuple[str | None, str]] = set()
    counts: dict[str | None, int] = {}
    dropped = 0
    for raw in data.get("drawnItems") or []:
        if not isinstance(raw, dict):
            dropped += 1
            continue
        name = str(raw.get("name", "")).strip()
        subject = str(raw.get("drawingSubject") or "").strip().upper() or None
        # 요청에 없는 주제는 그리지 않은 그림이다. 서술이 빈 주제는 대조할 원문이 없다.
        description = descriptions.get(subject)
        if not name or len(name) > _DRAWN_ITEM_NAME_MAX or not description:
            dropped += 1
            continue
        if name not in description:
            dropped += 1
            continue
        if (subject, name) in seen:
            continue
        if counts.get(subject, 0) >= _DRAWN_ITEMS_PER_SUBJECT_MAX:
            dropped += 1
            continue
        seen.add((subject, name))
        counts[subject] = counts.get(subject, 0) + 1
        items.append(contracts.DrawnItem(drawing_subject=subject, name=name))
    if dropped:
        # ⚠️ 이름 값은 남기지 않는다 — 서술에 없던 값이 로그에 쌓일 이유가 없다.
        logger.info("'그린 것' 항목 %d건 제외 — 관찰 서술에 없는 이름·초과분", dropped)
    # sorted 는 안정 정렬이라 주제 안의 모델 출력 순서는 그대로 유지된다.
    return sorted(
        items, key=lambda item: subject_order.get(item.drawing_subject, len(subject_order))
    )


# ── 주제별 관찰 (875 §5 · S15P11B209-HTP 주제 분리) ──────────────
# 그림 한 장당 관찰 문장 상한. VLM 관찰 서술 자체가 2~4문장이라 그보다 많이 나오면 서술에 없는
#   것을 늘려 쓴 것이다(_DRAWN_ITEMS_PER_SUBJECT_MAX 와 같은 결).
_VISION_OBSERVATIONS_PER_SUBJECT_MAX = 4
# 875 §5 가 못 박은 표시 순서. **요청 순서가 아니라 이 순서가 계약이다** —
#   BE가 스냅샷을 그대로 쓰므로 여기서 어긋나면 화면에서 나무가 집보다 먼저 나온다.
_SUBJECT_REPORT_ORDER = ("HOUSE", "TREE", "PERSON")


def _kept_positions(before: list, after: list) -> list[int]:
    """after(순서를 지킨 부분집합)의 각 원소가 before 의 몇 번째였는지.

    경향 카드가 게이트·자체검토에서 빠질 때마다 배열 위치가 앞으로 당겨진다. 주제별 관찰의
    interpretation_refs 는 그 **위치**를 가리키므로(875 §5-1), 다시 매핑하지 않으면 참조가
    조용히 다른 카드를 가리킨다 — 875가 "재정렬하지 마라"로 경고한 바로 그 사고다.
    값 비교(==)가 아니라 **동일성(is)** 으로 맞춘다. 같은 내용의 카드가 두 장이면 값 비교는
    앞 카드에 붙어 매핑이 어긋난다.
    """
    positions: list[int] = []
    remaining = iter(enumerate(before))
    for item in after:
        for index, candidate in remaining:
            if candidate is item:
                positions.append(index)
                break
    return positions


def _subject_reports(
    data: dict,
    req: contracts.ObservationGenerationRequest,
    ref_map: dict[int, int],
) -> tuple[list[contracts.SubjectReportDraft], bool]:
    """주제별 관찰 묶음 (875 §5). 두 번째 반환값은 '규칙 필터가 문장을 걸렀는가'다.

    HTP는 집·나무·사람 세 장을 그리는데 지금까지 응답에는 주제 구분이 남지 않았다.
    이 목록이 '주제별 관찰 사실과 문답' 섹션(875 §11-5)의 AI 몫이다 —
    image_url·qa_pairs 는 BE가 자기 데이터로 채운다(계약 모델 docstring 참조).

    ⚠️ **골격은 요청이 정한다.** 모델이 주제를 빠뜨리거나 순서를 뒤집어도 그 그림이 리포트에서
       사라지지 않게, req.subject_summaries 의 주제마다 한 칸씩 만들고 거기에 모델 내용을 얹는다.
       순서는 HOUSE → TREE → PERSON 고정(875 §5). 요청에 없는 주제는 그리지 않은 그림이라 버린다.

    ⚠️ 관찰 서술이 없는 그림은 문장을 받지 않는다. 대조할 원본이 없는데 관찰 사실을 적으면
       그건 관찰이 아니라 창작이다(_drawn_items 가 서술 원문과 대조하는 것과 같은 원칙).

    ref_map: LLM이 적은 카드 순번(자기 출력 기준) → 게이트를 통과한 최종 배열 위치.
    """
    if not req.subject_summaries:
        # 레거시 draft 경로(subject_summaries 없음) — 주제가 없으니 만들 것도 없다.
        return [], False

    descriptions: dict[str | None, str] = {}
    order: list[str | None] = []
    for summary in req.subject_summaries:
        if summary.drawing_subject in descriptions:
            continue
        descriptions[summary.drawing_subject] = (summary.drawing_description or "").strip()
        order.append(summary.drawing_subject)
    # 안정 정렬이라 계약에 없는 주제(그림일기의 None)는 요청 순서를 지킨 채 뒤로 밀린다.
    order.sort(
        key=lambda subject: (
            _SUBJECT_REPORT_ORDER.index(subject)
            if subject in _SUBJECT_REPORT_ORDER
            else len(_SUBJECT_REPORT_ORDER)
        )
    )

    raw_by_subject: dict[str | None, dict] = {}
    for raw in data.get("subjectReports") or []:
        if not isinstance(raw, dict):
            continue
        subject = str(raw.get("subjectType") or "").strip().upper() or None
        if subject not in descriptions or subject in raw_by_subject:
            continue
        raw_by_subject[subject] = raw

    flagged = False
    reports: list[contracts.SubjectReportDraft] = []
    for subject in order:
        raw = raw_by_subject.get(subject) or {}
        observations: list[str] = []
        if descriptions.get(subject):
            for value in raw.get("visionObservations") or []:
                if len(observations) >= _VISION_OBSERVATIONS_PER_SUBJECT_MAX:
                    break
                text = str(value).strip()
                if not text or text in observations:
                    continue
                if report_safety.has_unsafe_expression(text):
                    # ⚠️ 원문은 남기지 않는다 — 관찰 문장에 아이 표현이 섞일 수 있다.
                    # 관찰 '사실' 자리에 단정·낙인이 섞이면 다른 문장들이 그걸 사실로 알고
                    # 기대게 된다 — 문장만 빼고 리포트는 미검토(AI_DRAFT)로 남긴다.
                    logger.warning("주제별 관찰 사실 단정·낙인 표현 — 문장 제외·자체검토 실패")
                    flagged = True
                    continue
                observations.append(text)
        refs: list[int] = []
        for value in raw.get("interpretationRefs") or []:
            try:
                index = int(value)
            except (TypeError, ValueError):
                continue
            mapped = ref_map.get(index)
            if mapped is not None and mapped not in refs:
                refs.append(mapped)
        reports.append(
            contracts.SubjectReportDraft(
                subject_type=subject,
                vision_observations=observations,
                interpretation_refs=refs,
            )
        )
    return reports, flagged


def _generation_version(is_htp: bool) -> str:
    """리포트 재현성 버전 태그 — 프롬프트·파이프라인 버전을 함께 기록한다(S15P11B209-602).

    ObservationGenerationResult 계약엔 prompt/pipeline 전용 필드가 없어(BE 소유), model_version
    문자열에 둘을 함께 실어 재현·재분석에 필요한 버전을 모두 남긴다(모델 ID는 model_name).
    형식: "pipeline=<파이프라인>;prompt=<이번에 쓴 프롬프트 조합 버전>".

    프롬프트가 활동별로 갈린 뒤로는 '이번 생성이 실제로 쓴' 조합만 싣는다 — 두 변형을 모두
    적으면 어느 쪽으로 뽑힌 결과인지 사후에 구분할 수 없다. 전용 필드 분리는 BE 계약 확장 후속.

    프롬프트 조합은 축약 태그로 싣는다(S15P11B209-819) — 정본을 그대로 실으면 파일이 갈릴 때마다
    길어져 BE 컬럼을 넘긴다. 정본은 version_manifest()로 되짚는다.
    """
    label = "htp" if is_htp else "diary"
    # 자체검토 프롬프트도 조합에 넣는다 — 검토 기준이 바뀌면 어떤 리포트가 보호자에게 열리는지가
    # 바뀌는데 태그가 그대로면 "같은 버전인데 결과가 다른" 상태가 된다(832와 같은 사고 유형).
    prompt = prompts_registry.short_version(
        label, *_prompt_names(is_htp), _review_prompt_name(is_htp)
    )
    return f"pipeline={config.PIPELINE_VERSION};prompt={prompt}"


def _safe_follow_up(raw, *, is_htp: bool = True) -> str:
    """보호자용 후속 질문을 안전하게 보장한다(S15P11B209-601).

    비어 있거나 단정 진단·과잉 추론 표현이 섞이면 안전한 기본 질문으로 대체한다. 후속 질문은
    보호자가 아이에게 그대로 건네는 문장이라, 진단성 표현을 그대로 내보내면 안 된다(제거).

    모델이 스키마(문자열)를 벗어나 {questionText, questionPurpose} 객체로 주는 경우가 있어,
    dict면 questionText만 뽑아낸다 — 안 그러면 dict가 통째로 문자열화돼 화면에 새어 나간다.
    """
    if isinstance(raw, dict):
        raw = raw.get("questionText", "")
    text = str(raw or "").strip()
    unsafe = (
        report_safety.has_unsafe_expression(text)
        if is_htp
        else diary_report_v2.has_unsafe_diary_expression(text)
    )
    if not text or unsafe:
        return DEFAULT_FOLLOW_UP_QUESTION
    return text


def _assemble(
    req: contracts.ObservationGenerationRequest,
    data: dict,
    model: str,
    rag_chunks: list[Chunk] | None = None,
    rag_skipped_reason: str | None = None,
    is_htp: bool | None = None,
) -> tuple[contracts.ObservationGenerationResult, bool]:
    """LLM 정성 결과(data) + 서버 고정 필드를 합쳐 (계약 결과, 규칙 위반 여부)를 만든다.

    rag_chunks(614)가 있으면 출처 목록과 KB Version을 함께 싣는다 — 출처 표시는
    라이선스 의무이자 리포트 재현성 재료(어떤 지식 근거로 생성됐나).

    두 번째 반환값은 **규칙 필터(report_safety)가 무언가를 걸렀는가**다. 이건 리포트 품질
    실패이지 '아이가 걱정된다'는 신호가 아니라서 expert_review_required 로 올리지 않는다
    (2026-08-05 계약: expertReviewRequired = 사람 상담을 권할 신호). 대신 자체검토 실패로
    이어져 status 가 AI_DRAFT 로 남고, BE는 그 리포트의 관찰 카드를 보호자에게 열지 않는다.
    ⚠️ 강등·제외가 이미 끝난 결과만으로는 이 사실을 되짚을 수 없어(제외된 카드는 사라진다)
       조립 시점에 함께 돌려준다 — 신호를 잃지 않기 위한 것이다.
    """
    if is_htp is None:
        is_htp = _is_htp(req)
    conv = data.get("conversationSummary") or {}
    all_features = [
        _feature(f) for f in data.get("features", []) if isinstance(f, dict)
    ]
    # 단일 그림일기에서 여러 해석 카드가 반복 노출되지 않도록 레거시 feature는 최대 1개만
    # 유지한다. 안전 스캔은 아래에서 all_features 전체에 수행해 모델이 만든 위험 문장을 놓치지 않는다.
    features = all_features if is_htp else all_features[:1]

    # 단정적 진단(591)이나 감정·성격 과잉 추론(592) 표현이 보호자 노출 문장·특징에 하나라도
    # 있으면 자체검토 실패로 처리한다(status=AI_DRAFT). attentionPoints는 여기 없는데, 이제
    # 그것도 보호자가 읽는 자리다 — 아래에서 따로 검사해 합친다.
    diary_signals = data.get("diarySignals") or {}
    diary_story = diary_signals.get("storySnapshot") if isinstance(diary_signals, dict) else {}
    diary_flow = diary_signals.get("narrativeFlow") if isinstance(diary_signals, dict) else []
    diary_observations = (
        diary_signals.get("sessionObservations") if isinstance(diary_signals, dict) else []
    )
    diary_questions = (
        diary_signals.get("caregiverQuestions") if isinstance(diary_signals, dict) else []
    )
    guardian_texts = [
        str(data.get("overallSummary", "")),
        str(data.get("positiveSignals", "")),
        # attentionPoints 는 2026-08-05 계약에서 '보호자가 다음에 더 지켜볼 점'이 됐다.
        # 전문가 전용 채널이던 시절의 검사 면제를 그대로 두면, 보호자가 읽는 자리 하나가
        # 규칙 필터 밖에 남는다.
        str(data.get("attentionPoints", "")),
        str(data.get("evidenceSummary", "")),
        str(data.get("guardianGuidance", "")),
        str(data.get("followUpQuestion", "")),
        str(conv.get("summaryText", "")),
        str(conv.get("mainTopic", "")),
        str(conv.get("expressedEmotion", "")),
        *(f"{f.title} {f.description} {f.evidence_summary}" for f in all_features),
        *(
            f"{g.get('guidance', '')} {g.get('detailText', '')}"
            for g in (data.get("followUpGuides") or [])
            if isinstance(g, dict)
        ),
        *(
            f"{q.get('questionText', '')} {q.get('questionPurpose', '')}"
            for q in (data.get("guardianQuestions") or [])
            if isinstance(q, dict)
        ),
        *(
            str(item)
            for guide in (data.get("parentGuides") or [])
            if isinstance(guide, dict)
            for item in (guide.get("items") or [])
        ),
        *(
            str((diary_story or {}).get(key, ""))
            for key in ("headline", "summary", "mainEvent")
            if isinstance(diary_story, dict)
        ),
        *(
            str(item.get("text", ""))
            for item in (diary_flow or [])
            if isinstance(item, dict)
        ),
        *(
            f"{item.get('title', '')} {item.get('description', '')}"
            for item in (diary_observations or [])
            if isinstance(item, dict)
        ),
        *(
            f"{item.get('question', '')} {item.get('purpose', '')}"
            for item in (diary_questions or [])
            if isinstance(item, dict)
        ),
        str(diary_signals.get("listeningTip", ""))
        if isinstance(diary_signals, dict)
        else "",
    ]
    rule_flagged = (
        report_safety.has_unsafe_expression(*guardian_texts)
        if is_htp
        else diary_report_v2.has_unsafe_diary_expression(*guardian_texts)
    )

    # ── 경향 해석 (S15P11B209-887 조립 + 888 구조 게이트) ────────
    # 근거 풀을 먼저 만들고, 카드는 그 풀에 실제로 있는 근거만 참조하게 한다.
    # 요청에 실려 온 식별자만 근거로 인정한다(886) — 형식만 맞는 창작 번호를 막는다.
    evidence_items = _evidence_items(data, _allowed_evidence_refs(req))
    known_ids = {item.evidence_id for item in evidence_items}
    interpretations: list[contracts.PublicInterpretation] = []
    # 주제별 관찰(875 §5)의 interpretation_refs 가 가리킬 '원래 순번'을 기억해 둔다 —
    # 아래에서 카드가 빠질 때마다 배열 위치가 당겨지므로, 모델이 자기 출력 기준으로 적은
    # 순번을 최종 위치로 다시 매핑해야 참조가 어긋나지 않는다(875 §5-1).
    raw_index_of: list[int] = []
    raw_interpretations = data.get("publicInterpretations") or []
    # 그림일기 단일 회차에서 레거시 '주요 심리 경향' 카드를 노출하지 않는다. V2의
    # sessionObservations가 이번 활동 한정 표현을 근거와 함께 대신한다. HTP는 기존 의미를 유지한다.
    if not is_htp and raw_interpretations:
        logger.info("그림일기 publicInterpretations %d건 제외", len(raw_interpretations))
        raw_interpretations = []
    for raw_index, raw in enumerate(raw_interpretations):
        # 표현 안전 검사를 **구조 검사보다 먼저** 원문에 돌린다. 순서를 바꾸면 형식까지 어긋난
        # 카드가 구조 검사에서 먼저 걸러져, 진단·낙인 표현이 있었다는 신호가 사라진다.
        # 카드에는 EXPERT_ONLY 자리가 없어(875 §3) 강등할 곳이 없다 — 빼고 신호를 남긴다.
        if isinstance(raw, dict) and report_safety.has_unsafe_expression(
            *(
                str(raw.get(key, ""))
                for key in ("title", "tendencyText", "scopeText", "homeObservationGuide")
            )
        ):
            logger.warning("경향 카드 과도 규정·단정 표현 — 카드 제외·자체검토 실패")
            rule_flagged = True
            continue
        card = _public_interpretation(raw, known_ids)
        if card is not None:
            interpretations.append(card)
            raw_index_of.append(raw_index)
    # 구조적 공개 게이트(S15P11B209-888) — 값싼 결정적 검사라 표현 필터보다 먼저 돌린다.
    # 실패한 카드는 EXPERT_ONLY로 강등하지 않고 **제외**한다(근거 자체가 없다).
    # blocked_refs: 미확정 STT(886)를 배제한다. 위기 발화(889)가 같은 집합에 합쳐진다.
    parsed_cards = interpretations
    interpretations, gate_reasons = interpretation_gate.apply(
        parsed_cards,
        evidence_items,
        blocked_refs=_blocked_evidence_refs(req),
        # 선택형(OPTION) 답변은 발화가 아니라 '고른 것'으로 등급을 매긴다(994).
        chip_answer_refs=_chip_answer_refs(req),
    )
    # 확신도 대비 과장 검사(982) — **게이트 뒤에** 돈다. 등급은 게이트가 찍으므로 그 전에는
    # 기준이 없다. 약한 근거로 강하게 말한 카드를 여기서 뺀다("약한 근거 → 강한 주장" 승격 차단).
    # 주장 문장(title·tendencyText)만 본다 — homeObservationGuide 는 "평소에도 그런지 살펴봐
    # 주세요"가 정상인 자리라 같은 어휘를 막으면 그 필드를 못 쓴다.
    overclaimed = [
        card
        for card in interpretations
        if report_safety.has_overclaim(
            f"{card.title} {card.tendency_text}", card.confidence
        )
    ]
    if overclaimed:
        # ⚠️ 카드 문장은 로그에 남기지 않는다 — 관점 라벨과 등급만(등급도 값이라 개수만 센다).
        logger.warning("경향 카드 확신도 대비 과장 — 카드 제외 %d건", len(overclaimed))
        rule_flagged = True
        excluded = {id(card) for card in overclaimed}
        interpretations = [c for c in interpretations if id(c) not in excluded]
    # 모델이 적은 카드 순번 → 최종 배열 위치. 빠진 카드를 가리키던 참조는 매핑에 없어 사라진다.
    ref_map = {
        raw_index_of[position]: final
        for final, position in enumerate(_kept_positions(parsed_cards, interpretations))
    }
    if gate_reasons:
        # 사유 코드만 남긴다 — 카드 문장·아이 발화는 로그에 담지 않는다.
        logger.info("경향 카드 게이트 제외 %d건: %s", len(gate_reasons), sorted(set(gate_reasons)))
    # 아무 카드도 참조하지 않는 근거는 싣지 않는다 — 화면에 쓰이지 않는 아이 발화 인용이
    # 응답에 남는 것을 막는다(최소 노출).
    referenced = {ref for card in interpretations for ref in card.evidence_refs}
    evidence_items = [i for i in evidence_items if i.evidence_id in referenced]
    parent_guides = _parent_guides(data)
    # 주제별 관찰(875 §5). 카드 매핑이 끝난 뒤에 만든다 — 순번을 최종 배열 기준으로 적어야 한다.
    subject_reports, subject_flagged = _subject_reports(data, req, ref_map)
    if not is_htp:
        for report in subject_reports:
            report.vision_observations = report.vision_observations[:2]
    rule_flagged = rule_flagged or subject_flagged

    raw_activity_notes = [str(n) for n in data.get("activityNotes", [])]
    raw_follow_up_guides = [
        contracts.FollowUpGuideDraft(
            guidance=str(g.get("guidance", "")),
            detail_text=str(g.get("detailText", "")),
        )
        for g in data.get("followUpGuides", [])
        if isinstance(g, dict)
    ]
    raw_guardian_questions = [
        contracts.GuardianQuestionDraft(
            question_text=str(q.get("questionText", "")),
            question_purpose=str(q.get("questionPurpose", "")),
        )
        for q in data.get("guardianQuestions", [])
        if isinstance(q, dict)
    ]
    activity_notes = raw_activity_notes if is_htp else raw_activity_notes[:2]
    follow_up_guides = raw_follow_up_guides if is_htp else raw_follow_up_guides[:2]
    guardian_questions = (
        raw_guardian_questions if is_htp else raw_guardian_questions[:2]
    )

    observation = contracts.ObservationDraft(
        # 조립 단계는 언제나 '미검토'다 — 자체검토(_self_review)만 AI_REVIEWED 로 올릴 수 있다.
        status=REVIEW_STATUS_DRAFT,
        overall_summary=str(data.get("overallSummary", "")),
        positive_signals=str(data.get("positiveSignals", "")),
        attention_points=str(data.get("attentionPoints", "")),
        evidence_summary=str(data.get("evidenceSummary", "")),
        guardian_guidance=str(data.get("guardianGuidance", "")),
        # 후속 질문은 비었거나 진단성 표현이 섞이면 안전 기본값으로 대체·보장한다(S15P11B209-601).
        # raw를 그대로 넘긴다 — 객체({questionText,...})로 와도 _safe_follow_up이 questionText를 뽑는다.
        follow_up_question=_safe_follow_up(
            data.get("followUpQuestion", ""), is_htp=is_htp
        ),
        # 2026-08-05 계약: expertReviewRequired = '사람 상담을 권할 신호'(아이 이야기)다.
        # 예전에는 여기에 규칙 필터 적중(rule_flagged)을 OR 로 얹었는데, 그건 '리포트에 진단어가
        # 섞였다'는 품질 실패라 뜻이 다르다 — 둘을 합치면 문장 사고가 상담 권유로 둔갑한다.
        # 품질 실패는 status(AI_DRAFT)로 간다. 담는 곳이 갈렸을 뿐 격리가 약해지지는 않는다:
        # 구 경로에서 이 불리언은 BE Report.expertReviewRecommended 컬럼에만 저장되고 읽는 곳이
        # 없었던 반면, status 는 BE가 관찰 카드 공개 여부를 정하는 데 실제로 쓴다.
        expert_review_required=bool(data.get("expertReviewRequired", False)),
        disclaimer=DISCLAIMER,
        features=features,
    )
    conversation_summary = contracts.ConversationSummaryDraft(
        summary_text=str(conv.get("summaryText", "")),
        main_topic=str(conv.get("mainTopic", "")),
        expressed_emotion=str(conv.get("expressedEmotion", "")),
        emotion_source=_emotion_source(req),
        # 아이가 실제로 한 말만 싣는다. 없으면 None — 무난한 문장으로 채우지 않는다.
        #   폐지된 기본값("재미있었어요.")은 운영 51건 중 34건을 차지했다. 아무도 읽지 않는
        #   컬럼이었지만, 나중에 읽는 기능이 생기면 그대로 가짜 인용이 된다.
        #   바로 아래 confidence=None 과 같은 원칙이다(지어내지 않는다).
        representative_utterance=req.representative_utterance,
    )
    result = contracts.ObservationGenerationResult(
        request_id=req.request_id,
        # 재현성(S15P11B209-602): model_name=실제 서빙 모델, model_version=프롬프트+파이프라인 버전.
        model_name=model,
        model_version=_generation_version(is_htp),
        confidence=None,  # LLM 서술엔 보정된 신뢰도가 없다 — 지어내지 않고 None.
        observation_draft=observation,
        conversation_summary=conversation_summary,
        activity_notes=activity_notes,
        follow_up_guides=follow_up_guides,
        guardian_questions=guardian_questions,
        limitations_text=LIMITATIONS,
        rag_references=_rag_references(rag_chunks or []),
        # 근거를 실제로 썼을 때만 KB Version을 싣는다 — 근거 없는 리포트에 버전이 붙으면
        # "이 지식에 기반했다"는 거짓 신호가 된다.
        knowledge_base_version=(
            rag_knowledge_base_version() if rag_chunks else None
        ),
        rag_skipped_reason=rag_skipped_reason,
        # 경향 해석(S15P11B209-887). 근거가 모자라면 빈 목록이고, 그것이 정상이다(875 §10).
        public_interpretations=interpretations,
        evidence_items=evidence_items,
        parent_guides=parent_guides,
        # 주제별 관찰(875 §5). HTP 세 장의 구분이 여기서만 남는다 — 비면 지금까지와 같다.
        subject_reports=subject_reports,
        # '그린 것'(S15P11B209-911). 서술 원문과 대조해 통과한 이름만 실린다.
        drawn_items=_drawn_items(data, req),
        # 위기 안내는 S15P11B209-889이 채운다 — LLM 결과에서 만들지 않는다.
        crisis_alert=None,
        # 그림일기 전용 V2. 근거 식별자를 원본 요청과 대조한 뒤 조립하므로, 모델이 만든
        # 참조나 실제/상상·시점 추정은 그대로 통과하지 않는다. HTP에서는 None이다.
        diary_insights=(
            None
            if is_htp
            else diary_report_v2.build_diary_insights(
                data.get("diarySignals"),
                req,
                vision_available=any(
                    (summary.drawing_description or "").strip()
                    for summary in req.subject_summaries
                ),
            )
        ),
    )
    return result, rule_flagged


# ── AI 자체검토 (2-pass, 2026-08-05) ─────────────────────────────
# 사람 전문가 검토자가 없는 자리를 AI가 대신한다. 통과분만 AI_REVIEWED 로 올려 보호자 경로를 연다.
#
# 층을 나눈 이유(중복 구현 아님):
#   1층 report_safety(정규식) — 형태가 정해진 표현(장애명·단정 종결·고정 특질 규정). 값싸고 결정적이라
#      먼저 돌고, 개별 feature 강등·카드 제외는 조립 단계에서 이미 끝난다.
#   2층 여기(LLM) — 규칙으로 못 잡는 것만 맡는다: 근거 없는 단정, 활동 밖 확대, 근거 칸에 섞인 해석.
#      문장을 읽어야 판정되는 것들이라 정규식으로는 원리적으로 잡히지 않는다.
# 그래서 2층은 1층을 다시 돌리지 않고, 1층 결과(rule_flagged)를 그대로 이어받아 합친다.
#
# 실패는 차단이 아니라 기능 저하다(RAG·548과 같은 정책) — 검토 호출이 실패하면 리포트는 그대로
# 반환하되 status 를 AI_DRAFT 로 남긴다. '검토 못 했으니 열지 않는다'가 보수적인 쪽이다.
_LEGACY_REVIEW_ISSUES = frozenset(
    {
        "DIAGNOSTIC",
        "STIGMA",
        "NO_EVIDENCE",
        "OVERCLAIM",
        "OVERREACH",
        "MIXED_EVIDENCE",
    }
)
_DIARY_REVIEW_ISSUES = frozenset(
    {
        # 그림일기 V2 품질 문제. 안전 위반뿐 아니라 보호자에게 쓸모없는 반복·일반론과
        # 자발 발화/실제 경험을 과장하는 문장도 마지막 관문에서 제거한다.
        "DUPLICATE_CONTENT",
        "GENERIC_GUIDANCE",
        "NOT_ACTIONABLE",
        "UNSUPPORTED_TREND",
        "ELICITATION_OVERCLAIM",
        "REALITY_COLLAPSE",
        "TIME_SCOPE_OVERCLAIM",
        "VISUAL_UNCERTAINTY_EXPOSED",
        "CHILD_VOICE_DISTORTION",
    }
)
# 테스트·관측용 전체 코드 목록. 실제 파싱 허용 목록은 활동별로 분리한다.
_REVIEW_ISSUES = _LEGACY_REVIEW_ISSUES | _DIARY_REVIEW_ISSUES
# 검토 결과를 담을 수 있는 자리 — 지적당한 항목만 빼고 나머지는 살린다.
_FEATURE_TARGET_PREFIX = "feature."
_CARD_TARGET_PREFIX = "card."
_SUBJECT_TARGET_PREFIX = "subject."
# 검토 대상 중 '관찰 사실을 적는 자리'임을 검토자에게 알리는 표시. 해석 자리와 판정 기준이
#   다르다(사실 자리에 해석이 섞이면 MIXED_EVIDENCE) — report_review.txt 가 이 값을 읽는다.
_FACT_SLOT_LABEL = "관찰 사실"

# 자체검토 결과 카운터. outcome: passed | contained | failed | unavailable.
#   contained = 지적이 있었지만 관찰 카드 강등·경향 카드 제외로 담아내고 통과시킨 경우.
#   ⚠️ 지적 내용(note)·원문은 어디에도 남기지 않는다 — 아이 표현이 섞일 수 있다(가드레일 9절).
_SELF_REVIEW_COUNTER = PrometheusCounter(
    "dodam_report_self_review_total",
    "관찰 리포트 AI 자체검토 결과 (outcome별 누적)",
    labelnames=("outcome",),
)


def _review_facts(
    result: contracts.ObservationGenerationResult,
    req: contracts.ObservationGenerationRequest,
    *,
    is_htp: bool,
    drawing_description: str | None = None,
) -> list[str]:
    """검토자에게 줄 [관찰 사실] 목록.

    그림일기는 원본 요청에서 확인된 사실만 사용한다. 생성 모델이 만든 evidenceSummary·
    activityNotes를 다시 사실 풀에 넣으면 첫 호출의 창작이 두 번째 호출에서 자기 근거가 되는
    순환이 생기기 때문이다. HTP는 다른 담당 영역의 기존 검토 의미를 보존하기 위해 레거시
    사실 풀을 그대로 유지한다.
    """
    if not is_htp:
        return diary_report_v2.raw_review_facts(
            req, drawing_description=drawing_description
        )

    facts = [result.observation_draft.evidence_summary, *result.activity_notes]
    facts.extend(item.text for item in result.evidence_items)
    facts.extend(f.evidence_summary for f in result.observation_draft.features)
    facts.extend(
        text for report in result.subject_reports for text in report.vision_observations
    )
    return [text.strip() for text in facts if text and text.strip()]


def _review_targets(
    result: contracts.ObservationGenerationResult,
    req: contracts.ObservationGenerationRequest,
    *,
    is_htp: bool,
) -> list[dict[str, object]]:
    """검토 대상 항목 목록. id 는 코드가 발급하고, 모델은 그대로 되돌려 주기만 한다.

    보호자에게 닿는 글 중 **해석이 실릴 수 있는 것**만 담는다 — 검토는 '보호자 노출 전 관문'이지
    전수 감사가 아니고, 대상이 늘수록 한 건의 지적이 리포트 전체를 떨어뜨릴 확률만 는다.
    drawnItems·evidenceItems는 사실 원본이므로 검토 대상이 아니다. 그림일기에서는 보호자에게
    바로 노출되는 guardianQuestions·parentGuides·diaryInsights도 항목 단위로 검토한다.
    HTP에서는 기존 대상 집합을 그대로 유지한다.
    """
    draft = result.observation_draft
    targets: list[dict[str, object]] = []
    named = {
        "draft.overallSummary": draft.overall_summary,
        "draft.positiveSignals": draft.positive_signals,
        "draft.attentionPoints": draft.attention_points,
        # 근거 풀이면서 동시에 검토 대상이다. 여기 해석이 섞이면(MIXED_EVIDENCE) 다른 문장들이
        # 그걸 사실로 알고 기대게 되므로, 근거 자리야말로 검토에서 빠지면 안 된다.
        "draft.evidenceSummary": draft.evidence_summary,
        "draft.guardianGuidance": draft.guardian_guidance,
        "draft.followUpQuestion": draft.follow_up_question,
        "conversation.summaryText": result.conversation_summary.summary_text,
    }
    for target_id, text in named.items():
        if text and text.strip():
            targets.append({"id": target_id, "글": text.strip()})
    for index, note in enumerate(result.activity_notes):
        if note and note.strip():
            targets.append({"id": f"activityNote.{index}", "글": note.strip()})
    for index, guide in enumerate(result.follow_up_guides):
        if guide.guidance and guide.guidance.strip():
            targets.append({"id": f"followUpGuide.{index}", "글": guide.guidance.strip()})
    if not is_htp:
        for index, question in enumerate(result.guardian_questions):
            if question.question_text and question.question_text.strip():
                targets.append(
                    {
                        "id": f"guardianQuestion.{index}",
                        "글": question.question_text.strip(),
                    }
                )
        for guide_index, guide in enumerate(result.parent_guides):
            for item_index, text in enumerate(guide.items):
                if text and text.strip():
                    targets.append(
                        {
                            "id": f"parentGuide.{guide_index}.{item_index}",
                            "글": text.strip(),
                        }
                    )
    for index, feature in enumerate(draft.features):
        # 이미 EXPERT_ONLY 인 카드는 보호자에게 나가지 않으므로 검토 대상이 아니다 —
        # 넣으면 검토자가 '무거운 관찰'을 또 잡아 리포트 전체를 떨어뜨린다.
        if feature.visibility_scope == "EXPERT_ONLY":
            continue
        targets.append(
            {
                "id": f"{_FEATURE_TARGET_PREFIX}{index}",
                "글": f"{feature.title} / {feature.description}".strip(" /"),
                "근거": feature.evidence_summary,
            }
        )
    for index, card in enumerate(result.public_interpretations):
        if is_htp:
            card_evidence: object = card.scope_text
        else:
            evidence_by_id = {item.evidence_id: item for item in result.evidence_items}
            raw_evidence: list[str] = []
            for evidence_id in card.evidence_refs:
                item = evidence_by_id.get(evidence_id)
                if item is None:
                    continue
                refs = []
                if item.source_ref is not None:
                    refs.append(item.source_ref)
                refs.extend(item.derived_from or [])
                for text in diary_report_v2.evidence_texts_for_ids(req, refs):
                    if text not in raw_evidence:
                        raw_evidence.append(text)
            card_evidence = raw_evidence
        target = {
            "id": f"{_CARD_TARGET_PREFIX}{index}",
            "글": f"{card.title} / {card.tendency_text}".strip(" /"),
            "근거": card_evidence,
        }
        # 확신도를 검토자에게 함께 준다(982) — '이 글이 근거에 비해 세게 말하는가'(OVERCLAIM)는
        # 등급을 모르면 판정할 수 없다. 등급 자체는 코드가 정한 값이라 검토자가 바꾸지 못한다:
        # 검토자는 issue 코드만 돌려주고, 이 값을 되돌려 받아 쓰는 경로가 없다.
        if card.confidence:
            target["확신도"] = card.confidence
        targets.append(target)
    # 주제별 관찰(875 §5) — 보호자가 그대로 읽는 **사실 자리**다. draft.evidenceSummary 를
    # 검토 대상에 넣은 것과 같은 이유로 넣는다: 여기 해석이 섞이면(MIXED_EVIDENCE) 카드·요약이
    # 그걸 사실로 알고 기댄다. 지적당해도 그 문장 하나만 빠지므로 리포트를 막지 않는다.
    for subject_index, report in enumerate(result.subject_reports):
        for text_index, text in enumerate(report.vision_observations):
            targets.append(
                {
                    "id": f"{_SUBJECT_TARGET_PREFIX}{subject_index}.{text_index}",
                    "글": text,
                    "자리": _FACT_SLOT_LABEL,
                }
            )
    diary = result.diary_insights
    if not is_htp and diary is not None:
        if diary.story_snapshot is not None:
            targets.append(
                {
                    "id": "diary.story",
                    "글": " / ".join(
                        part
                        for part in (
                            diary.story_snapshot.headline,
                            diary.story_snapshot.summary,
                            diary.story_snapshot.main_event,
                        )
                        if part
                    ),
                    "근거": diary_report_v2.evidence_texts_for_ids(
                        req, diary.story_snapshot.evidence_refs
                    ),
                }
            )
        for index, step in enumerate(diary.narrative_flow):
            targets.append(
                {
                    "id": f"diary.flow.{index}",
                    "글": step.text,
                    "근거": diary_report_v2.evidence_texts_for_ids(req, step.evidence_refs),
                }
            )
        for index, observation in enumerate(diary.session_observations):
            # 가설과 다른 설명도 검토 대상에 함께 넣는다. 가설만 검토하면 "다르게 볼 수도 있다"가
            #   근거 없는 말로 채워져도 통과한다 — 그 한 줄이 카드를 가설로 남기는 장치라
            #   그것부터 검토를 받아야 한다.
            text = " / ".join(
                part
                for part in (
                    observation.title,
                    observation.description,
                    observation.hypothesis,
                    " · ".join(observation.alternative_explanations) or None,
                )
                if part
            )
            targets.append(
                {
                    "id": f"diary.observation.{index}",
                    "글": text,
                    "주장 세기": observation.insight_type,
                    "근거": diary_report_v2.evidence_texts_for_ids(
                        req, observation.evidence_refs
                    ),
                }
            )
        for index, question in enumerate(diary.caregiver_questions):
            targets.append(
                {
                    "id": f"diary.question.{index}",
                    "글": f"{question.question} / {question.purpose}".strip(" /"),
                    "근거": diary_report_v2.evidence_texts_for_ids(
                        req, question.evidence_refs
                    ),
                }
            )
        if diary.listening_tip:
            targets.append({"id": "diary.listeningTip", "글": diary.listening_tip})
    return targets


def _review_payload(
    result: contracts.ObservationGenerationResult,
    req: contracts.ObservationGenerationRequest,
    *,
    is_htp: bool,
    drawing_description: str | None = None,
) -> str:
    """검토 user 메시지. JSON 한 덩어리로 넘겨 id 대응이 어긋나지 않게 한다.

    가드레일: 여기 실리는 것은 **방금 생성 호출에 이미 나갔던 재료의 부분집합**이다(같은 GMS).
    새로운 노출면을 만들지 않는다 — 원본 이미지·음성·식별 정보는 애초에 계약에 없고,
    근거 식별자도 싣지 않는다(검토자는 참조 정합을 보지 않는다).
    ⚠️ 이 문자열은 로그로 남기지 않는다. 아이 발화 인용이 섞일 수 있다.
    """
    return json.dumps(
        {
            "관찰 사실": _review_facts(
                result,
                req,
                is_htp=is_htp,
                drawing_description=drawing_description,
            ),
            "검토 대상": _review_targets(result, req, is_htp=is_htp),
        },
        ensure_ascii=False,
    )


def _parse_findings(
    data: dict,
    known_ids: set[str],
    *,
    allowed_issues: frozenset[str] = _REVIEW_ISSUES,
) -> list[tuple[str, str]]:
    """검토 응답 → [(target, issue)]. 모르는 id·모르는 issue 는 버린다.

    ⚠️ note 는 읽지 않는다 — 아이 표현이 섞일 수 있어 결과에도 로그에도 남기지 않는다.
    """
    findings: list[tuple[str, str]] = []
    for raw in data.get("findings") or []:
        if not isinstance(raw, dict):
            continue
        target = str(raw.get("target", "")).strip()
        issue = str(raw.get("issue", "")).strip().upper()
        if target in known_ids and issue in allowed_issues:
            findings.append((target, issue))
    return findings


def _apply_findings(
    result: contracts.ObservationGenerationResult,
    findings: list[tuple[str, str]],
    *,
    is_htp: bool,
) -> bool:
    """지적을 결과에 반영하고 '리포트를 열어도 되는가'를 돌려준다.

    가능한 한 **항목 단위로 담아낸다**. 질문·안내·관찰 카드 하나가 부적절하다고 리포트
    전체를 가리는 것은 보호자에게 남은 근거 있는 내용을 함께 잃게 만든다.

    - 관찰 카드(feature) → EXPERT_ONLY 로 강등.
    - 경향 카드(card) → 제외하고 근거/참조를 재매핑.
    - 주제별 관찰·활동 기록·질문·가이드 → 해당 항목만 제외.
    - diary observation/question → 해당 항목만 제외.
    - diary story/flow/listeningTip → 구조화 V2 전체를 제외하고 레거시 리포트는 유지.
    - 그 밖의 핵심 요약 문장 → 안전하게 비우거나 다시 쓸 계약이 없어 전체를 AI_DRAFT로 남김.
    """
    flagged = {target for target, _ in findings}
    blocking = False

    for index, feature in enumerate(result.observation_draft.features):
        if f"{_FEATURE_TARGET_PREFIX}{index}" in flagged:
            feature.visibility_scope = "EXPERT_ONLY"

    kept_positions = [
        index
        for index in range(len(result.public_interpretations))
        if f"{_CARD_TARGET_PREFIX}{index}" not in flagged
    ]
    kept_cards = [result.public_interpretations[index] for index in kept_positions]
    result.public_interpretations = kept_cards
    referenced = {ref for card in kept_cards for ref in card.evidence_refs}
    result.evidence_items = [
        item for item in result.evidence_items if item.evidence_id in referenced
    ]

    new_index_of = {old: new for new, old in enumerate(kept_positions)}
    for subject_index, report in enumerate(result.subject_reports):
        report.interpretation_refs = [
            new_index_of[ref] for ref in report.interpretation_refs if ref in new_index_of
        ]
        report.vision_observations = [
            text
            for text_index, text in enumerate(report.vision_observations)
            if f"{_SUBJECT_TARGET_PREFIX}{subject_index}.{text_index}" not in flagged
        ]

    if is_htp:
        for target in flagged:
            if not target.startswith(
                (_FEATURE_TARGET_PREFIX, _CARD_TARGET_PREFIX, _SUBJECT_TARGET_PREFIX)
            ):
                blocking = True
        return not blocking

    result.activity_notes = [
        text
        for index, text in enumerate(result.activity_notes)
        if f"activityNote.{index}" not in flagged
    ]
    result.follow_up_guides = [
        guide
        for index, guide in enumerate(result.follow_up_guides)
        if f"followUpGuide.{index}" not in flagged
    ]
    result.guardian_questions = [
        question
        for index, question in enumerate(result.guardian_questions)
        if f"guardianQuestion.{index}" not in flagged
    ]

    kept_parent_guides: list[contracts.ReportParentGuide] = []
    for guide_index, guide in enumerate(result.parent_guides):
        items = [
            text
            for item_index, text in enumerate(guide.items)
            if f"parentGuide.{guide_index}.{item_index}" not in flagged
        ]
        if items:
            guide.items = items
            kept_parent_guides.append(guide)
    result.parent_guides = kept_parent_guides

    diary = result.diary_insights
    if diary is not None:
        diary.session_observations = [
            observation
            for index, observation in enumerate(diary.session_observations)
            if f"diary.observation.{index}" not in flagged
        ]
        diary.caregiver_questions = [
            question
            for index, question in enumerate(diary.caregiver_questions)
            if f"diary.question.{index}" not in flagged
        ]
        # 걸린 항목만 뺀다 — 검토기는 문장을 고치지 않고 문제가 있는 항목만 지적한다.
        #   ⚠️ 구 코드는 listeningTip·flow 가 걸려도 V2 를 통째로 버렸다. 2026-08-07 실호출에서
        #      검토기가 **optional 한 줄인 listeningTip 하나만** GENERIC_GUIDANCE 로 걸었는데
        #      핵심 이야기·흐름 5단계·관찰 1개·질문 2개가 함께 사라졌다(3/3). V2 가 한 번도
        #      켜지지 않는 상태였고, 단위 테스트는 그 조합을 재지 않아 조용히 지나갔다.
        if "diary.listeningTip" in flagged:
            diary.listening_tip = None
        diary.narrative_flow = [
            step
            for index, step in enumerate(diary.narrative_flow)
            if f"diary.flow.{index}" not in flagged
        ]
        # 핵심 이야기는 다르다. 이야기가 현실 붕괴·시점 과장으로 걸리면 그 이야기를 나눠 적은
        #   흐름과 관찰도 같은 오염을 물려받는다 — 뼈대가 무너지면 통째로 접고 레거시로 간다.
        if "diary.story" in flagged:
            result.diary_insights = None
        elif not any(
            (
                diary.story_snapshot is not None,
                diary.narrative_flow,
                diary.session_observations,
                diary.caregiver_questions,
            )
        ):
            # 남은 것이 없으면 비운다 — 판단 기준은 build_diary_insights 와 같다.
            #   듣기 안내 한 줄만 남은 V2 화면은 레거시 화면보다 정보가 적다.
            result.diary_insights = None

    contained_prefixes = (
        _FEATURE_TARGET_PREFIX,
        _CARD_TARGET_PREFIX,
        _SUBJECT_TARGET_PREFIX,
        "activityNote.",
        "followUpGuide.",
        "guardianQuestion.",
        "parentGuide.",
        "diary.observation.",
        "diary.question.",
        "diary.flow.",
    )
    contained_exact = {"diary.story", "diary.listeningTip"}
    for target in flagged:
        if target in contained_exact or target.startswith(contained_prefixes):
            continue
        blocking = True
    return not blocking


def _self_review(
    result: contracts.ObservationGenerationResult,
    req: contracts.ObservationGenerationRequest,
    *,
    rule_flagged: bool,
    model: str,
    is_htp: bool,
    drawing_description: str | None = None,
) -> contracts.ObservationGenerationResult:
    """생성된 리포트를 스스로 검토해 status 를 정한다(2-pass).

    Args:
        result: 조립이 끝난 계약 결과(1층 규칙 필터는 이미 적용된 상태).
        rule_flagged: 1층 규칙 필터가 무언가를 걸렀는가. True 면 LLM 검토 결과와 무관하게
            통과시키지 않는다 — 이미 진단·낙인 표현이 있었다는 뜻이다.
        model: 검토에 쓸 모델. 생성과 같은 모델을 쓴다(같은 프롬프트 자산·같은 버전 태그).

    Returns:
        status 가 정해진 결과. 통과하면 AI_REVIEWED, 아니면 AI_DRAFT.
    """
    targets = _review_targets(result, req, is_htp=is_htp)
    if not targets:
        # 검토할 문장이 하나도 없다 = 열 것도 없다. 통과로 올리지 않는다.
        _SELF_REVIEW_COUNTER.labels(outcome="failed").inc()
        return result
    try:
        resp = get_client().chat.completions.create(
            model=model,
            messages=[
                {"role": "system", "content": _load(_review_prompt_name(is_htp))},
                {
                    "role": "user",
                    "content": _review_payload(
                        result,
                        req,
                        is_htp=is_htp,
                        drawing_description=drawing_description,
                    ),
                },
            ],
            temperature=0,  # 판정은 흔들리면 안 된다 — 생성(0.4)보다 낮춘다.
            response_format={"type": "json_object"},
            # 생성 + 검토 두 번이 BE read timeout(30s) 안에 끝나야 한다. 넘기면 생성까지 버려진다.
            timeout=config.REPORT_REVIEW_TIMEOUT_SEC,
        )
        data = _extract_json(resp.choices[0].message.content or "")
    except (OpenAIError, RuntimeError) as e:
        # ⚠️ 응답 본문은 로그로 남기지 않는다 — 에러 유형만. 검토 실패는 차단이 아니라 기능 저하다.
        logger.warning("리포트 자체검토 실패 — 미검토로 남김: %s", type(e).__name__)
        _SELF_REVIEW_COUNTER.labels(outcome="unavailable").inc()
        return result

    findings = _parse_findings(
        data,
        {t["id"] for t in targets},
        allowed_issues=(
            _LEGACY_REVIEW_ISSUES
            if is_htp
            else _LEGACY_REVIEW_ISSUES | _DIARY_REVIEW_ISSUES
        ),
    )
    passed = _apply_findings(result, findings, is_htp=is_htp)
    if findings:
        # 사유 코드만 남긴다 — 지적 문장·아이 발화는 담지 않는다.
        logger.info(
            "리포트 자체검토 지적 %d건: %s",
            len(findings),
            sorted({issue for _, issue in findings}),
        )
    if not passed or rule_flagged:
        _SELF_REVIEW_COUNTER.labels(outcome="failed").inc()
        return result
    _SELF_REVIEW_COUNTER.labels(outcome="contained" if findings else "passed").inc()
    result.observation_draft.status = REVIEW_STATUS_REVIEWED
    return result


def generate(
    req: contracts.ObservationGenerationRequest,
    *,
    drawing_description: str | None = None,
    behavior: contracts.BehaviorMetrics | None = None,
    model: str | None = None,
) -> contracts.ObservationGenerationResult:
    """[그림 관찰 서술] + [형식적 분석] + 활동 요청 → GMS LLM 관찰 리포트 초안(계약 결과).

    Args:
        req: 최종 분석 관찰 생성 요청(집계·감정·대표 발화).
        drawing_description: vlm_client.describe 산출물(그림 사실 묘사). 있으면 관찰 근거로
            쓰인다. None이면 그림 특징은 언급하지 않고 나머지 데이터만으로 생성한다.
        behavior: 소요시간·필압 등 형식적 지표(있으면 관찰 보조 근거로 반영). 생략하면
            req.behavior_metrics 를 쓴다 — 계약으로 들어온 값이 정상 경로이고, 이 인자는
            draft/스모크에서 계약 밖 값을 넣어 보기 위한 덮어쓰기다.
        model: 미지정 시 config.REPORT_LLM_MODEL(텍스트 전용 — 이미지 자체는 넘기지 않는다).
            리포트는 대화(config.LLM_MODEL)와 다른 모델을 쓴다 — 이유는 config 주석 참조.

    Returns:
        ObservationGenerationResult(BE 계약 형태, camelCase 직렬화).

    Raises:
        RuntimeError: GMS 호출 실패 또는 응답 JSON 파싱 실패 시(내용은 감추고 유형만 로그).
    """
    # 리포트 전용 모델(S15P11B209-972). 자체검토(_self_review)도 같은 모델로 돈다 —
    # 생성과 판정이 다른 모델이면 "같은 버전 태그인데 열리는 기준이 다른" 상태가 된다.
    used_model = model or config.REPORT_LLM_MODEL
    # 계약 값(836)이 기본. 인자로 준 값이 있으면 그쪽이 이긴다(draft/스모크 덮어쓰기).
    behavior = behavior if behavior is not None else req.behavior_metrics
    is_htp = _is_htp(req)
    # RAG 근거 검색(614)은 HTP 리포트에서만 한다 — 그림일기 프롬프트는 [전문 자료 근거]를
    # 근거 목록에 두지 않으므로, 검색해 봐야 프롬프트가 쓰지 않는 블록에 비용만 쓴다.
    # 실패해도 리포트는 생성한다(기능 저하, 차단 아님). 사유(615)는 응답·메트릭으로만 남긴다.
    if is_htp:
        rag_chunks, rag_skipped_reason = _search_rag(req, drawing_description)
    else:
        _RAG_SEARCH_COUNTER.labels(outcome="not_applicable").inc()
        rag_chunks, rag_skipped_reason = [], RAG_NOT_APPLICABLE
    messages = [
        {"role": "system", "content": _system_prompt(is_htp)},
        {
            "role": "user",
            "content": _format_activity(req, drawing_description, behavior, rag_chunks),
        },
    ]
    try:
        resp = get_client().chat.completions.create(
            model=used_model,
            messages=messages,
            temperature=0.4,  # 관찰 기록은 튀지 않게 다소 낮게.
            response_format={"type": "json_object"},
        )
    except OpenAIError as e:
        # ⚠️ 요청 내용(대표 발화 등)은 로그에 남기지 않는다 — 에러 유형만.
        logger.error("GMS 리포트 생성 호출 실패: %s", type(e).__name__)
        raise RuntimeError("리포트 생성에 실패했어요(GMS).") from e

    data = _extract_json(resp.choices[0].message.content or "")
    # 재현성: GMS가 실제 서빙한 모델 ID를 기록한다(예: gpt-4o-mini-2024-07-18). 없으면 요청 모델명.
    served_model = getattr(resp, "model", "") or used_model
    result, rule_flagged = _assemble(
        req, data, served_model, rag_chunks, rag_skipped_reason, is_htp
    )
    # 2차 패스: 스스로 검토해 보호자에게 열지 말지를 정한다. 실패해도 리포트는 그대로 나간다
    # (status 가 AI_DRAFT 로 남아 관찰 카드가 보호자에게 열리지 않을 뿐이다).
    return _self_review(
        result,
        req,
        rule_flagged=rule_flagged,
        model=used_model,
        is_htp=is_htp,
        drawing_description=drawing_description,
    )


if __name__ == "__main__":
    # 스모크 테스트:  cd ai && python report_client.py  (GMS 키 필요)
    logging.basicConfig(level=logging.INFO)
    sample = contracts.ObservationGenerationRequest(
        request_id="smoke-1",
        analysis_id=1,
        drawing_session_id=1,
        analysis_type="FINAL",
        question_difficulty="PRESCHOOL",
        question_count=5,
        answered_count=4,
        skipped_count=1,
        unrecognized_speech_count=0,
        selected_emotions=["JOY"],
        expressed_emotion_text=None,
        representative_utterance="이건 우리 집이야. 엄마랑 나 있어.",
    )
    sample_description = "가운데에 집이 크게 그려져 있고, 왼쪽에 나무 한 그루가 있어요. 오른쪽에는 사람 두 명이 나란히 서 있어요."
    sample_behavior = contracts.BehaviorMetrics(
        drawing_duration_ms=600_000,  # 총 10분
        active_drawing_ms=410_000,  # 실제 그린 시간 약 6.8분
        pause_count=4,
        erase_count=3,
        undo_count=2,
        pressure_available=True,
        # BE는 이번 단계에서 항상 None을 보낸다 — 스모크에서만 값을 넣어 표기를 확인한다.
        average_pressure=0.62,
    )
    result = generate(
        sample, drawing_description=sample_description, behavior=sample_behavior
    )
    print(result.model_dump_json(by_alias=True, indent=2))
