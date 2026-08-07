"""GMS STT 클라이언트 — whisper-1로 음성 파일→텍스트.

가드레일: 인식된 텍스트(아이 발화일 수 있음)와 키는 로그로 남기지 않는다(에러 유형·판정 사유만).

무음·저신뢰 처리(2026-08-05): 예전에는 whisper 응답 텍스트를 그대로 돌려줘, 아이가
아무 말도 하지 않은 녹음에서 나온 학습 데이터 정형구가 아이 답변으로 저장됐다.
이제 `verbose_json`으로 세그먼트 지표(`no_speech_prob`·`avg_logprob`)를 함께 받아
`stt_verdict`가 상태를 정하고, 실패면 텍스트를 비운다(정본 §19.6·§25).
"""

from __future__ import annotations

import logging
from dataclasses import dataclass

from openai import APITimeoutError, BadRequestError, OpenAIError

import config
import stt_verdict
from gms import get_client

logger = logging.getLogger(__name__)

# whisper `prompt`(initial prompt) — 디코딩 문맥을 미리 정해 유튜브 상용구로 흐르는 걸 막는다.
#   2026-08-07 실측에서 무음 녹음이 "자막제작 by UpTitle …"·"유료광고를 포함하고 있습니다"로
#   나왔다. whisper는 앞 문맥이 비면 학습 분포에서 가장 흔한 자막체로 떨어지므로, 짧은
#   한국어 대화라는 문맥을 먼저 깔아 그 경로를 막는다. temperature=0은 폴백 샘플링을 꺼
#   같은 오디오가 실행마다 다른 문장을 내지 않게 한다(캘리브레이션 재현성).
#   ⚠️ 이 문장에 아이 이름·질문 내용 같은 실데이터를 넣지 않는다 — 모델이 프롬프트 단어를
#   그대로 받아쓰는 사례가 있어, 넣는 순간 하지 않은 말이 답변으로 저장될 수 있다.
_DECODE_PROMPT = "아이가 그림을 그리면서 나눈 대화의 한 마디예요."


@dataclass(frozen=True)
class Transcription:
    """STT 결과. 실패면 `text`는 빈 문자열이다(추측 문장을 만들지 않는다)."""

    text: str
    status: str
    failure_reason: str | None = None
    needs_confirmation: bool = False

    @property
    def failed(self) -> bool:
        return self.status == stt_verdict.STATUS_FAILED


def transcribe_detailed(audio_path: str, *, language: str = "ko") -> Transcription:
    """음성 파일을 텍스트로 변환하고 무음·저신뢰를 실패로 판정한다.

    Args:
        audio_path: 음성 파일 경로(mp3/wav/m4a 등).
        language: 인식 언어 힌트. 기본 한국어("ko").

    Returns:
        상태·실패 사유가 붙은 인식 결과. 실패해도 예외가 아니라 값으로 돌려준다 —
        무음은 장애가 아니라 정상적인 결과이고, BE는 이 둘을 다르게 처리해야 한다.

    Raises:
        RuntimeError: GMS 호출이 상류 장애로 실패한 경우(BE는 502로 받는다).
    """
    text, segments = _request(audio_path, language)
    metrics = stt_verdict.weighted_metrics(segments)
    verdict = stt_verdict.judge(
        text,
        metrics,
        no_speech_prob_max=config.STT_NO_SPEECH_PROB_MAX,
        avg_logprob_fail_max=config.STT_AVG_LOGPROB_FAIL_MAX,
        avg_logprob_confirm_max=config.STT_AVG_LOGPROB_CONFIRM_MAX,
    )
    if verdict.failed:
        # 사유·지표만 남긴다(텍스트 금지). 지표가 없으면 평문 폴백이었다는 뜻이다.
        logger.info(
            "STT 실패 판정 reason=%s segments=%d noSpeechProb=%s avgLogprob=%s",
            verdict.failure_reason,
            metrics.segment_count,
            _format(metrics.no_speech_prob),
            _format(metrics.avg_logprob),
        )
        return Transcription("", verdict.status, verdict.failure_reason, False)
    # 성공도 남긴다. 실패만 로그하면 임계값을 조정할 근거가 한쪽만 쌓인다 — 2026-08-07
    #   확인 필요 과탐(11건 중 8건)을 실측하고도 플래그된 건들의 avg_logprob 분포를
    #   몰라 완화 폭을 추정으로 정해야 했다. 여기 남는 값이 다음 캘리브레이션 재료다.
    #   ⚠️ 인식 텍스트는 넣지 않는다(파일 상단 가드레일) — 아이 발화일 수 있다.
    logger.info(
        "STT 판정 status=%s needsConfirmation=%s segments=%d noSpeechProb=%s avgLogprob=%s",
        verdict.status,
        verdict.needs_confirmation,
        metrics.segment_count,
        _format(metrics.no_speech_prob),
        _format(metrics.avg_logprob),
    )
    return Transcription(
        text.strip(), verdict.status, None, verdict.needs_confirmation
    )


def transcribe(audio_path: str, *, language: str = "ko") -> str:
    """예전 문자열 반환 형태. 실패는 빈 문자열이 된다.

    새 호출부는 상태를 함께 봐야 하므로 [transcribe_detailed]를 쓴다. 이 함수는
    스모크 테스트와 외부 스크립트 호환을 위해 남긴다.
    """
    return transcribe_detailed(audio_path, language=language).text


def _request(audio_path: str, language: str) -> tuple[str, list[dict]]:
    """verbose_json으로 먼저 요청하고, 게이트웨이가 거절하면 평문으로 한 번 되돌아간다.

    reason: `verbose_json`은 whisper-1이 지원하는 형식이지만 우리는 GMS 게이트웨이를
    통해 호출한다. 게이트웨이가 형식을 거절할 때 STT 전체가 실패하면, 무음 판정을
    붙이려다 정상 음성 인식까지 잃는다. 폴백에서는 지표가 없어 텍스트 규칙만 남는다.

    ⚠️ 폴백은 **bare 호출**이어야 한다(model·file·language만). 첫 호출에는
    response_format 말고도 prompt·temperature가 실려 있고, 게이트웨이가 그중
    무엇을 거절하든 똑같이 400으로 온다. 폴백에서 거절당한 파라미터를 그대로
    다시 보내면 두 번째도 400이 되어 STT 전체가 UNSUPPORTED_AUDIO로 죽는다 —
    오디오는 멀쩡한데 파라미터 때문에 아이 답변을 잃는 실패다.
    """
    try:
        response = _call(audio_path, language, verbose=True)
        return _text_of(response), _segments_of(response)
    except BadRequestError:
        logger.warning("STT verbose_json 거절 — 평문 응답으로 재시도한다")
    except APITimeoutError as e:
        raise _timeout_error() from e
    except OpenAIError as e:
        logger.error("GMS STT 호출 실패: %s", type(e).__name__)
        raise RuntimeError("음성 인식에 실패했어요(GMS).") from e

    try:
        response = _call(audio_path, language, verbose=False)
        return _text_of(response), []
    except BadRequestError as e:
        # 두 형식 모두 400이면 형식 문제가 아니라 오디오 문제로 본다(정본 §19.6).
        raise _unsupported_audio_error() from e
    except APITimeoutError as e:
        raise _timeout_error() from e
    except OpenAIError as e:
        logger.error("GMS STT 호출 실패: %s", type(e).__name__)
        raise RuntimeError("음성 인식에 실패했어요(GMS).") from e


def _call(audio_path: str, language: str, *, verbose: bool):
    """`verbose=False`는 게이트웨이가 확실히 받는 최소 호출이다(폴백 전용).

    선택 파라미터를 전부 `verbose` 하나에 묶어 둔 건 의도다 — 폴백이 bare로 남는 것이
    분기가 아니라 구조로 보장돼야 한다(위 `_request` 주석).
    """
    with open(audio_path, "rb") as f:
        kwargs = {
            "model": config.STT_MODEL,
            "file": f,
            "language": language,
        }
        if verbose:
            kwargs["response_format"] = "verbose_json"
            kwargs["temperature"] = 0
            kwargs["prompt"] = _DECODE_PROMPT
        return get_client().audio.transcriptions.create(**kwargs)


def _text_of(response: object) -> str:
    return getattr(response, "text", "") or ""


def _segments_of(response: object) -> list[dict]:
    """세그먼트를 dict 목록으로 정규화한다(SDK가 객체·dict 어느 쪽을 주든)."""
    segments = getattr(response, "segments", None) or []
    normalized: list[dict] = []
    for segment in segments:
        if isinstance(segment, dict):
            normalized.append(segment)
            continue
        normalized.append(
            {
                key: getattr(segment, key, None)
                for key in ("start", "end", "no_speech_prob", "avg_logprob")
            }
        )
    return normalized


class SttAudioError(RuntimeError):
    """오디오 자체 문제로 인식할 수 없는 경우. `failure_reason`을 함께 나른다."""

    def __init__(self, failure_reason: str, message: str) -> None:
        super().__init__(message)
        self.failure_reason = failure_reason


def _unsupported_audio_error() -> SttAudioError:
    return SttAudioError(stt_verdict.UNSUPPORTED_AUDIO, "지원하지 않는 음성 형식이에요.")


def _timeout_error() -> SttAudioError:
    return SttAudioError(stt_verdict.TIMEOUT, "음성 인식이 시간 안에 끝나지 않았어요.")


def _format(value: float | None) -> str:
    return "none" if value is None else f"{value:.3f}"


if __name__ == "__main__":
    # 스모크 테스트:  cd ai && python stt_client.py <음성파일>
    #   팁: tts_client.py로 만든 out.mp3를 넣으면 TTS→STT 왕복 확인이 된다.
    import sys

    logging.basicConfig(level=logging.INFO)
    if len(sys.argv) < 2:
        print("사용법: python stt_client.py <음성파일(mp3/wav/m4a)>")
        raise SystemExit(1)
    result = transcribe_detailed(sys.argv[1])
    print(f"status={result.status} reason={result.failure_reason} confirm={result.needs_confirmation}")
    print(result.text)
