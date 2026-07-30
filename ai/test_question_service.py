"""question_service 단위 테스트 — 첫 질문 고정 현상 제거·컨텍스트 기반 생성 (S15P11B209-589).

GMS를 가짜로 대체해(네트워크·과금 없이) 내부 계약 질문 생성이
- 탐지 객체·대화 문맥을 프롬프트에 반영하는지(더 이상 무맥락 고정 프롬프트가 아님)
- 첫 질문 vs 다음 질문을 문맥으로 구분하는지
- 난이도별 말투 지침을 덧붙이는지
- 계약 응답을 조립하는지(promptVersion이 placeholder가 아님)
를 검증한다.
"""

from __future__ import annotations

import types
import unittest
from unittest import mock

import child_screen_guard
import config
import crisis_guidance
import llm_client
import question_safety
import question_service
from pydantic import ValidationError

from internal_contracts import (
    BoundingBox,
    DetectedObject,
    QuestionRequest,
    RecentMessage,
)


def _fake_response(text: str, *, model: str = "gpt-4o-mini-2024-07-18"):
    message = types.SimpleNamespace(content=text)
    choice = types.SimpleNamespace(message=message)
    return types.SimpleNamespace(choices=[choice], model=model)


def _mock_client(capture: dict, *, reply: str = "이 집에는 누가 살고 있어?"):
    def fake_create(*, model, messages, **_kwargs):
        capture["messages"] = messages
        capture["system"] = messages[0]["content"]
        return _fake_response(reply)

    client = mock.Mock()
    client.chat.completions.create.side_effect = fake_create
    # question_service는 get_client().with_options(...)로 옵션만 덧씌운다 — 같은 클라이언트 반환.
    client.with_options.return_value = client
    return client


def _detected(object_code="HOUSE", object_name="집전체", confidence=0.95):
    return DetectedObject(
        object_code=object_code,
        object_name=object_name,
        confidence=confidence,
        bounding_box=BoundingBox(x=0.1, y=0.1, width=0.4, height=0.4),
    )


def _request(**overrides) -> QuestionRequest:
    base = {
        "conversation_id": 1,
        "drawing_session_id": 2,
        "child_age": 6,
        "difficulty": "PRESCHOOL",
        "allowed_response_modes": ["VOICE"],
        "current_question_count": 0,
        "max_question_count": 5,
        "detected_objects": [_detected()],
        "recent_messages": [],
        "safety_rule_version": "safety-2026-07",
    }
    base.update(overrides)
    return QuestionRequest(**base)


class BuildMessagesTest(unittest.TestCase):
    def test_recent_message_accepts_optional_selected_option_codes(self):
        selected = RecentMessage.model_validate(
            {
                "messageId": 102,
                "senderType": "CHILD",
                "messageType": "OPTION_ANSWER",
                "text": "음, 아니야",
                "selectedOptionCodes": ["CHIP_NO"],
            }
        )
        legacy = RecentMessage.model_validate(
            {
                "messageId": 101,
                "senderType": "CHILD",
                "messageType": "VOICE_ANSWER",
                "text": "강아지야",
            }
        )

        self.assertEqual(selected.selected_option_codes, ["CHIP_NO"])
        self.assertIsNone(legacy.selected_option_codes)

    def test_first_question_uses_detected_objects_context(self):
        system = question_service._build_messages(_request())[0]["content"]
        self.assertIn("집전체", system)  # 탐지 객체가 그림 분석 근거로 들어감
        # 예전 고정 문구는 더 이상 쓰지 않는다(첫 질문 고정 현상 제거).
        self.assertNotIn("아이가 방금 그림을 그렸어요. 첫 질문을 해주세요", system)

    def test_first_question_without_objects_uses_placeholder(self):
        system = question_service._build_messages(_request(detected_objects=[]))[0][
            "content"
        ]
        self.assertIn(llm_client.NO_ANALYSIS, system)

    def test_difficulty_rules_block_is_appended(self):
        system = question_service._build_messages(_request(difficulty="PRESCHOOL"))[0][
            "content"
        ]
        self.assertIn("[연령별 말하기 규칙]", system)
        rule = question_service._DIFFICULTY_RULES["PRESCHOOL"]
        self.assertIn(rule["length"], system)
        self.assertIn(rule["vocabulary"], system)
        self.assertIn(rule["tone"], system)

    # ── 그림 서술(VLM) 전달 — S15P11B209-704 ──────────────────────────────
    def test_drawing_description_reaches_the_prompt(self):
        """서술이 있으면 프롬프트에 들어간다. 색·표정 질문이 가능해지는 근거다."""
        system = question_service._build_messages(
            _request(drawing_description="하늘을 검게 칠했고 사람이 활짝 웃고 있어요.")
        )[0]["content"]
        self.assertIn("하늘을 검게 칠했고", system)
        self.assertIn("활짝 웃고", system)

    def test_description_and_objects_are_both_kept(self):
        """서술이 객체 목록을 대체하지 않는다 — 서로 보완한다."""
        system = question_service._build_messages(
            _request(drawing_description="큰 집 옆에 나무가 있어요.")
        )[0]["content"]
        self.assertIn("큰 집 옆에", system)
        self.assertIn("집전체", system)  # 탐지 객체도 그대로 남는다

    def test_missing_description_keeps_object_only_behaviour(self):
        """BE가 서술을 안 보내면(분석 실패·구버전) 기존 동작 그대로."""
        system = question_service._build_messages(_request(drawing_description=None))[0][
            "content"
        ]
        self.assertIn("집전체", system)

    def test_no_description_and_no_objects_falls_back_to_placeholder(self):
        system = question_service._build_messages(
            _request(detected_objects=[], drawing_description=None)
        )[0]["content"]
        self.assertIn(llm_client.NO_ANALYSIS, system)

    def test_blank_description_is_treated_as_absent(self):
        """공백만 있는 서술이 빈 [그림 분석 결과] 절을 만들지 않게 한다."""
        self.assertIsNone(question_service._truncate_description("   "))
        self.assertIsNone(question_service._truncate_description(""))

    def test_long_description_is_truncated_with_ellipsis(self):
        """상한 초과 시 자르고, 잘랐다는 사실을 말줄임표로 남긴다."""
        limit = config.QUESTION_DESCRIPTION_MAX_CHARS
        cut = question_service._truncate_description("가" * (limit + 50))
        self.assertEqual(len(cut), limit + 1)  # 본문 limit + 말줄임표 1
        self.assertTrue(cut.endswith("…"))

    def test_prompt_forbids_quoting_the_description_verbatim(self):
        """서술을 그대로 읽어주지 말라는 지시가 프롬프트에 있어야 한다.

        이게 빠지면 VLM 서술 문장이 아이에게 그대로 나간다 — 진단형 표현이 섞여
        있으면 아이가 그것을 듣게 된다(CLAUDE.md 9절).
        """
        system = question_service._build_messages(
            _request(drawing_description="집이 있어요.")
        )[0]["content"]
        self.assertIn("참고 자료", system)
        self.assertIn("그대로", system)

    def test_description_detail_is_not_logged_when_detail_off(self):
        """상세 로그가 꺼져 있으면 서술 내용은 남기지 않되 존재 사실은 남긴다."""
        req = _request(drawing_description="아이가 검은 하늘을 그렸어요.")
        with mock.patch.object(config, "DETECTION_LOG_DETAIL", False):
            line = question_service._format_objects_for_log(req)
        self.assertNotIn("검은 하늘", line)
        self.assertIn("서술있음", line)

    def test_each_difficulty_injects_its_own_rules(self):
        for difficulty, rule in question_service._DIFFICULTY_RULES.items():
            with self.subTest(difficulty=difficulty):
                system = question_service._build_messages(_request(difficulty=difficulty))[
                    0
                ]["content"]
                self.assertIn(rule["length"], system)
                self.assertIn(rule["tone"], system)

    def test_unknown_difficulty_falls_back_to_lower_elementary(self):
        # 계약상 검증되지만 방어적으로 — 알 수 없는 값이면 저학년 규칙을 쓴다.
        # _difficulty_guidance는 .difficulty만 읽으므로 가짜 객체로 경계 조건을 검증한다.
        fake = types.SimpleNamespace(difficulty="UNKNOWN_LEVEL")
        guidance = question_service._difficulty_guidance(fake)
        self.assertIn(
            question_service._DIFFICULTY_RULES["LOWER_ELEMENTARY"]["length"], guidance
        )

    def test_internal_contract_has_no_child_name(self):
        # 개인정보 최소화 — 이름 슬롯은 항상 "너"(대체 문구)로 채워진다.
        system = question_service._build_messages(_request())[0]["content"]
        self.assertIn(llm_client.NO_CHILD_NAME, system)

    def test_followup_uses_last_child_utterance_and_history(self):
        req = _request(
            recent_messages=[
                RecentMessage(sender_type="AI", message_type="QUESTION", text="이 집에는 누가 살아?"),
                RecentMessage(sender_type="CHILD", message_type="VOICE_ANSWER", text="엄마랑 나 살아."),
            ]
        )
        system = question_service._build_messages(req)[0]["content"]
        self.assertIn("엄마랑 나 살아.", system)  # 마지막 아이 발화
        self.assertIn("이 집에는 누가 살아?", system)  # 이전 이력


class GenerateTest(unittest.TestCase):
    def test_generate_builds_context_based_contract_response(self):
        capture: dict = {}
        client = _mock_client(capture, reply="이 집은 어떤 집이야?")
        with mock.patch.object(question_service, "get_client", return_value=client):
            resp = question_service.generate(_request(), "req-1")

        self.assertEqual(resp.question_text, "이 집은 어떤 집이야?")
        # 첫 질문(아이 발화 없음) + 탐지 객체 있음 → OBJECT_DESCRIPTION
        self.assertEqual(resp.question_purpose, "OBJECT_DESCRIPTION")
        # placeholder 버전이 아니라 실제 프롬프트 버전을 쓴다.
        self.assertEqual(resp.prompt_version, llm_client.PROMPT_VERSION)
        self.assertNotEqual(resp.prompt_version, "placeholder-0")
        self.assertEqual(resp.safety_result.status, "PASSED")
        # 프롬프트에 탐지 객체 문맥이 실렸는지
        self.assertIn("집전체", capture["system"])

    def test_generate_options_null_when_option_not_allowed(self):
        capture: dict = {}
        client = _mock_client(capture, reply="이 집은 어떤 집이야?")
        with mock.patch.object(question_service, "get_client", return_value=client):
            resp = question_service.generate(
                _request(allowed_response_modes=["VOICE"]), "req-1"
            )
        # OPTION 비허용 → options는 null이어야 계약 통과
        self.assertIsNone(resp.options)


class QuestionInputLogTest(unittest.TestCase):
    """질문 재료 진단 로그 (S15P11B209-710).

    "LLM이 무엇을 보고 질문했는가"를 남긴다 — S15P11B209-709 계열 버그의 확정 증거다.
    생성된 질문 원문은 어느 모드에서도 남기지 않는다(가드레일).
    """

    REPLY = "이 집은 어떤 집이야?"

    def _generate_capturing_logs(self, detail: bool):
        client = _mock_client({}, reply=self.REPLY)
        with mock.patch.object(question_service.config, "DETECTION_LOG_DETAIL", detail):
            with mock.patch.object(
                question_service, "get_client", return_value=client
            ):
                with self.assertLogs("question_service", level="INFO") as logs:
                    question_service.generate(_request(), "req-log")
        return "\n".join(logs.output)

    def test_logs_purpose_target_and_prompt_objects(self):
        joined = self._generate_capturing_logs(detail=True)
        self.assertIn("[질문]", joined)
        self.assertIn("request_id=req-log", joined)
        self.assertIn("drawingSessionId=2", joined)
        self.assertIn("purpose=OBJECT_DESCRIPTION", joined)
        # 프롬프트에 실제로 들어간 이름이 그대로 보여야 원인 추적이 된다
        self.assertIn("집전체", joined)

    def test_only_counts_when_flag_off(self):
        joined = self._generate_capturing_logs(detail=False)
        self.assertIn("[질문]", joined)
        self.assertIn("purpose=OBJECT_DESCRIPTION", joined)
        self.assertIn("HOUSE", joined)  # 객체 코드는 내부 Enum이라 남긴다
        self.assertNotIn("집전체", joined)  # 그림 내용은 남기지 않는다

    def test_never_logs_generated_question_text(self):
        for detail in (False, True):
            joined = self._generate_capturing_logs(detail=detail)
            self.assertNotIn(self.REPLY, joined)


class SafetyPipelineTest(unittest.TestCase):
    """생성 질문 안전 판정 파이프라인 (S15P11B209-596)."""

    def test_generated_question_is_sanitized(self):
        # 내부 계약 경로도 이제 정화된 질문을 내보낸다(이모지·마크업 제거).
        capture: dict = {}
        client = _mock_client(capture, reply="**우와** 멋진 집이네! 누가 살아? 😊")
        with mock.patch.object(question_service, "get_client", return_value=client):
            resp = question_service.generate(_request(), "req-1")
        self.assertEqual(resp.safety_result.status, "PASSED")
        self.assertNotIn("😊", resp.question_text)
        self.assertNotIn("*", resp.question_text)
        self.assertIn("멋진 집이네", resp.question_text)

    def test_diagnostic_question_blocked_maps_to_422(self):
        capture: dict = {}
        client = _mock_client(capture, reply="이 그림은 불안을 의미하니?")
        with mock.patch.object(question_service, "get_client", return_value=client):
            with self.assertRaises(question_service.SafetyBlockedError) as ctx:
                question_service.generate(_request(), "req-1")
        self.assertEqual(
            ctx.exception.block_reason_code, question_safety.DIAGNOSTIC_LANGUAGE
        )
        self.assertEqual(ctx.exception.rule_version, "safety-2026-07")

    def test_crisis_content_question_blocked(self):
        capture: dict = {}
        client = _mock_client(capture, reply="혹시 죽고 싶었던 적 있어?")
        with mock.patch.object(question_service, "get_client", return_value=client):
            with self.assertRaises(question_service.SafetyBlockedError) as ctx:
                question_service.generate(_request(), "req-1")
        self.assertEqual(
            ctx.exception.block_reason_code, question_safety.CRISIS_CONTENT
        )

    def test_symbol_only_question_treated_as_empty(self):
        # 정화 후 남는 게 없으면 안전 차단이 아니라 빈 출력 → 폴백 경로(UpstreamError).
        capture: dict = {}
        client = _mock_client(capture, reply="🎨🌟")
        with mock.patch.object(question_service, "get_client", return_value=client):
            with self.assertRaises(question_service.UpstreamError) as ctx:
                question_service.generate(_request(), "req-1")
        self.assertEqual(ctx.exception.error_code, "AI_EMPTY_COMPLETION")

    def test_risk_notice_question_blocked(self):
        # 보호자용 위기 경고 문구가 질문에 섞이면 아이 화면에 못 나가게 차단(S15P11B209-597).
        capture: dict = {}
        client = _mock_client(capture, reply="위험이 감지되어 보호자에게 알렸어. 지금 기분은 어때?")
        with mock.patch.object(question_service, "get_client", return_value=client):
            with self.assertRaises(question_service.SafetyBlockedError) as ctx:
                question_service.generate(_request(), "req-1")
        self.assertEqual(
            ctx.exception.block_reason_code, question_safety.CHILD_UNSAFE_NOTICE
        )


class ChildScreenSafeConstantsTest(unittest.TestCase):
    """아이 화면에 그대로 나가는 서버 상수(위기 안전 질문·선택 칩)에 위험 문구가 없어야 한다
    (S15P11B209-597 회귀 방어 — 누군가 상수를 위험 문구로 바꾸면 즉시 실패)."""

    def test_crisis_safe_question_has_no_risk_notice(self):
        self.assertFalse(
            child_screen_guard.contains_child_unsafe(
                question_service.CRISIS_SAFE_QUESTION
            )
        )

    def test_all_option_chip_labels_have_no_risk_notice(self):
        chips = [
            opt
            for options in question_service._OPTIONS_BY_PURPOSE.values()
            for opt in options
        ]
        chips += list(question_service._CRISIS_SAFE_OPTIONS)
        for opt in chips:
            with self.subTest(label=opt.label):
                self.assertFalse(child_screen_guard.contains_child_unsafe(opt.label))


class DebugRawLogTest(unittest.TestCase):
    """임시 검증용 원문 디버그 로그 게이팅 (S15P11B209-689, 출시 전 제거 대상).

    기본(플래그 꺼짐)에서는 원문이 절대 로그에 새지 않아야 하고, 명시적으로 켰을 때만
    [SAFETY-DEBUG-REMOVE] 로그로 원문이 남는다.
    """

    RAW = "이 그림은 불안을 의미하니?"  # 진단 표현 → 차단 유발

    def _run_blocked(self):
        capture: dict = {}
        client = _mock_client(capture, reply=self.RAW)
        with mock.patch.object(question_service, "get_client", return_value=client):
            with self.assertRaises(question_service.SafetyBlockedError):
                question_service.generate(_request(), "req-dbg")

    def test_raw_not_logged_when_flag_off(self):
        with mock.patch.object(question_service.config, "SAFETY_DEBUG_LOG_RAW", False):
            with self.assertLogs("question_service", level="WARNING") as logs:
                self._run_blocked()
        joined = "\n".join(logs.output)
        self.assertNotIn("[SAFETY-DEBUG-REMOVE]", joined)
        self.assertNotIn(self.RAW, joined)  # 원문이 어떤 로그에도 새지 않는다

    def test_raw_logged_only_when_flag_on(self):
        with mock.patch.object(question_service.config, "SAFETY_DEBUG_LOG_RAW", True):
            with self.assertLogs("question_service", level="WARNING") as logs:
                self._run_blocked()
        joined = "\n".join(logs.output)
        self.assertIn("[SAFETY-DEBUG-REMOVE]", joined)
        self.assertIn(self.RAW, joined)  # 켰을 때만 원문 확인 가능


class PurposeTargetChipConsistencyTest(unittest.TestCase):
    """목적·대상 객체·선택 Chip 정합성 (S15P11B209-594)."""

    def _generate(self, req):
        capture: dict = {}
        client = _mock_client(capture, reply="이 집은 어떤 집이야?")
        with mock.patch.object(question_service, "get_client", return_value=client):
            return question_service.generate(req, "req-1")

    def test_object_description_carries_target_and_object_chips(self):
        # 첫 질문 + 탐지 객체 + OPTION 허용 → 목적 OBJECT_DESCRIPTION, 대상 객체 있음, 객체용 칩.
        resp = self._generate(_request(allowed_response_modes=["OPTION"]))
        self.assertEqual(resp.question_purpose, "OBJECT_DESCRIPTION")
        self.assertIsNotNone(resp.target_object)
        self.assertEqual(resp.target_object.object_code, "HOUSE")
        self.assertEqual(
            [o.code for o in resp.options],
            [o.code for o in question_service._OPTIONS_BY_PURPOSE["OBJECT_DESCRIPTION"]],
        )

    def test_followup_has_no_target_object(self):
        req = _request(
            allowed_response_modes=["OPTION"],
            recent_messages=[
                RecentMessage(sender_type="AI", message_type="QUESTION", text="이 집엔 누가 살아?"),
                RecentMessage(sender_type="CHILD", message_type="VOICE_ANSWER", text="엄마랑 나."),
            ],
        )
        resp = self._generate(req)
        self.assertEqual(resp.question_purpose, "FOLLOW_UP")
        # 대상 객체는 OBJECT_DESCRIPTION일 때만 — FOLLOW_UP엔 붙지 않는다.
        self.assertIsNone(resp.target_object)

    def test_drawing_context_when_no_objects(self):
        resp = self._generate(
            _request(allowed_response_modes=["OPTION"], detected_objects=[])
        )
        self.assertEqual(resp.question_purpose, "DRAWING_CONTEXT")
        self.assertIsNone(resp.target_object)
        self.assertEqual(
            [o.code for o in resp.options],
            [o.code for o in question_service._OPTIONS_BY_PURPOSE["DRAWING_CONTEXT"]],
        )

    def test_target_only_for_object_description(self):
        req = _request()  # 탐지 객체 있음
        self.assertIsNotNone(
            question_service._target_for_purpose(req, "OBJECT_DESCRIPTION")
        )
        for purpose in ("DRAWING_CONTEXT", "EXPRESSION", "FOLLOW_UP"):
            with self.subTest(purpose=purpose):
                self.assertIsNone(question_service._target_for_purpose(req, purpose))

    def test_is_consistent_rules(self):
        target = _detected()
        opts = question_service._OPTIONS_BY_PURPOSE["OBJECT_DESCRIPTION"]
        # 정상: OBJECT_DESCRIPTION + 대상 + 칩(OPTION 허용)
        self.assertTrue(
            question_service._is_consistent("OBJECT_DESCRIPTION", target, opts, True)
        )
        # 대상 객체가 OBJECT_DESCRIPTION이 아닌 목적에 붙으면 불일치
        self.assertFalse(
            question_service._is_consistent("FOLLOW_UP", target, opts, True)
        )
        # OPTION 허용인데 칩이 없으면 불일치
        self.assertFalse(
            question_service._is_consistent("FOLLOW_UP", None, None, True)
        )
        # OPTION 비허용인데 칩이 있으면 불일치
        self.assertFalse(
            question_service._is_consistent("FOLLOW_UP", None, opts, False)
        )
        # 계약에 없는 목적은 불일치
        self.assertFalse(
            question_service._is_consistent("UNKNOWN", None, None, False)
        )
        # 칩 code 중복이면 불일치
        dup = [
            question_service.QuestionOption(code="X", label="a"),
            question_service.QuestionOption(code="X", label="b"),
        ]
        self.assertFalse(
            question_service._is_consistent("FOLLOW_UP", None, dup, True)
        )

    def test_every_purpose_has_unique_chip_codes(self):
        for purpose, opts in question_service._OPTIONS_BY_PURPOSE.items():
            with self.subTest(purpose=purpose):
                codes = [o.code for o in opts]
                self.assertEqual(len(codes), len(set(codes)))
                self.assertTrue(all(o.code and o.label for o in opts))


class CrisisSafeResponseTest(unittest.TestCase):
    """자해·학대·위기 신호 → 차단이 아니라 안전·지지형 응답으로 지속 (S15P11B209-593)."""

    def _child(self, text):
        return RecentMessage(sender_type="CHILD", message_type="VOICE_ANSWER", text=text)

    def _generate(self, req):
        capture: dict = {}
        client = _mock_client(capture)
        with mock.patch.object(question_service, "get_client", return_value=client):
            with self.assertLogs("question_service", level="WARNING") as logs:
                resp = question_service.generate(req, "req-1")
        return resp, client, logs

    def test_crisis_returns_safe_response_without_calling_gms(self):
        req = _request(recent_messages=[self._child("나 그냥 죽고 싶어.")])
        resp, client, logs = self._generate(req)
        # 대화를 끊지 않고 안전·지지형 고정 응답을 돌려준다(차단 아님).
        self.assertEqual(resp.question_text, question_service.CRISIS_SAFE_QUESTION)
        self.assertEqual(resp.question_purpose, "EXPRESSION")
        self.assertIsNone(resp.target_object)
        self.assertEqual(resp.safety_result.status, "PASSED")
        # 위기 상황에선 GMS를 호출하지 않는다(잘못된 생성 방지).
        client.chat.completions.create.assert_not_called()
        # 위기 사실은 사유 코드로 서버 경보 로그에 남는다(원문 없이).
        self.assertTrue(any("SELF_HARM_RISK" in m for m in logs.output))

    def test_abuse_disclosure_also_continues_safely(self):
        req = _request(recent_messages=[self._child("아빠가 자꾸 때려서 무서워.")])
        resp, client, logs = self._generate(req)
        self.assertEqual(resp.question_text, question_service.CRISIS_SAFE_QUESTION)
        self.assertTrue(any("ABUSE_DISCLOSURE" in m for m in logs.output))

    def test_crisis_safe_response_has_option_chips_when_allowed(self):
        req = _request(
            allowed_response_modes=["OPTION"],
            recent_messages=[self._child("다 사라지고 싶어.")],
        )
        resp, _client, _logs = self._generate(req)
        self.assertEqual(
            [o.code for o in resp.options],
            [o.code for o in question_service._CRISIS_SAFE_OPTIONS],
        )

    def test_safe_child_talk_is_not_flagged(self):
        req = _request(recent_messages=[self._child("이 집에는 엄마랑 나랑 살아.")])
        capture: dict = {}
        client = _mock_client(capture, reply="엄마랑 뭐 하고 놀아?")
        with mock.patch.object(question_service, "get_client", return_value=client):
            resp = question_service.generate(req, "req-1")
        # 위기어가 없으면 평소대로 GMS 질문이 생성된다.
        self.assertEqual(resp.question_text, "엄마랑 뭐 하고 놀아?")
        client.chat.completions.create.assert_called_once()

    def test_ai_utterance_is_not_scanned_for_crisis(self):
        # 곰돌이(AI) 발화에 위기어가 있어도 검사 대상이 아니다 — 아이 발화만 본다.
        req = _request(
            recent_messages=[
                RecentMessage(
                    sender_type="AI", message_type="QUESTION", text="죽고 싶은 기분이 들 때가 있어?"
                )
            ]
        )
        self.assertIsNone(question_service._detect_crisis(req))

    def test_guardian_crisis_guidance_signal_is_logged(self):
        # 위기 감지 시 보호자 안내(심각도·사유)가 서버 신호로 남는다 — 원문 없이 (S15P11B209-598).
        # 임시 원문 디버그 로그(689)는 꺼둬 이 검증이 그 영향을 받지 않게 한다.
        req = _request(recent_messages=[self._child("나 그냥 죽고 싶어.")])
        with mock.patch.object(question_service.config, "SAFETY_DEBUG_LOG_RAW", False):
            _resp, _client, logs = self._generate(req)
        joined = "\n".join(logs.output)
        self.assertIn("보호자 위기 안내 준비", joined)
        self.assertIn(crisis_guidance.SEVERITY_HIGH, joined)
        # 안내 신호에도 아이 발화 원문은 남기지 않는다.
        self.assertNotIn("죽고 싶어", joined)


class SubjectContextContractTest(unittest.TestCase):
    """질문 요청 계약의 HTP 주제 맥락 필드 (S15P11B209-712).

    activityType·drawingSubject·askedObjectCodes를 수용하고, 활동 유형이 주어지면
    분석 경로와 같은 정합성 규칙을 적용한다. 실제 프롬프트 반영은 후속 713 몫이다.
    """

    def test_defaults_when_omitted(self):
        # 롤아웃 안전: 구 BE가 새 필드를 안 보내도 요청이 깨지지 않고 기본값을 쓴다.
        req = _request()
        self.assertIsNone(req.activity_type)
        self.assertIsNone(req.drawing_subject)
        self.assertEqual(req.asked_object_codes, [])

    def test_accepts_camelcase_aliases_from_be(self):
        # BE(Jackson) camelCase JSON을 그대로 수용해야 한다.
        req = QuestionRequest.model_validate(
            {
                "conversationId": 1,
                "drawingSessionId": 2,
                "childAge": 6,
                "difficulty": "PRESCHOOL",
                "allowedResponseModes": ["VOICE"],
                "currentQuestionCount": 0,
                "maxQuestionCount": 5,
                "safetyRuleVersion": "safety-2026-07",
                "activityType": "HTP",
                "drawingSubject": "TREE",
                "askedObjectCodes": ["TREE_TRUNK", "TREE_CROWN"],
            }
        )
        self.assertEqual(req.activity_type, "HTP")
        self.assertEqual(req.drawing_subject, "TREE")
        self.assertEqual(req.asked_object_codes, ["TREE_TRUNK", "TREE_CROWN"])

    def test_htp_with_subject_is_valid(self):
        req = _request(activity_type="HTP", drawing_subject="HOUSE")
        self.assertEqual(req.drawing_subject, "HOUSE")

    def test_htp_without_subject_is_rejected(self):
        # 분석 경로(AnalysisRequest)와 같은 규칙 — HTP인데 주제가 없으면 계약 위반.
        with self.assertRaises(ValidationError):
            _request(activity_type="HTP")

    def test_art_diary_with_subject_is_rejected(self):
        with self.assertRaises(ValidationError):
            _request(activity_type="ART_DIARY", drawing_subject="HOUSE")

    def test_art_diary_without_subject_is_valid(self):
        req = _request(activity_type="ART_DIARY")
        self.assertIsNone(req.drawing_subject)

    def test_absent_activity_type_skips_consistency_check(self):
        # activity_type이 없으면(구 BE) 주제 유무를 검사하지 않는다 — 롤아웃 호환.
        req = _request(drawing_subject=None)
        self.assertIsNone(req.activity_type)

    def test_unknown_subject_is_rejected(self):
        with self.assertRaises(ValidationError):
            _request(activity_type="HTP", drawing_subject="CASTLE")


class SubjectContextLogTest(unittest.TestCase):
    """진단 로그에 activityType·drawingSubject가 실리는지 (S15P11B209-712)."""

    def _logs_for(self, **overrides):
        client = _mock_client({}, reply="이 나무는 어떤 나무야?")
        with mock.patch.object(question_service, "get_client", return_value=client):
            with self.assertLogs("question_service", level="INFO") as logs:
                question_service.generate(_request(**overrides), "req-subj")
        return "\n".join(logs.output)

    def test_logs_activity_type_and_subject_when_present(self):
        joined = self._logs_for(activity_type="HTP", drawing_subject="TREE")
        self.assertIn("activityType=HTP", joined)
        self.assertIn("drawingSubject=TREE", joined)

    def test_logs_dash_when_subject_absent(self):
        joined = self._logs_for()
        self.assertIn("activityType=-", joined)
        self.assertIn("drawingSubject=-", joined)


class SubjectPromptAndTargetTest(unittest.TestCase):
    """HTP 주제 제약·대상 선택·반복 방지 (S15P11B209-713)."""

    def _htp(self, **overrides):
        base = {"activity_type": "HTP", "drawing_subject": "HOUSE"}
        base.update(overrides)
        return _request(**base)

    def test_target_prefers_subject_group_over_raw_confidence(self):
        # 배경 나무 신뢰도가 가장 높아도, 주제(집) 그룹에서 먼저 고른다(709 핵심 수정).
        req = self._htp(
            detected_objects=[
                _detected("HOUSE", "집", 0.60),
                _detected("HOUSE_ROOF", "지붕", 0.80),
                _detected("SCENERY_TREE", "(배경) 나무", 0.95),
            ]
        )
        target = question_service._target_for_purpose(req, "OBJECT_DESCRIPTION")
        self.assertEqual(target.object_code, "HOUSE_ROOF")

    def test_falls_back_to_background_when_subject_exhausted(self):
        # 주제(집) 객체가 없으면 배경도 후보로 삼는다(결정 B: 주제 소진 후 배경).
        req = self._htp(
            detected_objects=[_detected("SCENERY_TREE", "(배경) 나무", 0.5)]
        )
        target = question_service._target_for_purpose(req, "OBJECT_DESCRIPTION")
        self.assertEqual(target.object_code, "SCENERY_TREE")

    def test_asked_object_is_excluded_from_target(self):
        req = self._htp(
            detected_objects=[
                _detected("HOUSE", "집", 0.9),
                _detected("HOUSE_ROOF", "지붕", 0.8),
            ],
            asked_object_codes=["HOUSE"],
        )
        target = question_service._target_for_purpose(req, "OBJECT_DESCRIPTION")
        self.assertEqual(target.object_code, "HOUSE_ROOF")

    def test_all_subject_objects_asked_downgrades_to_drawing_context(self):
        req = self._htp(
            detected_objects=[_detected("HOUSE", "집", 0.9)],
            asked_object_codes=["HOUSE"],
        )
        capture: dict = {}
        client = _mock_client(capture, reply="오늘은 뭘 그렸어?")
        with mock.patch.object(question_service, "get_client", return_value=client):
            resp = question_service.generate(req, "req-713")
        self.assertEqual(resp.question_purpose, "DRAWING_CONTEXT")
        self.assertIsNone(resp.target_object)

    def test_htp_prompt_states_subject_and_forbids_other_subjects(self):
        req = self._htp(detected_objects=[_detected("HOUSE", "집", 0.9)])
        system = question_service._build_messages(req)[0]["content"]
        self.assertIn("'집'", system)
        self.assertIn("다른 주제", system)

    def test_first_question_examples_no_longer_inject_other_subjects(self):
        # 709: 예시가 집·나무·사람을 다 넣던 문제 제거 회귀 방어.
        req = self._htp(detected_objects=[_detected("HOUSE", "집", 0.9)])
        system = question_service._build_messages(req)[0]["content"]
        self.assertNotIn("이 나무는 어디에 있는 나무야", system)
        self.assertNotIn("이 집에는 누가 살고 있어", system)

    def test_prompt_target_matches_response_target(self):
        # 질문 문장이 가리키는 객체와 응답 targetObject가 같은 객체다(정합성).
        req = self._htp(
            detected_objects=[
                _detected("HOUSE_ROOF", "지붕", 0.9),
                _detected("SCENERY_TREE", "(배경) 나무", 0.95),
            ]
        )
        capture: dict = {}
        client = _mock_client(capture, reply="이 지붕은 무슨 색이야?")
        with mock.patch.object(question_service, "get_client", return_value=client):
            resp = question_service.generate(req, "req-713")
        self.assertEqual(resp.target_object.object_code, "HOUSE_ROOF")
        self.assertIn("지붕", capture["system"])

    def test_diary_has_no_subject_constraint(self):
        req = _request(
            activity_type="ART_DIARY",
            drawing_subject=None,
            detected_objects=[_detected("UNKNOWN", "강아지", 0.9)],
        )
        system = question_service._build_messages(req)[0]["content"]
        self.assertIn("정해진 주제는 없어", system)
        self.assertNotIn("다른 주제", system)

    def test_asked_hint_present_only_when_asked_nonempty(self):
        with_asked = question_service._build_messages(
            self._htp(
                detected_objects=[_detected("HOUSE_ROOF", "지붕", 0.9)],
                asked_object_codes=["HOUSE"],
            )
        )[0]["content"]
        self.assertIn("다시 묻지 말", with_asked)
        without_asked = question_service._build_messages(
            self._htp(detected_objects=[_detected("HOUSE", "집", 0.9)])
        )[0]["content"]
        self.assertNotIn("다시 묻지 말", without_asked)


if __name__ == "__main__":
    unittest.main()
