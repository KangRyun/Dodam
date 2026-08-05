"""STT 클라이언트 테스트 — verbose_json 요청·폴백·실패 사유 매핑.

GMS를 부르지 않는다. `stt_client.get_client`를 가짜 클라이언트로 바꿔 호출 인자와
분기만 검증한다(아동 음성·키를 쓰지 않는다).
"""

from __future__ import annotations

import httpx
import pytest
from openai import APITimeoutError, BadRequestError, InternalServerError

import stt_client
import stt_verdict


class _Segment:
    """SDK가 dict가 아니라 객체를 주는 경우를 재현한다."""

    def __init__(self, start, end, no_speech_prob, avg_logprob):
        self.start = start
        self.end = end
        self.no_speech_prob = no_speech_prob
        self.avg_logprob = avg_logprob


class _Response:
    def __init__(self, text, segments=None):
        self.text = text
        if segments is not None:
            self.segments = segments


class _FakeTranscriptions:
    def __init__(self, outcomes):
        self._outcomes = list(outcomes)
        self.calls = []

    def create(self, **kwargs):
        self.calls.append(kwargs)
        outcome = self._outcomes.pop(0)
        if isinstance(outcome, Exception):
            raise outcome
        return outcome


class _FakeClient:
    def __init__(self, outcomes):
        self.audio = type("_Audio", (), {})()
        self.audio.transcriptions = _FakeTranscriptions(outcomes)


def _bad_request():
    request = httpx.Request("POST", "https://gms.invalid/audio/transcriptions")
    response = httpx.Response(400, request=request, json={"error": {"message": "x"}})
    return BadRequestError("bad request", response=response, body=None)


def _server_error():
    request = httpx.Request("POST", "https://gms.invalid/audio/transcriptions")
    response = httpx.Response(500, request=request, json={"error": {"message": "x"}})
    return InternalServerError("boom", response=response, body=None)


@pytest.fixture
def audio_file(tmp_path):
    path = tmp_path / "answer.m4a"
    path.write_bytes(b"\x00\x01\x02")
    return str(path)


def _install(monkeypatch, outcomes):
    client = _FakeClient(outcomes)
    monkeypatch.setattr(stt_client, "get_client", lambda: client)
    return client


class TestVerboseRequest:
    def test_verbose_json으로_먼저_요청한다(self, monkeypatch, audio_file):
        client = _install(monkeypatch, [_Response("이건 우리 집이야", segments=[])])
        stt_client.transcribe_detailed(audio_file)
        call = client.audio.transcriptions.calls[0]
        assert call["response_format"] == "verbose_json"
        assert call["language"] == "ko"

    def test_세그먼트_객체에서_지표를_읽어_무음을_판정한다(self, monkeypatch, audio_file):
        segments = [_Segment(0.0, 2.0, 0.95, -0.3)]
        _install(monkeypatch, [_Response("구독, 좋아요", segments=segments)])
        result = stt_client.transcribe_detailed(audio_file)
        assert result.failed
        assert result.failure_reason == stt_verdict.NO_SPEECH
        assert result.text == ""

    def test_성공이면_텍스트를_다듬어_돌려준다(self, monkeypatch, audio_file):
        segments = [_Segment(0.0, 3.0, 0.02, -0.15)]
        _install(monkeypatch, [_Response("  이건 우리 집이야  ", segments=segments)])
        result = stt_client.transcribe_detailed(audio_file)
        assert result.status == stt_verdict.STATUS_SUCCESS
        assert result.text == "이건 우리 집이야"
        assert result.needs_confirmation is False

    def test_확인구간이면_needs_confirmation이_참(self, monkeypatch, audio_file):
        segments = [_Segment(0.0, 3.0, 0.05, -0.75)]
        _install(monkeypatch, [_Response("친구랑 놀았어", segments=segments)])
        assert stt_client.transcribe_detailed(audio_file).needs_confirmation is True


class TestFallback:
    def test_verbose가_400이면_평문으로_한_번_되돌아간다(self, monkeypatch, audio_file):
        client = _install(monkeypatch, [_bad_request(), _Response("이건 나무야")])
        result = stt_client.transcribe_detailed(audio_file)
        assert result.status == stt_verdict.STATUS_SUCCESS
        assert result.text == "이건 나무야"
        calls = client.audio.transcriptions.calls
        assert len(calls) == 2
        assert "response_format" not in calls[1]

    def test_평문_폴백에서도_자막_정형구는_걸러진다(self, monkeypatch, audio_file):
        _install(monkeypatch, [_bad_request(), _Response("구독, 좋아요, 알림설정 부탁드립니다.")])
        result = stt_client.transcribe_detailed(audio_file)
        assert result.failure_reason == stt_verdict.NO_SPEECH

    def test_두_형식_모두_400이면_지원하지_않는_오디오(self, monkeypatch, audio_file):
        _install(monkeypatch, [_bad_request(), _bad_request()])
        with pytest.raises(stt_client.SttAudioError) as error:
            stt_client.transcribe_detailed(audio_file)
        assert error.value.failure_reason == stt_verdict.UNSUPPORTED_AUDIO


class TestErrorMapping:
    def test_타임아웃은_TIMEOUT_사유로_올린다(self, monkeypatch, audio_file):
        request = httpx.Request("POST", "https://gms.invalid/audio/transcriptions")
        _install(monkeypatch, [APITimeoutError(request=request)])
        with pytest.raises(stt_client.SttAudioError) as error:
            stt_client.transcribe_detailed(audio_file)
        assert error.value.failure_reason == stt_verdict.TIMEOUT

    def test_그_외_GMS_오류는_상류_장애로_올린다(self, monkeypatch, audio_file):
        _install(monkeypatch, [_server_error()])
        with pytest.raises(RuntimeError) as error:
            stt_client.transcribe_detailed(audio_file)
        assert not isinstance(error.value, stt_client.SttAudioError)

    def test_상류_장애_메시지에_인식_텍스트를_담지_않는다(self, monkeypatch, audio_file):
        _install(monkeypatch, [_server_error()])
        with pytest.raises(RuntimeError) as error:
            stt_client.transcribe_detailed(audio_file)
        assert "음성 인식에 실패했어요(GMS)." == str(error.value)


class TestLegacyStringApi:
    def test_기존_문자열_API는_실패를_빈_문자열로_준다(self, monkeypatch, audio_file):
        segments = [_Segment(0.0, 1.0, 0.99, -0.2)]
        _install(monkeypatch, [_Response("구독, 좋아요", segments=segments)])
        assert stt_client.transcribe(audio_file) == ""

    def test_기존_문자열_API는_성공_텍스트를_그대로_준다(self, monkeypatch, audio_file):
        _install(monkeypatch, [_Response("이건 우리 집이야", segments=[])])
        assert stt_client.transcribe(audio_file) == "이건 우리 집이야"
