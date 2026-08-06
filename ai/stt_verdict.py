"""STT 결과 판정 — 무음·저신뢰·환각 정형구를 '추측 문장' 대신 실패로 돌린다.

정본 `docs/api/API_명세서_최종.md` §19.6:
    인식 실패는 추측 문장을 만들지 않고 status=FAILED,
    failureReason=NO_SPEECH|LOW_CONFIDENCE|UNSUPPORTED_AUDIO|TIMEOUT 을 반환한다.
정본 §25 계약 테스트: "STT low confidence → 추정 텍스트 확정 금지, 폴백 선택지 제공".

왜 필요한가(2026-08-05 실측): 아이가 아무 말도 안 한 녹음이 whisper-1을 타면
"구독, 좋아요, 알림설정 부탁드립니다." 같은 학습 데이터 정형구가 나오고, 그것이
아이 답변으로 저장돼 다음 질문의 근거가 됐다. 무음을 무음이라고 말하지 않으면
아이가 하지 않은 말이 기록에 남는다.

이 모듈은 외부 의존이 없다(openai·pydantic 미사용) — GMS 키 없이도 판정 규칙만
단독으로 테스트할 수 있게 하려는 의도적 분리다. 실제 호출은 stt_client가 한다.

가드레일: 이 모듈은 인식 텍스트를 로그로 남기지 않는다. 판정 사유만 돌려준다.
"""

from __future__ import annotations

import unicodedata
from dataclasses import dataclass

# ── 실패 사유 (정본 §19.6 어휘) ──────────────────────────────────
NO_SPEECH = "NO_SPEECH"
LOW_CONFIDENCE = "LOW_CONFIDENCE"
UNSUPPORTED_AUDIO = "UNSUPPORTED_AUDIO"
TIMEOUT = "TIMEOUT"

STATUS_SUCCESS = "SUCCESS"
STATUS_FAILED = "FAILED"

# whisper가 무음·잡음 구간에서 되풀이하는 학습 데이터 정형구(유튜브 자막 흔적).
#   전체 발화가 이 문구 하나와 **같을 때에만** 무음으로 본다 — 부분 일치로 판정하면
#   아이가 실제로 그 단어를 말한 것까지 지운다.
#   비교는 공백·문장부호를 제거한 문자열로 한다("구독 좋아요" / "구독,좋아요" 동일 취급).
#
#   ⚠️ 짧은 대답("네", "음", "안녕하세요", "감사합니다")은 여기에 넣지 않는다.
#   whisper가 무음에 그런 값을 붙이기도 하지만 아이가 실제로 그렇게 답하는 일이 훨씬
#   흔하다. 목록으로 지우면 진짜 답변을 삭제한다 — 그 경우는 no_speech_prob·avg_logprob
#   지표로 걸러야 하고, 지표가 없으면(평문 폴백) 통과시키는 쪽이 옳다.
_FILLER_PHRASES = (
    "구독좋아요알림설정부탁드립니다",
    "구독과좋아요알림설정부탁드립니다",
    "구독좋아요알림설정부탁드려요",
    "구독좋아요알림설정",
    "구독과좋아요알림설정",
    "시청해주셔서감사합니다",
    "끝까지시청해주셔서감사합니다",
    "영상시청해주셔서감사합니다",
    "다음영상에서만나요",
    "다음영상에서뵙겠습니다",
    "한글자막by",
    "자막제공",
    "이번영상은여기까지입니다",
    "오늘영상은여기까지입니다",
)


@dataclass(frozen=True)
class SpeechMetrics:
    """whisper `verbose_json` 세그먼트에서 뽑은 판정 근거.

    두 값 모두 `None`일 수 있다 — GMS가 `verbose_json`을 거절해 평문 응답으로
    되돌아간 경우다. 그때는 텍스트 기반 규칙만 적용한다(근거 없는 실패 판정 금지).
    """

    no_speech_prob: float | None = None
    avg_logprob: float | None = None
    segment_count: int = 0
    audio_duration_sec: float | None = None


@dataclass(frozen=True)
class Verdict:
    """판정 결과. 실패면 `text`는 호출부에서 빈 문자열로 비운다."""

    status: str
    failure_reason: str | None
    needs_confirmation: bool

    @property
    def failed(self) -> bool:
        return self.status == STATUS_FAILED


def normalize_for_filler_match(text: str) -> str:
    """공백·문장부호·호환문자를 지운 비교용 문자열을 만든다."""
    normalized = unicodedata.normalize("NFKC", text)
    return "".join(
        ch for ch in normalized if not ch.isspace() and (ch.isalnum() or ch == "_")
    ).lower()


def is_filler_only(text: str) -> bool:
    """전체 발화가 whisper 정형구 하나와 같은지 본다(부분 일치는 판정하지 않는다)."""
    normalized = normalize_for_filler_match(text)
    if not normalized:
        return True
    return normalized in _FILLER_PHRASES


def judge(
    text: str,
    metrics: SpeechMetrics,
    *,
    no_speech_prob_max: float,
    avg_logprob_fail_max: float,
    avg_logprob_confirm_max: float,
) -> Verdict:
    """인식 텍스트와 세그먼트 지표로 상태를 정한다.

    Args:
        text: whisper가 돌려준 원문(비어 있을 수 있다).
        metrics: 세그먼트 지표. 값이 없으면 텍스트 규칙만 쓴다.
        no_speech_prob_max: 이 값 이상이면 무음으로 본다.
        avg_logprob_fail_max: 이 값 미만이면 저신뢰 실패로 본다.
        avg_logprob_confirm_max: 이 값 미만이면 통과시키되 보호자 확인을 요구한다.

    Returns:
        상태·실패 사유·보호자 확인 필요 여부.

    판정 순서에는 이유가 있다. 무음을 먼저 걸러야 한다 — 무음 구간의 신뢰도는
    '무엇을 잘못 들었는지'를 말해줄 뿐이고, 애초에 들을 말이 없었다는 사실이
    더 강한 근거다. 저신뢰보다 무음이 아이에게 보여줄 안내(선택지)도 정확하다.
    """
    stripped = (text or "").strip()
    if not stripped:
        return Verdict(STATUS_FAILED, NO_SPEECH, False)

    if metrics.no_speech_prob is not None and metrics.no_speech_prob >= no_speech_prob_max:
        # 진짜 발화가 잡음에 묻혀 함께 버려질 수 있다. 그 경우 아이는 선택지를 받아
        # 대화를 이어가고, 하지 않은 말이 기록되는 일은 없다 — 뒤집으면 반대가 된다.
        return Verdict(STATUS_FAILED, NO_SPEECH, False)

    if is_filler_only(stripped):
        return Verdict(STATUS_FAILED, NO_SPEECH, False)

    if metrics.avg_logprob is not None:
        if metrics.avg_logprob < avg_logprob_fail_max:
            return Verdict(STATUS_FAILED, LOW_CONFIDENCE, False)
        if metrics.avg_logprob < avg_logprob_confirm_max:
            # 확정하지 않고 보호자 확인 대상으로 넘긴다(정본 §25).
            return Verdict(STATUS_SUCCESS, None, True)

    return Verdict(STATUS_SUCCESS, None, False)


def weighted_metrics(segments: list[dict]) -> SpeechMetrics:
    """세그먼트 목록을 하나의 지표로 접는다.

    길이 가중 평균을 쓴다 — 0.2초 잡음 세그먼트와 4초 발화 세그먼트를 같은 무게로
    평균하면 짧은 잡음이 판정을 끌고 간다. 길이를 알 수 없으면 균등 평균으로 떨어진다.
    """
    if not segments:
        return SpeechMetrics()

    total_weight = 0.0
    no_speech_sum = 0.0
    logprob_sum = 0.0
    no_speech_weight = 0.0
    logprob_weight = 0.0
    duration_end = 0.0

    for segment in segments:
        start = _as_float(segment.get("start"))
        end = _as_float(segment.get("end"))
        weight = 1.0
        if start is not None and end is not None and end > start:
            weight = end - start
            duration_end = max(duration_end, end)
        total_weight += weight

        no_speech = _as_float(segment.get("no_speech_prob"))
        if no_speech is not None:
            no_speech_sum += no_speech * weight
            no_speech_weight += weight

        avg_logprob = _as_float(segment.get("avg_logprob"))
        if avg_logprob is not None:
            logprob_sum += avg_logprob * weight
            logprob_weight += weight

    return SpeechMetrics(
        no_speech_prob=(no_speech_sum / no_speech_weight) if no_speech_weight else None,
        avg_logprob=(logprob_sum / logprob_weight) if logprob_weight else None,
        segment_count=len(segments),
        audio_duration_sec=duration_end or None,
    )


def _as_float(value: object) -> float | None:
    if isinstance(value, bool) or value is None:
        return None
    if isinstance(value, (int, float)):
        return float(value)
    return None
