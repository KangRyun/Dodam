"""crisis_guidance 단위 테스트 — 보호자 위기 안내 문구 생성 규칙 (S15P11B209-598).

- 각 위기 사유 코드가 알맞은 심각도·안내·상담 자원으로 매핑된다.
- 모르는 코드·None은 안내가 없다.
- 안내에는 아이 발화 원문이 담기지 않는다(개인정보 보호) — 일반적 서술만.
- 자해·학대는 즉각 우려(HIGH), 위기 의도는 주의(ELEVATED).
"""

from __future__ import annotations

import unittest

import crisis_detection as cd
import crisis_guidance as cg


class GuidanceMappingTest(unittest.TestCase):
    def test_self_harm_is_high_with_suicide_line(self):
        alert = cg.guidance_for(cd.SELF_HARM_RISK)
        self.assertIsNotNone(alert)
        self.assertEqual(alert.severity, cg.SEVERITY_HIGH)
        self.assertEqual(alert.reason_code, cd.SELF_HARM_RISK)
        contacts = [r.contact for r in alert.resources]
        self.assertIn("109", contacts)  # 자살예방 상담전화(2024-01 통합)

    def test_abuse_is_high_with_child_protection_line(self):
        alert = cg.guidance_for(cd.ABUSE_DISCLOSURE)
        self.assertIsNotNone(alert)
        self.assertEqual(alert.severity, cg.SEVERITY_HIGH)
        contacts = [r.contact for r in alert.resources]
        self.assertIn("112", contacts)  # 아동학대 신고·상담(112로 일원화)

    def test_no_discontinued_number_is_offered(self):
        """폐지된 번호가 어느 안내에도 남아 있으면 안 된다 (S15P11B209-853).

        1393(→109 통합)·1577-1391(폐지)은 걸어도 연결되지 않는다. 위기 안내에 죽은 번호가
        실리면 도움이 아니라 해가 되므로, 개별 케이스가 아니라 전체를 훑어 막는다.
        """
        dead = {"1393", "1577-1391", "15771391"}
        for code in (cd.SELF_HARM_RISK, cd.ABUSE_DISCLOSURE, cd.CRISIS_INTENT):
            alert = cg.guidance_for(code)
            with self.subTest(code=code):
                for resource in alert.resources:
                    self.assertNotIn(resource.contact.replace(" ", ""), dead)
                # 안내 문장에 번호를 직접 적은 경우까지 훑는다.
                text = " ".join([alert.message, *alert.action_steps])
                for number in dead:
                    self.assertNotIn(number, text)

    def test_crisis_intent_is_elevated(self):
        alert = cg.guidance_for(cd.CRISIS_INTENT)
        self.assertIsNotNone(alert)
        self.assertEqual(alert.severity, cg.SEVERITY_ELEVATED)

    def test_every_crisis_code_has_guidance(self):
        for code in (cd.SELF_HARM_RISK, cd.ABUSE_DISCLOSURE, cd.CRISIS_INTENT):
            with self.subTest(code=code):
                self.assertTrue(cg.has_guidance(code))


class WellFormedTest(unittest.TestCase):
    def test_each_alert_has_message_steps_resources_disclaimer(self):
        for code in (cd.SELF_HARM_RISK, cd.ABUSE_DISCLOSURE, cd.CRISIS_INTENT):
            with self.subTest(code=code):
                alert = cg.guidance_for(code)
                self.assertTrue(alert.title.strip())
                self.assertTrue(alert.message.strip())
                self.assertTrue(alert.action_steps)
                self.assertTrue(alert.resources)
                # 비진단 고지가 반드시 붙는다.
                self.assertIn("진단이 아닙니다", alert.disclaimer)

    def test_message_is_not_diagnostic_or_labeling(self):
        # 보호자 안내라도 "장애/진단" 같은 단정은 쓰지 않는다(비낙인 원칙).
        for code in (cd.SELF_HARM_RISK, cd.ABUSE_DISCLOSURE, cd.CRISIS_INTENT):
            with self.subTest(code=code):
                alert = cg.guidance_for(code)
                self.assertNotIn("장애", alert.message)
                self.assertNotIn("진단", alert.message)


class UnknownCodeTest(unittest.TestCase):
    def test_none_and_unknown_return_no_guidance(self):
        self.assertIsNone(cg.guidance_for(None))
        self.assertIsNone(cg.guidance_for(""))
        self.assertIsNone(cg.guidance_for("NOT_A_REAL_CODE"))
        self.assertFalse(cg.has_guidance("NOT_A_REAL_CODE"))


if __name__ == "__main__":
    unittest.main()
