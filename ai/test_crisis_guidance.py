"""crisis_guidance 단위 테스트 — 보호자 위기 안내 문구 생성 규칙 (S15P11B209-598).

- 각 위기 사유 코드가 알맞은 심각도·안내·상담 자원으로 매핑된다.
- 모르는 코드·None은 안내가 없다.
- 안내에는 아이 발화 원문이 담기지 않는다(개인정보 보호) — 일반적 서술만.
- 자해·학대는 즉각 우려(HIGH), 위기 의도는 주의(ELEVATED).
- **수신자 분기**(S15P11B209-890): 학대 진술은 보호자에게 자동 전달하지 않고 전문가 검토
  경로로만 남긴다. 가해자가 보호자일 수 있어 자동 통지가 아이를 더 위험하게 만들기 때문이다.
"""

from __future__ import annotations

import unittest

import crisis_detection as cd
import crisis_guidance as cg

# 모든 위기 사유 코드 / 보호자에게 전달하는 코드 / 전문가 전용 코드.
ALL_CODES = (cd.SELF_HARM_RISK, cd.ABUSE_DISCLOSURE, cd.CRISIS_INTENT)
GUARDIAN_CODES = (cd.SELF_HARM_RISK, cd.CRISIS_INTENT)
EXPERT_ONLY_CODES = (cd.ABUSE_DISCLOSURE,)


class GuidanceMappingTest(unittest.TestCase):
    def test_self_harm_is_high_with_suicide_line(self):
        alert = cg.guidance_for(cd.SELF_HARM_RISK)
        self.assertIsNotNone(alert)
        self.assertEqual(alert.severity, cg.SEVERITY_HIGH)
        self.assertEqual(alert.reason_code, cd.SELF_HARM_RISK)
        contacts = [r.contact for r in alert.resources]
        self.assertIn("109", contacts)  # 자살예방 상담전화(2024-01 통합)

    def test_no_discontinued_number_is_offered(self):
        """폐지된 번호가 어느 안내에도 남아 있으면 안 된다 (S15P11B209-853).

        1393(→109 통합)·1577-1391(폐지)은 걸어도 연결되지 않는다. 위기 안내에 죽은 번호가
        실리면 도움이 아니라 해가 되므로, 개별 케이스가 아니라 전체를 훑어 막는다.
        보호자 안내와 전문가 전용 기록을 **둘 다** 훑는다(890으로 경로가 갈렸다).
        """
        dead = {"1393", "1577-1391", "15771391"}
        for code in ALL_CODES:
            with self.subTest(code=code):
                alert = cg.guidance_for(code)
                note = cg.expert_note_for(code)
                record = alert if alert is not None else note
                self.assertIsNotNone(record, "어느 경로에도 기록이 없다")
                for resource in record.resources:
                    self.assertNotIn(resource.contact.replace(" ", ""), dead)
                # 안내 문장에 번호를 직접 적은 경우까지 훑는다.
                if alert is not None:
                    text = " ".join([alert.message, *alert.action_steps])
                else:
                    text = " ".join([note.summary, note.review_reason])
                for number in dead:
                    self.assertNotIn(number, text)

    def test_crisis_intent_is_elevated(self):
        alert = cg.guidance_for(cd.CRISIS_INTENT)
        self.assertIsNotNone(alert)
        self.assertEqual(alert.severity, cg.SEVERITY_ELEVATED)

    def test_every_crisis_code_is_known(self):
        """모든 사유 코드는 어느 한 경로로든 처리된다 — 조용히 사라지지 않는다."""
        for code in ALL_CODES:
            with self.subTest(code=code):
                self.assertTrue(cg.is_known_reason(code))
                self.assertTrue(
                    cg.guidance_for(code) is not None
                    or cg.expert_note_for(code) is not None
                )

    def test_guardian_codes_have_guardian_guidance(self):
        for code in GUARDIAN_CODES:
            with self.subTest(code=code):
                self.assertTrue(cg.has_guidance(code))
                self.assertTrue(cg.guardian_auto_delivery_allowed(code))
                self.assertFalse(cg.requires_expert_review(code))


class AbuseIsNotAutoSentToGuardianTest(unittest.TestCase):
    """학대 진술은 보호자에게 자동 전달하지 않는다 (S15P11B209-890).

    가해자가 보호자 본인일 수 있어, "아이가 이야기했다"는 사실이 자동 통지되면 입막음·보복으로
    이어져 아이가 더 위험해진다. 신호를 버리는 것이 아니라 수신자를 바꾸는 것이다.
    """

    def test_no_guardian_alert_for_abuse(self):
        self.assertIsNone(cg.guidance_for(cd.ABUSE_DISCLOSURE))
        self.assertFalse(cg.has_guidance(cd.ABUSE_DISCLOSURE))
        self.assertFalse(cg.guardian_auto_delivery_allowed(cd.ABUSE_DISCLOSURE))

    def test_expert_only_note_exists_and_requires_review(self):
        note = cg.expert_note_for(cd.ABUSE_DISCLOSURE)
        self.assertIsNotNone(note)
        self.assertEqual(note.reason_code, cd.ABUSE_DISCLOSURE)
        self.assertEqual(note.severity, cg.SEVERITY_HIGH)
        self.assertTrue(note.requires_expert_review)
        self.assertFalse(note.guardian_auto_delivery_allowed)
        self.assertTrue(cg.requires_expert_review(cd.ABUSE_DISCLOSURE))
        # 검토자가 상황을 알 수 있어야 한다 — 빈 기록이면 신호를 버린 것과 같다.
        self.assertTrue(note.summary.strip())
        self.assertTrue(note.review_reason.strip())
        # 보류 사유에 '왜'가 남아 있어야 나중에 되돌리려는 시도를 막는다.
        self.assertIn("보호자", note.review_reason)

    def test_expert_only_note_is_not_a_guardian_alert_type(self):
        """타입이 달라야 보호자 전달 코드에 실수로 흘러들지 않는다."""
        note = cg.expert_note_for(cd.ABUSE_DISCLOSURE)
        self.assertNotIsInstance(note, cg.GuardianAlert)
        self.assertIsInstance(note, cg.ExpertOnlyNote)

    def test_expert_only_reasons_never_appear_in_guardian_guidance(self):
        """회귀 가드 — 전문가 전용 코드가 보호자 안내로 되돌아오면 실패한다."""
        for code in cg.EXPERT_ONLY_REASONS:
            with self.subTest(code=code):
                self.assertIsNone(cg.guidance_for(code))
        for code in EXPERT_ONLY_CODES:
            with self.subTest(code=code):
                self.assertIn(code, cg.EXPERT_ONLY_REASONS)

    def test_abuse_note_keeps_report_line_for_reviewer(self):
        """검토자가 신고 창구를 알 수 있게 자원은 유지한다(112 일원화 — 853)."""
        note = cg.expert_note_for(cd.ABUSE_DISCLOSURE)
        contacts = [r.contact for r in note.resources]
        self.assertIn("112", contacts)


class WellFormedTest(unittest.TestCase):
    def test_each_alert_has_message_steps_resources_disclaimer(self):
        for code in GUARDIAN_CODES:
            with self.subTest(code=code):
                alert = cg.guidance_for(code)
                self.assertTrue(alert.title.strip())
                self.assertTrue(alert.message.strip())
                self.assertTrue(alert.action_steps)
                self.assertTrue(alert.resources)
                # 비진단 고지가 반드시 붙는다.
                self.assertIn("진단이 아닙니다", alert.disclaimer)

    def test_expert_note_is_well_formed(self):
        for code in EXPERT_ONLY_CODES:
            with self.subTest(code=code):
                note = cg.expert_note_for(code)
                self.assertTrue(note.title.strip())
                self.assertTrue(note.summary.strip())
                self.assertIn("진단이 아닙니다", note.disclaimer)

    def test_message_is_not_diagnostic_or_labeling(self):
        # 보호자 안내라도 "장애/진단" 같은 단정은 쓰지 않는다(비낙인 원칙).
        for code in GUARDIAN_CODES:
            with self.subTest(code=code):
                alert = cg.guidance_for(code)
                self.assertNotIn("장애", alert.message)
                self.assertNotIn("진단", alert.message)

    def test_expert_note_is_not_diagnostic_or_labeling(self):
        # 전문가 검토용 기록에도 진단·낙인 표현은 쓰지 않는다.
        for code in EXPERT_ONLY_CODES:
            with self.subTest(code=code):
                note = cg.expert_note_for(code)
                self.assertNotIn("장애", note.summary)
                self.assertNotIn("진단", note.summary)


class UnknownCodeTest(unittest.TestCase):
    def test_none_and_unknown_return_no_guidance(self):
        self.assertIsNone(cg.guidance_for(None))
        self.assertIsNone(cg.guidance_for(""))
        self.assertIsNone(cg.guidance_for("NOT_A_REAL_CODE"))
        self.assertFalse(cg.has_guidance("NOT_A_REAL_CODE"))

    def test_none_and_unknown_have_no_expert_note_either(self):
        self.assertIsNone(cg.expert_note_for(None))
        self.assertIsNone(cg.expert_note_for(""))
        self.assertIsNone(cg.expert_note_for("NOT_A_REAL_CODE"))
        self.assertFalse(cg.requires_expert_review("NOT_A_REAL_CODE"))
        self.assertFalse(cg.is_known_reason("NOT_A_REAL_CODE"))
        self.assertFalse(cg.guardian_auto_delivery_allowed("NOT_A_REAL_CODE"))


if __name__ == "__main__":
    unittest.main()
