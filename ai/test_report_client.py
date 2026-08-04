"""report_client 단위 테스트 — GMS 호출을 가짜로 대체해 조립·에러 매핑만 검증.

실제 네트워크·모델 없이 돈다. get_client 를 monkeypatch 해 chat.completions.create
호출 인자(프롬프트)를 가로채고, LLM JSON → 계약 결과 조립, 서버 고정 필드(안전 문구·상태),
emotion_source 규칙, visibility_scope 강제, OpenAIError → RuntimeError 변환을 확인한다.
"""

from __future__ import annotations

import json
import types
import unittest
from unittest import mock

from openai import OpenAIError

import internal_contracts as contracts
import prompts_registry
import report_client


def _fake_response(text: str, *, model: str | None = None):
    message = types.SimpleNamespace(content=text)
    choice = types.SimpleNamespace(message=message)
    resp = types.SimpleNamespace(choices=[choice])
    if model is not None:
        resp.model = model  # GMS가 실제 서빙한 모델 ID
    return resp


def _llm_json(**overrides) -> str:
    """LLM이 돌려줄 법한 JSON 문자열(정성 필드만). overrides로 일부 키 교체."""
    payload = {
        "overallSummary": "아이는 그림 활동에 즐겁게 참여했어요.",
        "positiveSignals": "자기 생각을 적극적으로 표현했어요.",
        "attentionPoints": "특이 관찰 사항 없음",
        "evidenceSummary": "집을 크게 그리고 가족을 함께 그린 점에서 관찰됨.",
        "guardianGuidance": "아이의 이야기를 편안하게 들어주세요.",
        "followUpQuestion": "이 집에는 누가 살고 있어?",
        "expertReviewRequired": False,
        "features": [
            {
                "featureCode": "HOUSE_CENTER",
                "title": "가운데 큰 집",
                "description": "집을 화면 가운데에 크게 그렸어요.",
                "evidenceSummary": "그림 관찰 서술 근거",
                "visibilityScope": "REVIEWED_GUARDIAN",
            }
        ],
        "conversationSummary": {
            "summaryText": "우리 집과 가족 이야기를 나눴어요.",
            "mainTopic": "우리 집",
            "expressedEmotion": "즐거움",
        },
        "activityNotes": ["활동 내내 집중했어요."],
        "followUpGuides": [
            {"guidance": "개방형 질문으로 이야기해 보세요.", "detailText": "정답을 요구하지 않는 질문이 표현을 돕습니다."}
        ],
        "guardianQuestions": [
            {"questionText": "가장 마음에 드는 부분은 어디야?", "questionPurpose": "표현 확장"}
        ],
    }
    payload.update(overrides)
    return json.dumps(payload, ensure_ascii=False)


def _sample_request(**overrides) -> contracts.ObservationGenerationRequest:
    base = {
        "request_id": "req-1",
        "analysis_id": 10,
        "drawing_session_id": 20,
        "analysis_type": "FINAL",
        "question_difficulty": "PRESCHOOL",
        "question_count": 5,
        "answered_count": 4,
        "skipped_count": 1,
        "unrecognized_speech_count": 0,
        "selected_emotions": ["JOY"],
        "expressed_emotion_text": None,
        "representative_utterance": "이건 우리 집이야.",
    }
    base.update(overrides)
    return contracts.ObservationGenerationRequest(**base)


def _htp_request(**overrides) -> contracts.ObservationGenerationRequest:
    """HTP 활동 요청 — drawingSubject가 채워진 subject_summaries가 HTP 판별 근거다.

    RAG는 HTP 리포트에서만 검색한다. 그림일기(subject 없음)·구 BE(빈 목록)는
    검색을 건너뛰고 RAG_NOT_APPLICABLE로 표시된다.
    """
    overrides.setdefault(
        "subject_summaries",
        [
            contracts.SubjectSummary(
                drawing_subject="HOUSE",
                drawing_description="집이 가운데에 크게 그려져 있어요.",
                detected_object_codes=["HOUSE"],
            )
        ],
    )
    return _sample_request(**overrides)


class GenerateTest(unittest.TestCase):
    def test_assembles_contract_result_with_server_owned_fields(self):
        captured = {}

        def fake_create(*, model, messages, **_kwargs):
            captured["model"] = model
            captured["messages"] = messages
            return _fake_response(_llm_json())

        fake_client = mock.Mock()
        fake_client.chat.completions.create.side_effect = fake_create

        req = _sample_request()
        with mock.patch.object(report_client, "get_client", return_value=fake_client):
            result = report_client.generate(
                req,
                drawing_description="가운데에 집이 크게, 왼쪽에 나무가 있어요.",
                model="test-model",
            )

        # 서버가 고정으로 채우는 필드
        self.assertEqual(result.request_id, "req-1")  # 요청 에코
        self.assertEqual(result.model_name, "test-model")
        # model_version은 프롬프트+파이프라인 복합 버전(S15P11B209-602).
        # _sample_request()는 subject_summaries가 없어 그림일기(비 HTP) 경로다.
        self.assertEqual(result.model_version, report_client._generation_version(False))
        self.assertIsNone(result.confidence)
        self.assertEqual(result.observation_draft.status, "AI_DRAFT")
        self.assertEqual(result.observation_draft.disclaimer, report_client.DISCLAIMER)
        self.assertEqual(result.limitations_text, report_client.LIMITATIONS)

        # LLM 정성 필드가 그대로 실렸는지
        self.assertIn("즐겁게", result.observation_draft.overall_summary)
        self.assertEqual(len(result.observation_draft.features), 1)
        self.assertEqual(
            result.observation_draft.features[0].visibility_scope, "REVIEWED_GUARDIAN"
        )
        self.assertEqual(result.conversation_summary.main_topic, "우리 집")

        # emotion_source 는 요청으로 결정(선택 감정 있음 → SELECTED)
        self.assertEqual(result.conversation_summary.emotion_source, "SELECTED")
        # 대표 발화는 요청 값 에코
        self.assertEqual(
            result.conversation_summary.representative_utterance, "이건 우리 집이야."
        )

        # 그림 서술이 프롬프트(user 메시지)에 근거로 들어갔는지
        user_msg = captured["messages"][1]["content"]
        self.assertIn("가운데에 집이 크게", user_msg)
        self.assertIn("[그림 관찰 서술]", user_msg)

    def test_behavior_metrics_injected_into_prompt(self):
        captured = {}

        def fake_create(*, model, messages, **_kwargs):
            captured["messages"] = messages
            return _fake_response(_llm_json())

        fake_client = mock.Mock()
        fake_client.chat.completions.create.side_effect = fake_create

        behavior = contracts.BehaviorMetrics(
            drawing_duration_ms=600_000,
            pause_count=4,
            erase_count=3,
            pressure_available=True,
            average_pressure=0.62,
        )
        with mock.patch.object(report_client, "get_client", return_value=fake_client):
            report_client.generate(_sample_request(), behavior=behavior, model="m")

        user_msg = captured["messages"][1]["content"]
        self.assertIn("[형식적 분석]", user_msg)
        self.assertIn("약 10분", user_msg)  # 600_000ms → 10분
        self.assertIn("지우기 횟수: 3회", user_msg)
        self.assertIn("평균 0.62", user_msg)

    def test_pressure_line_is_omitted_without_a_value(self):
        """필압 강약 값이 없으면 필압 줄을 아예 내지 않는다 (S15P11B209-838).

        pressure_available 은 기기가 측정할 수 있는지일 뿐 아이에 대한 관찰이 아니다 —
        "측정됨"·"측정 불가"를 적으면 관찰 내용이 0인 줄이 해석 재료처럼 놓인다.
        """
        captured = {}
        fake_client = mock.Mock()
        fake_client.chat.completions.create.side_effect = lambda **k: captured.update(
            messages=k["messages"]
        ) or _fake_response(_llm_json())

        behavior = contracts.BehaviorMetrics(
            pressure_available=True, average_pressure=None, erase_count=1
        )
        with mock.patch.object(report_client, "get_client", return_value=fake_client):
            report_client.generate(_sample_request(), behavior=behavior, model="m")

        user_msg = captured["messages"][1]["content"]
        self.assertNotIn("필압", user_msg)
        self.assertIn("지우기 횟수: 1회", user_msg)  # 다른 항목은 그대로 실린다


class BehaviorMetricsContractTest(unittest.TestCase):
    """요청 계약으로 들어온 형식 지표가 프롬프트까지 도달하는지 (S15P11B209-836).

    확장 전에는 behavior 를 넘길 수단이 계약에 없어 [형식적 분석] 블록이 운영 경로에서
    한 번도 실리지 않았다 — 이 테스트가 그 배선을 고정한다.
    """

    def _capture_prompt(self, req) -> str:
        captured = {}
        fake_client = mock.Mock()
        fake_client.chat.completions.create.side_effect = lambda **k: captured.update(
            messages=k["messages"]
        ) or _fake_response(_llm_json())
        with mock.patch.object(report_client, "get_client", return_value=fake_client):
            report_client.generate(req, model="m")
        return captured["messages"][1]["content"]

    def test_request_behavior_metrics_reach_the_prompt(self):
        req = _sample_request()
        req.behavior_metrics = contracts.BehaviorMetrics(
            drawing_duration_ms=720_000, erase_count=3, pressure_available=False
        )

        user_msg = self._capture_prompt(req)

        self.assertIn("[형식적 분석]", user_msg)
        self.assertIn("약 12분", user_msg)
        self.assertIn("지우기 횟수: 3회", user_msg)

    def test_absent_behavior_metrics_keeps_legacy_behaviour(self):
        """구 BE(behaviorMetrics 미전달) 요청은 확장 전과 똑같이 동작한다."""
        user_msg = self._capture_prompt(_sample_request())

        self.assertNotIn("[형식적 분석]", user_msg)

    def test_zero_and_none_are_distinguished(self):
        """0은 '0회'라는 관찰 사실, None은 '집계 못 함' — 같은 문장이 되면 안 된다."""
        req = _sample_request()
        req.behavior_metrics = contracts.BehaviorMetrics(
            pause_count=0, erase_count=None, pressure_available=False
        )

        user_msg = self._capture_prompt(req)

        self.assertIn("멈춤 횟수: 0번", user_msg)
        self.assertNotIn("지우기 횟수", user_msg)

    def test_explicit_argument_overrides_contract_value(self):
        """draft·스모크가 계약 밖 값을 넣어 볼 수 있어야 한다."""
        req = _sample_request()
        req.behavior_metrics = contracts.BehaviorMetrics(drawing_duration_ms=60_000)
        captured = {}
        fake_client = mock.Mock()
        fake_client.chat.completions.create.side_effect = lambda **k: captured.update(
            messages=k["messages"]
        ) or _fake_response(_llm_json())

        with mock.patch.object(report_client, "get_client", return_value=fake_client):
            report_client.generate(
                req,
                behavior=contracts.BehaviorMetrics(drawing_duration_ms=600_000),
                model="m",
            )

        self.assertIn("약 10분", captured["messages"][1]["content"])

    def test_camel_case_payload_parses(self):
        """BE가 보내는 camelCase JSON이 계약 모델로 그대로 들어온다."""
        req = contracts.ObservationGenerationRequest.model_validate(
            {
                "requestId": "r-1",
                "analysisId": 1,
                "drawingSessionId": 1,
                "analysisType": "FINAL",
                "behaviorMetrics": {
                    "drawingDurationMs": 720000,
                    "activeDrawingMs": 480000,
                    "pauseCount": 4,
                    "undoCount": 2,
                    "eraseCount": 3,
                    "toolChangeCount": 1,
                    "colorChangeCount": 5,
                    "pressureAvailable": True,
                    "averagePressure": None,
                    "truncated": False,
                },
            }
        )

        self.assertEqual(720000, req.behavior_metrics.drawing_duration_ms)
        self.assertEqual(480000, req.behavior_metrics.active_drawing_ms)
        self.assertIsNone(req.behavior_metrics.average_pressure)
        self.assertFalse(req.behavior_metrics.truncated)


class BehaviorBlockWordingTest(unittest.TestCase):
    """[형식적 분석] 블록의 표현 규칙 (S15P11B209-838).

    블록 생성만 검증하므로 LLM 호출 없이 _format_behavior 를 직접 부른다.
    """

    def test_truncated_marks_partial_aggregation(self):
        """부분 집계를 활동 전체처럼 읽히게 두면 안 된다."""
        block = report_client._format_behavior(
            contracts.BehaviorMetrics(drawing_duration_ms=720_000, truncated=True)
        )

        self.assertIn("저장된 캔버스 입력 구간까지만 집계", block)
        self.assertIn("활동 전체가 아닐 수 있어요", block)

    def test_complete_aggregation_has_no_partial_note(self):
        block = report_client._format_behavior(
            contracts.BehaviorMetrics(drawing_duration_ms=720_000, truncated=False)
        )

        self.assertNotIn("저장된 캔버스 입력 구간", block)

    def test_htp_block_states_three_drawing_scope(self):
        """HTP는 BE가 세 단계를 합산해 보낸다 — 한 장 기준으로 읽히면 안 된다."""
        block = report_client._format_behavior(
            contracts.BehaviorMetrics(drawing_duration_ms=720_000), is_htp=True
        )

        self.assertIn("집·나무·사람 세 장을 합친 활동 전체 기준", block)

    def test_diary_block_has_no_htp_scope_note(self):
        block = report_client._format_behavior(
            contracts.BehaviorMetrics(drawing_duration_ms=720_000), is_htp=False
        )

        self.assertNotIn("세 장", block)

    def test_pause_count_is_hedged_as_an_estimate(self):
        """배치 경계 기반 추정값이라 단정 표기를 피한다."""
        block = report_client._format_behavior(
            contracts.BehaviorMetrics(pause_count=4)
        )

        self.assertIn("약 4번", block)
        self.assertIn("추정값", block)

    def test_zero_pauses_avoid_the_approximation_word(self):
        """'약 0번'은 문장이 이상하다 — 0일 때만 숫자를 그대로 쓴다."""
        block = report_client._format_behavior(
            contracts.BehaviorMetrics(pause_count=0)
        )

        self.assertIn("멈춤 횟수: 0번", block)
        self.assertNotIn("약 0번", block)

    def test_minutes_are_rounded_to_whole_minutes(self):
        """0.1분 자리는 집계가 갖지 않은 정밀도다(구 구현의 '약 10.0분')."""
        block = report_client._format_behavior(
            contracts.BehaviorMetrics(
                drawing_duration_ms=600_000, active_drawing_ms=410_000
            )
        )

        self.assertIn("총 소요시간: 약 10분", block)
        self.assertIn("실제 그린 시간: 약 7분", block)  # 410_000ms ≈ 6.83분 → 7분
        self.assertNotIn(".", block)

    def test_under_a_minute_is_not_rounded_to_zero(self):
        """'약 0분'은 아예 안 그린 것처럼 읽힌다."""
        block = report_client._format_behavior(
            contracts.BehaviorMetrics(drawing_duration_ms=30_000)
        )

        self.assertIn("1분 미만", block)
        self.assertNotIn("약 0분", block)

    def test_block_is_dropped_when_nothing_is_measurable(self):
        """적을 관찰이 하나도 없으면 빈 블록을 싣지 않는다 — 모델이 채우려 든다."""
        block = report_client._format_behavior(
            contracts.BehaviorMetrics(pressure_available=True, truncated=True)
        )

        self.assertEqual("", block)

    def test_tool_and_color_changes_are_not_rendered(self):
        """계약으로 받되 이번 단계에서는 블록에 싣지 않는다."""
        block = report_client._format_behavior(
            contracts.BehaviorMetrics(
                erase_count=1, tool_change_count=3, color_change_count=5
            )
        )

        self.assertIn("지우기 횟수: 1회", block)
        self.assertNotIn("도구", block)
        self.assertNotIn("색", block)


def _house_summary(**overrides) -> contracts.SubjectSummary:
    """집 그림 한 장의 주제 요약. detected_objects 를 overrides 로 갈아끼운다."""
    payload = {
        "drawingSubject": "HOUSE",
        "drawingDescription": "가운데에 집이 크게 그려져 있어요.",
        "detectedObjectCodes": ["HOUSE", "HOUSE_DOOR"],
        "detectedObjects": [
            {
                "objectCode": "HOUSE",
                "x": 0.21,
                "y": 0.18,
                "width": 0.55,
                "height": 0.60,
                "areaRatio": 0.33,
                "confidence": 0.94,
            },
            {
                "objectCode": "HOUSE_DOOR",
                "x": 0.42,
                "y": 0.70,
                "width": 0.09,
                "height": 0.16,
                "areaRatio": 0.014,
                "confidence": 0.81,
            },
        ],
    }
    payload.update(overrides)
    return contracts.SubjectSummary.model_validate(payload)


class GeometryBlockTest(unittest.TestCase):
    """[OO 크기·위치] 블록 생성 (S15P11B209-839).

    블록 생성만 검증하므로 LLM 호출 없이 _format_geometry 를 직접 부른다.
    """

    def test_area_and_position_are_rendered_as_facts(self):
        block = report_client._format_geometry(_house_summary(), "집 그림")

        self.assertIn("[집 그림 크기·위치]", block)
        self.assertIn("종이의 약 33%", block)
        self.assertIn("화면 한가운데", block)

    def test_part_ratio_is_relative_to_the_subject(self):
        """'집에 비해 문이 작다'를 수치로 남긴다 — 0.014 / 0.33 ≈ 4%."""
        block = report_client._format_geometry(_house_summary(), "집 그림")

        self.assertIn("집 전체의 약 4%", block)

    def test_missing_area_ratio_is_not_estimated(self):
        """areaRatio 가 없으면 점유율을 말하지 않는다 — width*height 로 보정 금지(BE 명시)."""
        summary = _house_summary(
            detectedObjects=[
                {
                    "objectCode": "HOUSE",
                    "x": 0.2,
                    "y": 0.2,
                    "width": 0.5,
                    "height": 0.5,
                    "areaRatio": None,
                    "confidence": 0.9,
                }
            ]
        )

        block = report_client._format_geometry(summary, "집 그림")

        self.assertNotIn("종이의", block)
        self.assertNotIn("%", block)
        self.assertIn("화면", block)  # 위치는 좌표만으로 말할 수 있다

    def test_low_confidence_detection_is_dropped(self):
        """탐지 임계값(0.20)은 박스를 남길 기준이지 문장의 근거 기준이 아니다."""
        summary = _house_summary(
            detectedObjects=[
                {
                    "objectCode": "HOUSE_WINDOW",
                    "x": 0.3,
                    "y": 0.3,
                    "width": 0.1,
                    "height": 0.1,
                    "areaRatio": 0.01,
                    "confidence": 0.31,
                }
            ]
        )

        self.assertEqual("", report_client._format_geometry(summary, "집 그림"))

    def test_middle_confidence_detection_is_hedged(self):
        summary = _house_summary(
            detectedObjects=[
                {
                    "objectCode": "HOUSE_WINDOW",
                    "x": 0.3,
                    "y": 0.3,
                    "width": 0.1,
                    "height": 0.1,
                    "areaRatio": 0.01,
                    "confidence": 0.55,
                }
            ]
        )

        block = report_client._format_geometry(summary, "집 그림")

        self.assertIn("확실하지 않아요", block)

    def test_high_confidence_detection_is_not_hedged(self):
        block = report_client._format_geometry(_house_summary(), "집 그림")

        self.assertNotIn("확실하지 않아요", block)

    def test_empty_detected_objects_produces_no_block(self):
        """구 BE·PIXEL 좌표뿐인 주제 — 기존 코드 목록 경로로 폴백한다."""
        summary = _house_summary(detectedObjects=[])

        self.assertEqual("", report_client._format_geometry(summary, "집 그림"))

    def test_diary_has_no_part_ratio(self):
        """그림일기는 주제 전체 객체가 없어 부위:주제 비율을 낼 수 없다."""
        summary = contracts.SubjectSummary.model_validate(
            {
                "drawingSubject": None,
                "detectedObjects": [
                    {
                        "objectCode": "SUN",
                        "x": 0.75,
                        "y": 0.05,
                        "width": 0.15,
                        "height": 0.15,
                        "areaRatio": 0.02,
                        "confidence": 0.88,
                    }
                ],
            }
        )

        block = report_client._format_geometry(summary, "그림")

        self.assertIn("종이의 약 2%", block)
        self.assertNotIn("전체의", block)  # 부위:주제 비율은 낼 수 없다
        self.assertIn("화면 위쪽 오른쪽", block)

    def test_tiny_object_avoids_zero_percent(self):
        """'약 0%'는 안 그린 것처럼 읽힌다."""
        summary = _house_summary(
            detectedObjects=[
                {
                    "objectCode": "HOUSE_CHIMNEY",
                    "x": 0.5,
                    "y": 0.1,
                    "width": 0.03,
                    "height": 0.03,
                    "areaRatio": 0.002,
                    "confidence": 0.9,
                }
            ]
        )

        block = report_client._format_geometry(summary, "집 그림")

        self.assertIn("1% 미만", block)
        self.assertNotIn("약 0%", block)

    def test_geometry_block_reaches_the_prompt(self):
        captured = {}
        fake_client = mock.Mock()
        fake_client.chat.completions.create.side_effect = lambda **k: captured.update(
            messages=k["messages"]
        ) or _fake_response(_llm_json())
        req = _sample_request()
        req.subject_summaries = [_house_summary()]

        with mock.patch.object(report_client, "get_client", return_value=fake_client):
            report_client.generate(req, model="m")

        user_msg = captured["messages"][1]["content"]
        self.assertIn("[집 그림 크기·위치]", user_msg)
        self.assertIn("종이의 약 33%", user_msg)


class DetectedObjectContractTest(unittest.TestCase):
    """탐지 기하 필드가 계약으로 들어오는지 (S15P11B209-836).

    소비(용지 점유율·9분할 위치 서술)는 S15P11B209-839 범위 — 여기서는 계약만 고정한다.
    """

    def test_detected_objects_parse_alongside_codes(self):
        req = contracts.ObservationGenerationRequest.model_validate(
            {
                "requestId": "r-1",
                "analysisId": 1,
                "drawingSessionId": 1,
                "analysisType": "FINAL",
                "subjectSummaries": [
                    {
                        "drawingSubject": "HOUSE",
                        "detectedObjectCodes": ["HOUSE", "HOUSE_DOOR"],
                        "detectedObjects": [
                            {
                                "objectCode": "HOUSE",
                                "x": 0.21,
                                "y": 0.18,
                                "width": 0.55,
                                "height": 0.60,
                                "areaRatio": 0.33,
                                "confidence": 0.94,
                            },
                            {
                                "objectCode": "HOUSE_DOOR",
                                "x": 0.42,
                                "y": 0.55,
                                "width": 0.09,
                                "height": 0.16,
                                "areaRatio": None,
                                "confidence": 0.81,
                            },
                        ],
                    }
                ],
            }
        )

        summary = req.subject_summaries[0]
        # 기존 코드 목록은 유지된다 — 신구 필드가 병렬로 존재한다(하위호환).
        self.assertEqual(["HOUSE", "HOUSE_DOOR"], summary.detected_object_codes)
        self.assertEqual(0.33, summary.detected_objects[0].area_ratio)
        # areaRatio 가 없으면 None 그대로 — width*height 로 보정하지 않는다(BE 명시).
        self.assertIsNone(summary.detected_objects[1].area_ratio)

    def test_missing_detected_objects_defaults_to_empty(self):
        """구 BE(그리고 PIXEL 결과만 있는 주제)는 빈 목록으로 들어온다."""
        req = contracts.ObservationGenerationRequest.model_validate(
            {
                "requestId": "r-1",
                "analysisId": 1,
                "drawingSessionId": 1,
                "analysisType": "FINAL",
                "subjectSummaries": [{"drawingSubject": "TREE"}],
            }
        )

        self.assertEqual([], req.subject_summaries[0].detected_objects)

    def test_without_description_prompts_placeholder(self):
        captured = {}

        def fake_create(*, model, messages, **_kwargs):
            captured["messages"] = messages
            return _fake_response(_llm_json())

        fake_client = mock.Mock()
        fake_client.chat.completions.create.side_effect = fake_create

        with mock.patch.object(report_client, "get_client", return_value=fake_client):
            report_client.generate(_sample_request(), model="m")

        user_msg = captured["messages"][1]["content"]
        self.assertIn("그림 관찰 서술이 제공되지 않았어요", user_msg)

    def test_invalid_visibility_scope_coerced_to_expert_only(self):
        fake_client = mock.Mock()
        fake_client.chat.completions.create.return_value = _fake_response(
            _llm_json(
                features=[
                    {
                        "featureCode": "X",
                        "title": "t",
                        "description": "d",
                        "evidenceSummary": "e",
                        "visibilityScope": "PUBLIC",  # 계약에 없는 값
                    }
                ]
            )
        )
        with mock.patch.object(report_client, "get_client", return_value=fake_client):
            result = report_client.generate(_sample_request(), model="m")
        self.assertEqual(
            result.observation_draft.features[0].visibility_scope, "EXPERT_ONLY"
        )

    def test_openai_error_maps_to_runtime_error(self):
        fake_client = mock.Mock()
        fake_client.chat.completions.create.side_effect = OpenAIError("boom")
        with mock.patch.object(report_client, "get_client", return_value=fake_client):
            with self.assertRaises(RuntimeError):
                report_client.generate(_sample_request(), model="m")


class DefinitiveDiagnosisQuarantineTest(unittest.TestCase):
    """단정적 진단 표현 격리 — 전문가 검토 + EXPERT_ONLY 강등 (S15P11B209-591)."""

    def _generate(self, **overrides):
        fake_client = mock.Mock()
        fake_client.chat.completions.create.return_value = _fake_response(
            _llm_json(**overrides)
        )
        with mock.patch.object(report_client, "get_client", return_value=fake_client):
            return report_client.generate(_sample_request(), model="m")

    def test_guardian_feature_with_diagnosis_downgraded_to_expert_only(self):
        result = self._generate(
            features=[
                {
                    "featureCode": "X",
                    "title": "정서 관찰",
                    "description": "이 아이는 불안장애로 진단됩니다.",  # 단정
                    "evidenceSummary": "e",
                    "visibilityScope": "REVIEWED_GUARDIAN",
                }
            ]
        )
        self.assertEqual(
            result.observation_draft.features[0].visibility_scope, "EXPERT_ONLY"
        )
        # 보호자 노출 내용에 단정 진단이 있으면 전문가 검토를 강제한다.
        self.assertTrue(result.observation_draft.expert_review_required)

    def test_hedged_concern_feature_stays_guardian_visible(self):
        result = self._generate(
            expertReviewRequired=False,
            features=[
                {
                    "featureCode": "X",
                    "title": "정서 관찰",
                    "description": "속상한 마음이 담긴 듯 보일 수 있어요.",  # 여지
                    "evidenceSummary": "e",
                    "visibilityScope": "REVIEWED_GUARDIAN",
                }
            ],
        )
        self.assertEqual(
            result.observation_draft.features[0].visibility_scope, "REVIEWED_GUARDIAN"
        )
        self.assertFalse(result.observation_draft.expert_review_required)

    def test_diagnosis_in_overall_summary_forces_expert_review(self):
        result = self._generate(
            expertReviewRequired=False,
            overallSummary="이 아이는 우울증이 있어 보입니다.",  # 장애명 단정
        )
        self.assertTrue(result.observation_draft.expert_review_required)


class OverinferenceQuarantineTest(unittest.TestCase):
    """감정·성격 과잉 추론 격리 — 전문가 검토 + EXPERT_ONLY 강등 (S15P11B209-592)."""

    def _generate(self, **overrides):
        fake_client = mock.Mock()
        fake_client.chat.completions.create.return_value = _fake_response(
            _llm_json(**overrides)
        )
        with mock.patch.object(report_client, "get_client", return_value=fake_client):
            return report_client.generate(_sample_request(), model="m")

    def test_guardian_feature_with_trait_labeling_downgraded_to_expert_only(self):
        result = self._generate(
            features=[
                {
                    "featureCode": "X",
                    "title": "성격 관찰",
                    "description": "공격적인 성향이 있어요.",  # 고정 특질 규정
                    "evidenceSummary": "e",
                    "visibilityScope": "REVIEWED_GUARDIAN",
                }
            ]
        )
        self.assertEqual(
            result.observation_draft.features[0].visibility_scope, "EXPERT_ONLY"
        )
        self.assertTrue(result.observation_draft.expert_review_required)

    def test_overinference_in_overall_summary_forces_expert_review(self):
        result = self._generate(
            expertReviewRequired=False,
            overallSummary="정서적으로 불안한 아이입니다.",  # 정체성 규정
        )
        self.assertTrue(result.observation_draft.expert_review_required)

    def test_behavioral_observation_stays_guardian_visible(self):
        result = self._generate(
            expertReviewRequired=False,
            features=[
                {
                    "featureCode": "X",
                    "title": "활동 관찰",
                    "description": "조심스러운 모습을 보였어요.",  # 행동 관찰
                    "evidenceSummary": "e",
                    "visibilityScope": "REVIEWED_GUARDIAN",
                }
            ],
        )
        self.assertEqual(
            result.observation_draft.features[0].visibility_scope, "REVIEWED_GUARDIAN"
        )
        self.assertFalse(result.observation_draft.expert_review_required)


class UngroundedInterpretationTest(unittest.TestCase):
    """관찰 사실 ↔ AI 해석 분리 — 근거 없는 해석은 보호자 노출 불가 (S15P11B209-600)."""

    def _generate(self, **overrides):
        fake_client = mock.Mock()
        fake_client.chat.completions.create.return_value = _fake_response(
            _llm_json(**overrides)
        )
        with mock.patch.object(report_client, "get_client", return_value=fake_client):
            return report_client.generate(_sample_request(), model="m")

    def test_interpretation_without_evidence_downgraded_to_expert_only(self):
        # description(해석)은 있는데 evidenceSummary(근거)가 비면 억측 → 격리.
        result = self._generate(
            features=[
                {
                    "featureCode": "X",
                    "title": "정서 관찰",
                    "description": "마음이 편안해 보여요.",  # 해석
                    "evidenceSummary": "   ",  # 근거 없음(공백)
                    "visibilityScope": "REVIEWED_GUARDIAN",
                }
            ]
        )
        self.assertEqual(
            result.observation_draft.features[0].visibility_scope, "EXPERT_ONLY"
        )

    def test_interpretation_with_evidence_stays_guardian_visible(self):
        # 근거가 있으면 그대로 보호자에게 보인다(정상 경로).
        result = self._generate(
            features=[
                {
                    "featureCode": "X",
                    "title": "정서 관찰",
                    "description": "즐겁게 그린 것으로 보여요.",  # 해석
                    "evidenceSummary": "밝은 색을 많이 썼고 지우기가 적었어요.",  # 관찰 사실 근거
                    "visibilityScope": "REVIEWED_GUARDIAN",
                }
            ]
        )
        self.assertEqual(
            result.observation_draft.features[0].visibility_scope, "REVIEWED_GUARDIAN"
        )


class VersionRecordingTest(unittest.TestCase):
    """리포트 model·prompt·pipelineVersion 저장 (S15P11B209-602)."""

    def test_model_version_carries_prompt_and_pipeline(self):
        fake_client = mock.Mock()
        fake_client.chat.completions.create.return_value = _fake_response(_llm_json())
        with mock.patch.object(report_client, "get_client", return_value=fake_client):
            result = report_client.generate(_sample_request(), model="m")
        # 재현성 3종: model_name(모델) + model_version(프롬프트·파이프라인)
        self.assertIn(f"pipeline={report_client.config.PIPELINE_VERSION}", result.model_version)
        self.assertIn("prompt=", result.model_version)
        # '이번에 쓴' 조합만 실린다 — 두 변형을 다 적으면 어느 쪽으로 뽑혔는지 구분이 안 된다.
        # 조합은 축약 태그로 실리고(819) 변형은 라벨로 구분된다.
        self.assertIn(report_client._generation_version(False), result.model_version)
        self.assertIn("prompt=diary@", result.model_version)
        self.assertNotIn("htp@", result.model_version)

    def test_htp_request_records_htp_prompt_version(self):
        fake_client = mock.Mock()
        fake_client.chat.completions.create.return_value = _fake_response(_llm_json())
        with mock.patch.object(
            report_client, "retrieve", return_value=[]
        ), mock.patch.object(report_client, "get_client", return_value=fake_client):
            result = report_client.generate(_htp_request(), model="m")
        self.assertIn("prompt=htp@", result.model_version)
        self.assertNotIn("diary@", result.model_version)

    def test_model_version_fits_backend_column(self):
        """BE generated_model_version·summary_model_version 컬럼 한계 (S15P11B209-819).

        786에서 리포트 프롬프트가 갈리며 76자가 돼 컬럼(VARCHAR(50))을 넘겼고, 저장 실패가
        리포트 전량 실패로 번졌다(815). 생성 경로에서 직접 한 번 더 못박는다.
        """
        for is_htp in (True, False):
            value = report_client._generation_version(is_htp)
            self.assertLessEqual(
                len(value), prompts_registry.MAX_VERSION_TAG, f"{len(value)}자: {value}"
            )

    def test_model_name_records_actual_served_model(self):
        # GMS가 실제 서빙한 모델 ID를 기록한다(요청 모델명이 아니라).
        fake_client = mock.Mock()
        fake_client.chat.completions.create.return_value = _fake_response(
            _llm_json(), model="gpt-4o-mini-2024-07-18"
        )
        with mock.patch.object(report_client, "get_client", return_value=fake_client):
            result = report_client.generate(_sample_request(), model="gpt-4o-mini")
        self.assertEqual(result.model_name, "gpt-4o-mini-2024-07-18")

    def test_model_name_falls_back_to_requested_when_unknown(self):
        fake_client = mock.Mock()
        fake_client.chat.completions.create.return_value = _fake_response(_llm_json())
        with mock.patch.object(report_client, "get_client", return_value=fake_client):
            result = report_client.generate(_sample_request(), model="req-model")
        self.assertEqual(result.model_name, "req-model")


class FollowUpAndDisclaimerTest(unittest.TestCase):
    """진단 표현 제거·한계 고지·후속 질문 생성 보장 (S15P11B209-601)."""

    def _generate(self, **overrides):
        fake_client = mock.Mock()
        fake_client.chat.completions.create.return_value = _fake_response(
            _llm_json(**overrides)
        )
        with mock.patch.object(report_client, "get_client", return_value=fake_client):
            return report_client.generate(_sample_request(), model="m")

    def test_empty_follow_up_is_filled_with_safe_default(self):
        result = self._generate(followUpQuestion="   ")
        self.assertEqual(
            result.observation_draft.follow_up_question,
            report_client.DEFAULT_FOLLOW_UP_QUESTION,
        )

    def test_diagnostic_follow_up_is_replaced_with_safe_default(self):
        # 후속 질문에 진단성 표현이 섞이면 보호자에게 그대로 내보내지 않고 안전 기본값으로 대체.
        result = self._generate(followUpQuestion="아이가 우울증이 있는지 물어보세요.")
        self.assertEqual(
            result.observation_draft.follow_up_question,
            report_client.DEFAULT_FOLLOW_UP_QUESTION,
        )

    def test_normal_follow_up_is_kept(self):
        result = self._generate(followUpQuestion="이 집에는 누가 살아?")
        self.assertEqual(
            result.observation_draft.follow_up_question, "이 집에는 누가 살아?"
        )

    def test_object_follow_up_extracts_question_text(self):
        # 모델이 스키마를 벗어나 객체로 줘도 questionText만 싣는다(dict가 통째로 문자열화되면 안 됨).
        result = self._generate(
            followUpQuestion={
                "questionText": "그림 속 집은 어떤 곳이야?",
                "questionPurpose": "상상력 자극",
            }
        )
        self.assertEqual(
            result.observation_draft.follow_up_question, "그림 속 집은 어떤 곳이야?"
        )
        self.assertNotIn("questionPurpose", result.observation_draft.follow_up_question)

    def test_object_follow_up_without_question_text_falls_back(self):
        result = self._generate(followUpQuestion={"questionPurpose": "목적만 있음"})
        self.assertEqual(
            result.observation_draft.follow_up_question,
            report_client.DEFAULT_FOLLOW_UP_QUESTION,
        )

    def test_disclaimer_and_limitations_always_present(self):
        # 한계 고지·면책 문구는 LLM이 무엇을 주든 서버가 상수로 항상 보장한다.
        result = self._generate(overallSummary="")
        self.assertEqual(result.observation_draft.disclaimer, report_client.DISCLAIMER)
        self.assertEqual(result.limitations_text, report_client.LIMITATIONS)
        self.assertTrue(result.observation_draft.disclaimer.strip())
        self.assertTrue(result.limitations_text.strip())


class EmotionSourceTest(unittest.TestCase):
    def test_selected(self):
        req = _sample_request(selected_emotions=["JOY"], expressed_emotion_text=None)
        self.assertEqual(report_client._emotion_source(req), "SELECTED")

    def test_stated(self):
        req = _sample_request(selected_emotions=[], expressed_emotion_text="무서웠어")
        self.assertEqual(report_client._emotion_source(req), "STATED")

    def test_inferred(self):
        req = _sample_request(selected_emotions=[], expressed_emotion_text=None)
        self.assertEqual(report_client._emotion_source(req), "INFERRED")


class ExtractJsonTest(unittest.TestCase):
    def test_strips_code_fence(self):
        raw = "```json\n{\"a\": 1}\n```"
        self.assertEqual(report_client._extract_json(raw), {"a": 1})

    def test_ignores_surrounding_prose(self):
        raw = "결과입니다: {\"a\": 2} 이상입니다."
        self.assertEqual(report_client._extract_json(raw), {"a": 2})

    def test_no_json_raises_runtime_error(self):
        with self.assertRaises(RuntimeError):
            report_client._extract_json("여기엔 JSON이 없어요")


class SubjectSummariesTest(unittest.TestCase):
    """주제별 그림 서술·문답 프롬프트 반영 (S15P11B209-740).

    HTP 3주제가 각각 [OO 그림 관찰]·[OO 그림 문답] 블록으로 실리고, 없으면 기존
    단일 [그림 관찰 서술] 경로가 그대로인지(롤아웃 호환) 검증한다.
    """

    def _capture_user_msg(self, req, **generate_kwargs) -> str:
        captured = {}

        def fake_create(*, model, messages, **_kwargs):
            captured["messages"] = messages
            return _fake_response(_llm_json())

        fake_client = mock.Mock()
        fake_client.chat.completions.create.side_effect = fake_create
        with mock.patch.object(report_client, "get_client", return_value=fake_client):
            report_client.generate(req, model="m", **generate_kwargs)
        return captured["messages"][1]["content"]

    @staticmethod
    def _htp_summaries() -> list[contracts.SubjectSummary]:
        return [
            contracts.SubjectSummary(
                drawing_subject="HOUSE",
                drawing_description="가운데에 집이 크게 그려져 있어요.",
                detected_object_codes=["HOUSE", "HOUSE_DOOR"],
                qa_pairs=[
                    contracts.SubjectQaPair(
                        question="이 집에는 누가 살아?",
                        answer_text="엄마랑 나!",
                        answer_type="VOICE",
                    ),
                    contracts.SubjectQaPair(
                        question="집 앞에는 뭐가 있어?",
                        answer_text=None,
                        answer_type=None,  # SKIPPED 아님 — 단순 무응답
                    ),
                ],
            ),
            contracts.SubjectSummary(
                drawing_subject="TREE",
                drawing_description="나무에 열매가 세 개 달려 있어요.",
                qa_pairs=[
                    contracts.SubjectQaPair(
                        question="이 나무는 어디에 있어?",
                        answer_text=None,
                        answer_type="SKIPPED",
                    )
                ],
            ),
            contracts.SubjectSummary(
                drawing_subject="PERSON",
                drawing_description="사람 두 명이 손을 잡고 있어요.",
            ),
        ]

    def test_subject_blocks_rendered_per_subject(self):
        req = _sample_request(subject_summaries=self._htp_summaries())
        user_msg = self._capture_user_msg(req)

        for label in ("[집 그림 관찰]", "[나무 그림 관찰]", "[사람 그림 관찰]"):
            self.assertIn(label, user_msg)
        self.assertIn("[집 그림 문답]", user_msg)
        self.assertIn("이 집에는 누가 살아?", user_msg)
        self.assertIn("엄마랑 나!", user_msg)
        self.assertIn("HOUSE_DOOR", user_msg)  # 참고용 요소 코드
        # 주제별 블록이 실리면 레거시 단일 블록은 없다.
        self.assertNotIn("[그림 관찰 서술]", user_msg)
        # 문답 없는 주제(사람)는 문답 블록도 없다.
        self.assertNotIn("[사람 그림 문답]", user_msg)

    def test_subject_blocks_take_priority_over_legacy_description(self):
        req = _sample_request(subject_summaries=self._htp_summaries())
        user_msg = self._capture_user_msg(
            req, drawing_description="레거시 단일 서술입니다."
        )
        self.assertNotIn("레거시 단일 서술입니다.", user_msg)
        self.assertIn("[집 그림 관찰]", user_msg)

    def test_art_diary_none_subject_uses_generic_label(self):
        req = _sample_request(
            subject_summaries=[
                contracts.SubjectSummary(
                    drawing_subject=None,
                    drawing_description="공룡이 풍선을 들고 있어요.",
                    qa_pairs=[
                        contracts.SubjectQaPair(question="공룡은 기분이 어때?")
                    ],
                )
            ]
        )
        user_msg = self._capture_user_msg(req)
        self.assertIn("[그림 관찰]", user_msg)
        self.assertIn("[그림 문답]", user_msg)
        # '그림 그림' 같은 라벨 중복이 없어야 한다.
        self.assertNotIn("그림 그림", user_msg)

    def test_skipped_question_rendered_distinctly_from_unanswered(self):
        req = _sample_request(subject_summaries=self._htp_summaries())
        user_msg = self._capture_user_msg(req)
        # SKIPPED(나무 문답)는 '건너뜀'으로, 타입 없는 무응답(집 두 번째 문답)은 별도 표기.
        self.assertIn("(건너뛴 질문)", user_msg)
        self.assertIn("(답하지 않았어요)", user_msg)

    def test_empty_subject_summaries_keeps_legacy_block(self):
        req = _sample_request(subject_summaries=[])
        user_msg = self._capture_user_msg(
            req, drawing_description="가운데에 집이 크게."
        )
        self.assertIn("[그림 관찰 서술]", user_msg)
        self.assertIn("가운데에 집이 크게.", user_msg)

    def test_answer_text_hidden_from_repr(self):
        qa = contracts.SubjectQaPair(question="누가 살아?", answer_text="비밀 발화")
        self.assertNotIn("비밀 발화", repr(qa))
        req = _sample_request(
            subject_summaries=[
                contracts.SubjectSummary(drawing_subject="HOUSE", qa_pairs=[qa])
            ]
        )
        self.assertNotIn("비밀 발화", repr(req))

    def test_camelcase_json_parses_like_be_payload(self):
        # BE(Jackson)가 보내는 camelCase JSON이 그대로 파싱되는지 — 계약 왕복 검증.
        payload = {
            "requestId": "req-9",
            "analysisId": 1,
            "drawingSessionId": 2,
            "analysisType": "FINAL",
            "subjectSummaries": [
                {
                    "drawingSubject": "TREE",
                    "drawingDescription": "나무 한 그루",
                    "detectedObjectCodes": ["TREE"],
                    "qaPairs": [
                        {
                            "question": "무슨 나무야?",
                            "answerText": "사과나무",
                            "answerType": "OPTION",
                        }
                    ],
                }
            ],
        }
        req = contracts.ObservationGenerationRequest.model_validate(payload)
        self.assertEqual(len(req.subject_summaries), 1)
        self.assertEqual(req.subject_summaries[0].drawing_subject, "TREE")
        self.assertEqual(req.subject_summaries[0].qa_pairs[0].answer_text, "사과나무")

    def test_old_be_payload_without_subject_summaries_still_parses(self):
        # 롤아웃 호환: 구 BE 요청(필드 부재)이 깨지지 않는다.
        payload = {
            "requestId": "req-8",
            "analysisId": 1,
            "drawingSessionId": 2,
            "analysisType": "FINAL",
        }
        req = contracts.ObservationGenerationRequest.model_validate(payload)
        self.assertEqual(req.subject_summaries, [])


class RagInjectionTest(unittest.TestCase):
    """RAG 근거 주입·출처 반환 (S15P11B209-614) — retrieve는 mock, GMS 미의존."""

    def _generate(self, req, *, chunks=None, unavailable=False, **kwargs):
        captured = {}

        def fake_create(*, model, messages, **_kwargs):
            captured["messages"] = messages
            return _fake_response(_llm_json())

        fake_client = mock.Mock()
        fake_client.chat.completions.create.side_effect = fake_create

        if unavailable:
            retrieve_patch = mock.patch.object(
                report_client,
                "retrieve",
                side_effect=report_client.RagUnavailableError("인덱스 없음"),
            )
        else:
            retrieve_patch = mock.patch.object(
                report_client, "retrieve", return_value=chunks or []
            )
        kb_patch = mock.patch.object(
            report_client, "rag_knowledge_base_version", return_value="kb-2026.07-1"
        )
        with retrieve_patch, kb_patch, mock.patch.object(
            report_client, "get_client", return_value=fake_client
        ):
            result = report_client.generate(req, model="m", **kwargs)
        return result, captured["messages"][1]["content"]

    @staticmethod
    def _chunks():
        from rag import Chunk

        return [
            Chunk(
                chunk_id="kicce-mr2303#0",
                source_id="kicce-mr2303",
                title="아동 사회·정서 발달지원",
                text="이 연령대 아이들은 그림으로 감정을 표현하는 것이 자연스럽습니다.",
                score=0.8,
            ),
            Chunk(
                chunk_id="kicce-mr2303#4",
                source_id="kicce-mr2303",  # 같은 자료의 다른 청크 — 출처는 1건으로 dedupe
                title="아동 사회·정서 발달지원",
                text="놀이와 그리기는 정서 표현의 통로입니다.",
                score=0.7,
            ),
        ]

    def test_chunks_injected_into_prompt_and_sources_returned(self):
        # 관찰 재료(서술)가 있어야 검색이 성립한다 — _build_rag_query 규칙과 정합.
        result, user_msg = self._generate(
            _htp_request(),
            chunks=self._chunks(),
            drawing_description="집이 크게 그려져 있어요.",
        )
        self.assertIn("[전문 자료 근거]", user_msg)
        self.assertIn("감정을 표현하는 것이 자연스럽습니다", user_msg)
        # 출처는 자료 단위 dedupe — 청크 2개, 참조 1건.
        self.assertEqual(len(result.rag_references), 1)
        self.assertEqual(result.rag_references[0].source_id, "kicce-mr2303")
        self.assertEqual(result.knowledge_base_version, "kb-2026.07-1")

    def test_unavailable_rag_degrades_not_blocks(self):
        # 인덱스 미배포·임베딩 실패 → 리포트는 그대로 생성, RAG 필드는 비움(기존 응답과 동일).
        result, user_msg = self._generate(_htp_request(), unavailable=True)
        self.assertNotIn("[전문 자료 근거]", user_msg)
        self.assertEqual(result.rag_references, [])
        self.assertIsNone(result.knowledge_base_version)
        self.assertIn("즐겁게", result.observation_draft.overall_summary)

    def test_empty_chunks_omit_block_and_kb_version(self):
        # 검색은 됐지만 임계값 미달(빈 목록) — 근거를 안 썼으므로 KB Version도 싣지 않는다.
        result, user_msg = self._generate(_htp_request(), chunks=[])
        self.assertNotIn("[전문 자료 근거]", user_msg)
        self.assertIsNone(result.knowledge_base_version)

    def test_query_excludes_child_utterances(self):
        # 질의는 관찰 서술·객체·선택 감정로만 — 아이 발화(답변·대표 발화)는 GMS로 안 나간다(정책 §1-1).
        req = _sample_request(
            representative_utterance="우리 엄마가 만든 김밥이 최고야",
            subject_summaries=[
                contracts.SubjectSummary(
                    drawing_subject="HOUSE",
                    drawing_description="집이 크게 그려져 있어요.",
                    detected_object_codes=["HOUSE"],
                    qa_pairs=[
                        contracts.SubjectQaPair(
                            question="누구랑 살아?", answer_text="비밀 발화 내용"
                        )
                    ],
                )
            ],
        )
        query = report_client._build_rag_query(req, None)
        self.assertIn("집이 크게 그려져 있어요.", query)
        self.assertIn("HOUSE", query)
        self.assertNotIn("비밀 발화 내용", query)
        self.assertNotIn("김밥", query)

    def test_no_query_material_skips_search(self):
        # 서술·객체·감정이 전부 없으면 임베딩 호출 자체를 하지 않는다.
        req = _sample_request(selected_emotions=[], subject_summaries=[])
        with mock.patch.object(report_client, "retrieve") as retrieve_spy:
            chunks, reason = report_client._search_rag(req, None)
        self.assertEqual(chunks, [])
        self.assertEqual(reason, "RAG_NO_QUERY")
        retrieve_spy.assert_not_called()


class RagSkippedReasonTest(unittest.TestCase):
    """근거를 싣지 못한 사유 코드 (S15P11B209-615) — 실패 종류별 표기와 응답 반영."""

    def _req_with_material(self):
        return _sample_request(
            subject_summaries=[
                contracts.SubjectSummary(
                    drawing_subject="HOUSE", drawing_description="집이 크게."
                )
            ]
        )

    def test_no_index_maps_to_rag_no_index(self):
        from rag import RagUnavailableError

        with mock.patch.object(
            report_client,
            "retrieve",
            side_effect=RagUnavailableError("미배포", reason="NO_INDEX"),
        ):
            chunks, reason = report_client._search_rag(self._req_with_material(), None)
        self.assertEqual((chunks, reason), ([], "RAG_NO_INDEX"))

    def test_search_failure_maps_to_rag_unavailable(self):
        from rag import RagUnavailableError

        with mock.patch.object(
            report_client,
            "retrieve",
            side_effect=RagUnavailableError("GMS 실패", reason="SEARCH_FAILED"),
        ):
            chunks, reason = report_client._search_rag(self._req_with_material(), None)
        self.assertEqual((chunks, reason), ([], "RAG_UNAVAILABLE"))

    def test_empty_results_map_to_low_score(self):
        with mock.patch.object(report_client, "retrieve", return_value=[]):
            chunks, reason = report_client._search_rag(self._req_with_material(), None)
        self.assertEqual((chunks, reason), ([], "RAG_LOW_SCORE"))

    def test_success_has_no_reason(self):
        from rag import Chunk

        chunk = Chunk(
            chunk_id="s#0", source_id="s", title="제목", text="본문", score=0.9
        )
        with mock.patch.object(report_client, "retrieve", return_value=[chunk]):
            chunks, reason = report_client._search_rag(self._req_with_material(), None)
        self.assertEqual(len(chunks), 1)
        self.assertIsNone(reason)

    def test_reason_lands_in_response(self):
        # 사유가 응답(ragSkippedReason)까지 흐르는지 — 미배포 시나리오로 종단 확인.
        from rag import RagUnavailableError

        def fake_create(*, model, messages, **_kwargs):
            return _fake_response(_llm_json())

        fake_client = mock.Mock()
        fake_client.chat.completions.create.side_effect = fake_create
        with mock.patch.object(
            report_client,
            "retrieve",
            side_effect=RagUnavailableError("미배포", reason="NO_INDEX"),
        ), mock.patch.object(report_client, "get_client", return_value=fake_client):
            result = report_client.generate(self._req_with_material(), model="m")
        self.assertEqual(result.rag_skipped_reason, "RAG_NO_INDEX")
        self.assertEqual(result.rag_references, [])
        self.assertIsNone(result.knowledge_base_version)

    def test_success_response_has_null_reason(self):
        from rag import Chunk

        chunk = Chunk(
            chunk_id="s#0", source_id="s", title="제목", text="본문", score=0.9
        )

        def fake_create(*, model, messages, **_kwargs):
            return _fake_response(_llm_json())

        fake_client = mock.Mock()
        fake_client.chat.completions.create.side_effect = fake_create
        with mock.patch.object(
            report_client, "retrieve", return_value=[chunk]
        ), mock.patch.object(
            report_client, "rag_knowledge_base_version", return_value="kb-2026.07-1"
        ), mock.patch.object(report_client, "get_client", return_value=fake_client):
            result = report_client.generate(self._req_with_material(), model="m")
        self.assertIsNone(result.rag_skipped_reason)
        self.assertEqual(len(result.rag_references), 1)


class ActivityPromptSplitTest(unittest.TestCase):
    """리포트 프롬프트 HTP/그림일기 분리 — 근거 화이트리스트·RAG 적용 범위."""

    def _generate(self, req):
        """generate()를 돌리고 (결과, system 프롬프트, retrieve 스파이)를 돌려준다."""
        fake_client = mock.Mock()
        fake_client.chat.completions.create.return_value = _fake_response(_llm_json())
        with mock.patch.object(
            report_client, "retrieve", return_value=[]
        ) as retrieve_spy, mock.patch.object(
            report_client, "get_client", return_value=fake_client
        ):
            result = report_client.generate(req, model="m")
        system = fake_client.chat.completions.create.call_args.kwargs["messages"][0]
        return result, system["content"], retrieve_spy

    def test_htp_request_selects_htp_prompt(self):
        _, system, _ = self._generate(_htp_request())
        self.assertIn("HTP(집·나무·사람)", system)
        self.assertNotIn("그림일기", system)

    def test_diary_request_selects_diary_prompt(self):
        # drawingSubject가 없는 subject_summaries = 그림일기 1건.
        req = _sample_request(
            subject_summaries=[
                contracts.SubjectSummary(drawing_description="하늘을 파랗게 칠했어요.")
            ]
        )
        _, system, _ = self._generate(req)
        self.assertIn("그림일기", system)
        self.assertNotIn("HTP(집·나무·사람)", system)

    def test_legacy_request_without_summaries_uses_diary_prompt(self):
        # 구 BE(subject_summaries 미전달)도 '단일 그림 + RAG 없음' 경로라 그림일기 쪽이 맞다.
        _, system, _ = self._generate(_sample_request())
        self.assertIn("그림일기", system)

    def test_both_variants_carry_common_rules_and_schema(self):
        for req in (_htp_request(), _sample_request()):
            _, system, _ = self._generate(req)
            # 공통부(report_common)가 뒤에 이어붙는다 — 사실/해석 분리와 출력 스키마.
            self.assertIn("관찰 '사실'과 AI '해석'을 분리한다", system)
            self.assertIn('"overallSummary"', system)
            self.assertIn('"visibilityScope"', system)
            # 출력 형식이 프롬프트 맨 끝에 오는지(모델이 형식을 놓치지 않게).
            self.assertGreater(system.index("출력 형식:"), system.index("근거 범위"))

    def test_whitelist_names_every_block_that_is_actually_injected(self):
        """근거 화이트리스트 누락 회귀 — 구 report.txt가 주제별 블록·RAG를 빠뜨렸다.

        '~만 근거로 삼는다'는 화이트리스트라, 실제 주입되는 블록이 목록에 없으면
        모델이 그 블록을 버린다(RAG 무력화·HTP 그림 내용 누락).
        """
        _, htp_system, _ = self._generate(_htp_request())
        for block in ("[집 그림 관찰]", "[형식적 분석]", "[전문 자료 근거]", "[활동 데이터]"):
            self.assertIn(block, htp_system)

        _, diary_system, _ = self._generate(_sample_request())
        for block in ("[그림 관찰]", "[형식적 분석]", "[활동 데이터]"):
            self.assertIn(block, diary_system)
        # 그림일기 프롬프트는 RAG 블록을 근거로 두지 않는다(검색도 하지 않으므로).
        self.assertNotIn("[전문 자료 근거]", diary_system)

    def test_diary_skips_rag_search_entirely(self):
        result, _, retrieve_spy = self._generate(_sample_request())
        retrieve_spy.assert_not_called()
        self.assertEqual(result.rag_skipped_reason, report_client.RAG_NOT_APPLICABLE)
        self.assertEqual(result.rag_references, [])
        self.assertIsNone(result.knowledge_base_version)

    def test_htp_still_searches_rag(self):
        _, _, retrieve_spy = self._generate(_htp_request())
        retrieve_spy.assert_called_once()


class ReportCommonContradictionTest(unittest.TestCase):
    """report_common.txt 안에서 같은 내용에 두 지시가 갈리지 않는지 (S15P11B209-788 E·F).

    프롬프트 '문구'를 직접 본다 — 여기서 고친 것은 모델에게 주는 지시의 일관성이고,
    조립·호출 경로는 ActivityPromptSplitTest가 이미 덮는다.
    """

    def setUp(self):
        import prompts_registry

        self.text = prompts_registry.load("report_common")

    # ── E: 걱정 신호 배출구 ──
    def test_two_expert_channels_are_defined_with_distinct_roles(self):
        self.assertIn("전문가 채널 두 곳", self.text)
        self.assertIn("같은 내용을 양쪽에 중복해 적지 마", self.text)
        # 관찰 카드 = EXPERT_ONLY feature / 추가 확인 지점 = attentionPoints
        self.assertIn("관찰 카드", self.text)
        self.assertIn("무엇을 더 확인하면 좋을지", self.text)

    def test_attention_points_is_no_longer_the_only_outlet(self):
        """구 문구는 걱정 신호를 attentionPoints '로만' 옮기라고 해서, 코드가 전제하는
        EXPERT_ONLY feature 경로(report_client._feature 강등 로직)와 어긋났다."""
        self.assertNotIn("attentionPoints(전문가용)로만 옮긴다", self.text)
        self.assertNotIn("관찰된 사실만 attentionPoints(전문가용)로 옮긴다", self.text)

    def test_expert_only_channel_matches_code_behaviour(self):
        # 코드가 실제로 EXPERT_ONLY feature 경로를 갖고 있다(프롬프트가 그걸 부정하면 안 된다).
        self.assertIn("EXPERT_ONLY", report_client._VALID_SCOPES)
        self.assertIn('features 의 EXPERT_ONLY 항목', self.text)

    def test_attention_points_is_not_a_summary_of_cards(self):
        self.assertIn("EXPERT_ONLY 관찰 카드를 다시 요약하지 마", self.text)

    # ── F: 형식적 분석 수치의 자리 ──
    def test_metric_facts_and_emotion_link_have_separate_homes(self):
        """구 문구는 수치를 evidenceSummary에 넣고 거기서 감정과 '연결'하라고 했는데,
        같은 파일의 사실/해석 분리 원칙은 evidenceSummary에 감정 판단을 금지한다."""
        self.assertIn("수치와 감정을 잇는 문장은 '해석'이라 자리가 다르다", self.text)
        self.assertIn("evidenceSummary 에는 수치만 남기고", self.text)
        # 사실/해석 분리 원칙은 그대로 살아 있어야 한다.
        self.assertIn("감정 판단·심리 해석(\"안정감을 느낀다\" 등)을 절대 넣지 마", self.text)

    def test_metric_link_instruction_appears_before_fact_split_principle(self):
        # 앞에 오는 지시가 뒤의 원칙과 어긋나면 모델이 어느 쪽을 따를지 알 수 없다 —
        # 이제 앞쪽이 뒤쪽 원칙을 가리킨다.
        self.assertIn("아래 사실/해석 분리 원칙", self.text)
        self.assertLess(
            self.text.index("아래 사실/해석 분리 원칙"),
            self.text.index("관찰 '사실'과 AI '해석'을 분리한다"),
        )

    def test_emotion_inference_requires_multiple_aligned_signals(self):
        """그림·필압 기반 추론은 허용하되, 단일 신호 억측과 성격 일반화는 막는다."""
        self.assertIn("단일 신호만으로 감정을 추론하지 마", self.text)
        self.assertIn("독립적인 관찰 신호가 두 가지 이상", self.text)
        self.assertIn("신호가 엇갈리거나 근거가 약하면 감정을 추론하지 않는다", self.text)
        self.assertIn("이번 활동에서는", self.text)
        self.assertIn("평소 마음·성격·발달 상태로 넓히지 않는다", self.text)


class ReportContractAlignmentTest(unittest.TestCase):
    """프롬프트가 BE 수신·화면 도달 실태와 맞는지 (S15P11B209-826).

    구 문구는 "각 필드가 화면에서 쓰이는 자리"로 7항목을 열거했는데 4.5개가 거짓이었다.
    모델이 그 맥락을 믿고 화면에 안 나가는 필드에 공을 들이고, 정작 보호자 조언 영역
    전부인 followUpGuides는 강조 없이 스키마 맨 끝에 있었다(818 근인 후보).
    """

    def setUp(self):
        self.text = prompts_registry.load("report_common")

    # ── 3. 렌더링 설명이 사실과 맞는가 ──
    def test_guardian_facing_fields_are_named_exactly(self):
        """보호자 화면에 실제로 도달하는 셋만 [1]로 분류돼야 한다.

        경로: ReportDetailQueryService → ReportDetailResponse → report_screen.dart.
        그 서비스에는 observedFeature·guardianQuestion·observationResult 저장소가
        주입되지 않는다 — 읽기 경로 부재의 확정 증거다.
        """
        section = self.text.split("[1]", 1)[1].split("[2]", 1)[0]
        for field in ("activityNotes", "conversationSummary.summaryText", "guidance"):
            self.assertIn(field, section)
        # 전문가 계층 필드가 '보호자 화면' 칸에 섞이면 안 된다.
        for field in ("overallSummary", "positiveSignals", "features", "attentionPoints"):
            self.assertNotIn(field, section)

    def test_expert_only_fields_are_not_claimed_as_guardian_screen(self):
        """§13.1은 AI 관찰 초안을 ExpertReviewMaterial 계층에 둔다(REPORT-03 미구현)."""
        self.assertNotIn("리포트 맨 위 전체 요약", self.text)
        self.assertNotIn("'아이의 좋은 모습' 영역", self.text)
        self.assertNotIn("'관찰된 특징' 카드 목록", self.text)
        # 대신 '전문가 검토용으로만 저장' 갈래로 옮겨졌다.
        expert = self.text.split("[2]", 1)[1].split("[3]", 1)[0]
        for field in ("overallSummary", "positiveSignals", "features", "attentionPoints"):
            self.assertIn(field, expert)

    def test_unused_fields_are_marked_as_such(self):
        unused = self.text.split("[3]", 1)[1].split("어느 갈래든", 1)[0]
        for field in ("detailText", "guardianQuestions", "mainTopic", "expressedEmotion"):
            self.assertIn(field, unused)

    def test_screen_section_title_matches_the_frontend(self):
        """FE 섹션 제목은 '이런 질문으로 대화해 보세요'다 — 구 문구의 '집에서 이렇게 해보세요'가 아니다."""
        self.assertIn("이런 질문으로 대화해 보세요", self.text)
        self.assertNotIn("'집에서 이렇게 해보세요' 안내와 질문", self.text)

    def test_follow_up_guides_are_question_first_with_one_attitude_slot(self):
        self.assertIn("그대로 물어볼 수 있는 질문을 앞에 둔다", self.text)
        self.assertIn("마지막 1개는 질문 대신 듣는 태도 안내로 써도 좋다", self.text)

    # ── 1. NOT NULL 필드가 필수로 표시되는가 ──
    def test_not_null_fields_are_marked_required(self):
        """BE 컬럼이 NOT NULL인데 프롬프트에 표시가 없었다.

        지금 예외가 안 나는 이유는 report_client._assemble이 빈 문자열을 채우기 때문이고,
        BE는 saveActivityNotes만 blank를 스킵한다 — 나머지는 빈 행이 저장돼 화면에
        빈 불릿으로 나간다.
        """
        self.assertIn("비어 있으면 안 된다", self.text)
        for field in ("followUpGuides", "questionText", "description", "visibilityScope"):
            self.assertIn(field, self.text)
        self.assertIn("비워 두지 마라", self.text)

    # ── 2. 조용히 잘리는 길이 상한이 명시되는가 ──
    def test_silent_truncation_limits_are_stated_as_numbers(self):
        """ColumnTextLimiter.fit은 초과분을 잘라내고 log.warn만 남긴다(조용한 절단)."""
        for limit in ("50자", "100자", "80자", "200자"):
            self.assertIn(limit, self.text)
        self.assertIn("말없이 잘라내", self.text)

    def test_limits_match_backend_column_constants(self):
        """BE ObservationReportPersistenceService의 *_LIMIT 값과 어긋나면 안 된다.

        어긋나면 프롬프트가 허용한 길이가 조용히 잘린다 — 두 벌을 따로 관리하는 함정이라
        값이 바뀌면 이 테스트가 먼저 깨지도록 둔다.
        """
        expected = {
            "expressedEmotion": "50자",  # EXPRESSED_EMOTION_LIMIT
            "mainTopic": "100자",  # MAIN_TOPIC_LIMIT
            "questionPurpose": "50자",  # QUESTION_PURPOSE_LIMIT
            "featureCode": "80자",  # FEATURE_CODE_LIMIT
            "title": "200자",  # FEATURE_TITLE_LIMIT
        }
        block = self.text.split("길이 상한", 1)[1].split("{", 1)[0]
        for field, limit in expected.items():
            with self.subTest(field=field):
                self.assertRegex(block + self.text, rf"{field}[^\n]*{limit}|{limit}[^\n]*{field}")


class RoutingSingleOwnerTest(unittest.TestCase):
    """표시 위치를 [1]/[2]/[3] 절만 말하는지 (S15P11B209-871).

    826이 라우팅을 재정의한 뒤 845가 "우려 소견도 보호자에게 보낸다"를 추가해, 같은 파일이
    features 에 대해 '보호자에게 보낸다'와 '보호자 화면에 안 나간다'를 동시에 말했다.
    스키마 설명도 826 이전의 "보호자에게 노출 가능한" 문구를 그대로 달고 있었다.
    소유자를 한 곳으로 못박아, 다음 수정자가 다른 구역에 목적지를 또 쓰지 않게 한다.
    """

    def setUp(self):
        self.text = prompts_registry.load("report_common")
        self.schema = self.text[self.text.index("{\n  \"overallSummary\"") :]

    def test_routing_ownership_is_declared(self):
        head = self.text.split("[1]", 1)[0]
        self.assertIn("이 절에서만", head)
        self.assertIn("표시 위치는 다시 적지 않는다", head)

    def test_schema_descriptions_make_no_display_claims(self):
        """스키마 설명이 목적지를 말하면 [1]/[2]/[3]과 어긋날 수 있다 — 아예 말하지 않는다."""
        for claim in ("보호자 화면", "노출 가능", "전문가 검토용", "화면에 안 나감"):
            self.assertNotIn(claim, self.schema, f"스키마 설명에 표시 위치 주장: {claim}")

    def test_expert_tier_fields_are_not_promised_to_guardian(self):
        """845 회귀 — features 를 '보호자에게 보낸다'고 말하면 [2]와 정면 충돌한다."""
        self.assertNotIn("이 조건을 갖추면 보호자에게 보낸다", self.text)
        self.assertNotIn("근거가 분명하면 보호자에게 전할 수 있고", self.text)

    def test_concerning_findings_have_a_named_destination(self):
        """'보호자에게 전할 수 있다'고만 하면 담을 자리가 없다 — 필드를 지목해야 한다."""
        rule = self.text.split("걱정되는 점이 보이면", 1)[1].split("\n-", 1)[0]
        self.assertIn("features", rule)
        self.assertIn("REVIEWED_GUARDIAN", rule)

    def test_visibility_scope_is_described_as_classification(self):
        """지금은 어느 쪽이든 보호자 화면에 안 나간다 — '분류'지 '노출 전환'이 아니다."""
        expert = self.text.split("[2]", 1)[1].split("[3]", 1)[0]
        self.assertIn("visibilityScope", expert)
        self.assertIn("분류값", expert)

    def test_activity_notes_count_floor_is_stated(self):
        """스키마에서 '불릿' 표시를 걷어내자 activityNotes 가 평균 2.67 → 1.00 으로 줄었다.

        표시 위치 주장 없이 개수 신호를 살리려면 개수를 소유한 출력 형식 절이 하한을 말해야
        한다. 이 줄이 빠지면 보호자 '활동 기록' 카드가 한 줄짜리가 된다(실측 회귀).
        """
        self.assertIn("activityNotes 는 **2~3개**를 채운다(3개를 넘기지 마)", self.text)


if __name__ == "__main__":
    unittest.main()
