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
    with open(audio_path, "rb") as f:
        kwargs = {
            "model": config.STT_MODEL,
            "file": f,
            "language": language,
        }
        if verbose:
            kwargs["response_format"] = "verbose_json"
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
