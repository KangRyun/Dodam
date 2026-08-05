"""STT 무음·저신뢰 판정 규칙 테스트.

이 모듈은 외부 의존이 없어 GMS 키·openai 패키지 없이도 돌린다(stt_verdict 분리 이유).

실측 기준선(2026-08-05, 에뮬레이터 session 3514 / conversation 337): 아이가 아무 말도
하지 않은 녹음이 "구독, 좋아요, 알림설정 부탁드립니다."로 저장되고 다음 질문의 근거가 됐다.
"""

from __future__ import annotations

import stt_verdict

NO_SPEECH_MAX = 0.6
FAIL_MAX = -1.0
CONFIRM_MAX = -0.6


def judge(text, metrics=None):
    return stt_verdict.judge(
        text,
        metrics or stt_verdict.SpeechMetrics(),
        no_speech_prob_max=NO_SPEECH_MAX,
        avg_logprob_fail_max=FAIL_MAX,
        avg_logprob_confirm_max=CONFIRM_MAX,
    )


class TestBlankText:
    def test_빈_문자열은_무음_실패(self):
        verdict = judge("")
        assert verdict.status == stt_verdict.STATUS_FAILED
        assert verdict.failure_reason == stt_verdict.NO_SPEECH

    def test_공백만_있어도_무음_실패(self):
        assert judge("   \n\t ").failure_reason == stt_verdict.NO_SPEECH

    def test_None_도_무음_실패(self):
        assert judge(None).failure_reason == stt_verdict.NO_SPEECH


class TestNoSpeechProb:
    def test_무음확률_임계_이상이면_텍스트가_있어도_실패(self):
        # 실측 사례: 무음 녹음인데 whisper가 문장을 만들어냈다.
        metrics = stt_verdict.SpeechMetrics(no_speech_prob=0.91, avg_logprob=-0.2)
        verdict = judge("구독, 좋아요, 알림설정 부탁드립니다.", metrics)
        assert verdict.status == stt_verdict.STATUS_FAILED
        assert verdict.failure_reason == stt_verdict.NO_SPEECH

    def test_임계값_경계는_실패쪽(self):
        metrics = stt_verdict.SpeechMetrics(no_speech_prob=NO_SPEECH_MAX)
        assert judge("이건 우리 집이야", metrics).failed

    def test_임계값_바로_아래는_통과(self):
        metrics = stt_verdict.SpeechMetrics(no_speech_prob=NO_SPEECH_MAX - 0.01, avg_logprob=-0.1)
        verdict = judge("이건 우리 집이야", metrics)
        assert verdict.status == stt_verdict.STATUS_SUCCESS
        assert verdict.failure_reason is None

    def test_무음확률이_저신뢰보다_먼저_판정된다(self):
        # 둘 다 걸릴 때 사유는 NO_SPEECH — 아이에게 보여줄 안내가 그쪽이 정확하다.
        metrics = stt_verdict.SpeechMetrics(no_speech_prob=0.8, avg_logprob=-2.5)
        assert judge("무엇인가", metrics).failure_reason == stt_verdict.NO_SPEECH


class TestLowConfidence:
    def test_평균로그확률이_하한_미만이면_실패(self):
        metrics = stt_verdict.SpeechMetrics(no_speech_prob=0.1, avg_logprob=-1.4)
        verdict = judge("웅얼웅얼", metrics)
        assert verdict.status == stt_verdict.STATUS_FAILED
        assert verdict.failure_reason == stt_verdict.LOW_CONFIDENCE

    def test_경계_이상이면_실패가_아니다(self):
        metrics = stt_verdict.SpeechMetrics(no_speech_prob=0.1, avg_logprob=FAIL_MAX)
        assert not judge("웅얼웅얼", metrics).failed

    def test_확인구간은_통과하되_보호자확인을_요구한다(self):
        metrics = stt_verdict.SpeechMetrics(no_speech_prob=0.1, avg_logprob=-0.8)
        verdict = judge("친구랑 놀았어", metrics)
        assert verdict.status == stt_verdict.STATUS_SUCCESS
        assert verdict.needs_confirmation is True

    def test_신뢰도가_충분하면_확인이_필요없다(self):
        metrics = stt_verdict.SpeechMetrics(no_speech_prob=0.05, avg_logprob=-0.2)
        assert judge("친구랑 놀았어", metrics).needs_confirmation is False


class TestFillerPhrases:
    def test_자막_정형구만_있으면_지표가_없어도_무음(self):
        # 평문 폴백(세그먼트 지표 없음)에서도 이 문구는 걸러야 한다.
        assert judge("구독, 좋아요, 알림설정 부탁드립니다.").failure_reason == stt_verdict.NO_SPEECH

    def test_공백_문장부호_차이를_무시한다(self):
        assert judge("구독 좋아요 알림설정").failed
        assert judge("구독,좋아요,알림설정!").failed

    def test_시청_감사_정형구도_무음(self):
        assert judge("시청해주셔서 감사합니다").failed

    def test_짧은_대답은_지우지_않는다(self):
        # "네"·"음"·"안녕하세요"는 아이가 실제로 하는 답이다 — 목록으로 지우면 답변이 사라진다.
        for answer in ("네", "음", "아니", "안녕하세요", "감사합니다", "몰라"):
            verdict = judge(answer)
            assert verdict.status == stt_verdict.STATUS_SUCCESS, answer

    def test_정형구가_문장에_섞여_있으면_지우지_않는다(self):
        # 부분 일치로 판정하면 아이 발화까지 잘린다.
        assert not judge("엄마가 구독 좋아요 누르라고 했어").failed


class TestNoMetricsFallback:
    def test_지표가_없으면_텍스트만으로_통과시킨다(self):
        # 근거 없이 실패로 만들면 정상 음성 인식을 잃는다.
        verdict = judge("이건 우리 집이고 옆은 나무야")
        assert verdict.status == stt_verdict.STATUS_SUCCESS
        assert verdict.needs_confirmation is False


class TestWeightedMetrics:
    def test_세그먼트가_없으면_빈_지표(self):
        metrics = stt_verdict.weighted_metrics([])
        assert metrics.no_speech_prob is None
        assert metrics.avg_logprob is None
        assert metrics.segment_count == 0

    def test_길이_가중_평균을_쓴다(self):
        # 0.2초 잡음(무음확률 1.0)과 4초 발화(0.0)를 균등 평균하면 0.5로 무음에 가까워진다.
        # 길이로 가중하면 0.048 — 발화가 판정을 주도한다.
        segments = [
            {"start": 0.0, "end": 0.2, "no_speech_prob": 1.0, "avg_logprob": -2.0},
            {"start": 0.2, "end": 4.2, "no_speech_prob": 0.0, "avg_logprob": -0.2},
        ]
        metrics = stt_verdict.weighted_metrics(segments)
        assert metrics.no_speech_prob < 0.1
        assert metrics.avg_logprob > -0.35
        assert metrics.segment_count == 2
        assert metrics.audio_duration_sec == 4.2

    def test_길이를_모르면_균등평균으로_떨어진다(self):
        segments = [{"no_speech_prob": 1.0}, {"no_speech_prob": 0.0}]
        assert stt_verdict.weighted_metrics(segments).no_speech_prob == 0.5

    def test_일부_세그먼트에_지표가_없어도_남은_값으로_계산한다(self):
        segments = [
            {"start": 0.0, "end": 1.0, "no_speech_prob": 0.4},
            {"start": 1.0, "end": 2.0},
        ]
        metrics = stt_verdict.weighted_metrics(segments)
        assert metrics.no_speech_prob == 0.4
        assert metrics.avg_logprob is None

    def test_불리언은_수치로_받지_않는다(self):
        # True가 1.0으로 섞여 들어가면 무음 판정이 조용히 뒤집힌다.
        segments = [{"no_speech_prob": True}]
        assert stt_verdict.weighted_metrics(segments).no_speech_prob is None


class TestFillerNormalization:
    def test_대문자_영문_자막표기도_정규화된다(self):
        assert stt_verdict.normalize_for_filler_match("한글자막 BY 홍길동").startswith("한글자막by")

    def test_빈_정규화_결과는_무음으로_본다(self):
        assert stt_verdict.is_filler_only("...!!!???")
