"""prompts_registry 단위 테스트 — 프롬프트 파일 버전 관리 (S15P11B209-595).

- 버전 문자열이 "<semver>+<content_hash>" 형식이고, 내용이 바뀌면 해시가 달라진다.
- composite_version이 여러 프롬프트를 정렬해 통합한다.
- verify_prompt_files가 semver 표와 실제 파일 불일치를 잡는다.
torch·GMS 없이 파일만 읽어 검증한다.
"""

from __future__ import annotations

import re
import unittest

import prompts_registry


class VersionTest(unittest.TestCase):
    def test_version_has_semver_and_hash(self):
        value = prompts_registry.version("first_question_htp")
        # 예: "1.1.0+ab12cd34"
        self.assertRegex(value, r"^\d+\.\d+\.\d+\+[0-9a-f]{8}$")

    def test_hash_reflects_content(self):
        # 같은 이름은 결정적으로 같은 해시.
        self.assertEqual(
            prompts_registry.content_hash("guardrails"),
            prompts_registry.content_hash("guardrails"),
        )
        # 서로 다른 프롬프트는(내용이 다르므로) 해시가 다르다.
        self.assertNotEqual(
            prompts_registry.content_hash("first_question_htp"),
            prompts_registry.content_hash("report_common"),
        )

    def test_registered_prompt_uses_its_semver(self):
        # 표에 등록된 이름은 그 semver를 그대로 쓴다.
        semver = prompts_registry._PROMPT_SEMVER["guardrails"]
        self.assertTrue(prompts_registry.version("guardrails").startswith(f"{semver}+"))

    def test_composite_sorts_and_joins(self):
        composite = prompts_registry.composite_version(
            "conversations_htp", "first_question_htp"
        )
        parts = composite.split(";")
        self.assertEqual(len(parts), 2)
        # 이름순 정렬 — conversations_htp가 first_question_htp보다 앞.
        self.assertTrue(parts[0].startswith("conversations_htp@"))
        self.assertTrue(parts[1].startswith("first_question_htp@"))
        # 각 파트는 name@<version> 형식.
        for part in parts:
            self.assertRegex(part, r"^[a-z_]+@\d+\.\d+\.\d+\+[0-9a-f]{8}$")

    def test_load_returns_stripped_content(self):
        text = prompts_registry.load("guardrails")
        self.assertTrue(text)
        self.assertEqual(text, text.strip())


class VerifyPromptFilesTest(unittest.TestCase):
    def test_registered_prompts_match_files(self):
        # 현재 저장소 상태는 표와 파일이 일치해야 한다(누락·미등록 없음).
        self.assertEqual(prompts_registry.verify_prompt_files(), [])


class ClientVersionWiringTest(unittest.TestCase):
    """각 클라이언트 PROMPT_VERSION이 레지스트리에서 파생되는지."""

    def test_vlm_and_report_use_registry_versions(self):
        import report_client
        import vlm_client

        # 서술·리포트 프롬프트는 활동 유형별로 갈라져 통합 버전을 쓴다.
        self.assertEqual(
            vlm_client.PROMPT_VERSION,
            prompts_registry.composite_version(
                "drawing_description_htp", "drawing_description_diary"
            ),
        )
        self.assertEqual(
            report_client.PROMPT_VERSION,
            prompts_registry.composite_version(
                "report_common", "report_htp", "report_diary"
            ),
        )

    def test_vlm_prompt_version_resolves_per_activity(self):
        """'실제로 쓴' 프롬프트 하나의 버전 — 결과 재현·추적의 단위."""
        import vlm_client

        self.assertEqual(
            vlm_client.prompt_version_for("HTP"),
            prompts_registry.version("drawing_description_htp"),
        )
        self.assertEqual(
            vlm_client.prompt_version_for("ART_DIARY"),
            prompts_registry.version("drawing_description_diary"),
        )
        # 활동 유형을 모르는 호출(draft 경로)은 기본 가중치와 같은 HTP로 떨어진다.
        self.assertEqual(
            vlm_client.prompt_version_for(None),
            prompts_registry.version("drawing_description_htp"),
        )

    def test_question_path_uses_composite_version(self):
        """모듈 상수는 '대화 경로가 쓸 수 있는 파일 전부'의 통합 버전이다."""
        import llm_client
        import question_service

        expected = prompts_registry.composite_version(
            "first_question_htp",
            "first_question_diary",
            "conversations_htp",
            "conversations_diary",
            "conversation_common",
            "conversation_tone",
            "guardrails",
        )
        self.assertEqual(llm_client.PROMPT_VERSION, expected)
        self.assertEqual(question_service.PROMPT_VERSION, expected)

    def test_conversation_prompt_version_resolves_per_activity(self):
        """생성된 질문에 실리는 버전은 '이번에 쓴' 활동 변형만 담는다(S15P11B209-786).

        두 변형을 모두 적으면 어느 쪽으로 뽑힌 결과인지 사후에 구분할 수 없다.
        """
        import llm_client

        htp = llm_client.prompt_version_for("HTP")
        diary = llm_client.prompt_version_for("ART_DIARY")
        self.assertNotEqual(htp, diary)
        self.assertIn("first_question_htp@", htp)
        self.assertIn("conversations_htp@", htp)
        self.assertNotIn("_diary@", htp)
        self.assertIn("first_question_diary@", diary)
        self.assertNotIn("_htp@", diary)
        # 공유 파일은 어느 쪽에나 실린다 — 내용이 바뀌면 두 버전 모두 달라져야 한다.
        for version in (htp, diary):
            self.assertIn("conversation_common@", version)
            self.assertIn("conversation_tone@", version)
            self.assertIn("guardrails@", version)
        # 활동 유형을 모르는 호출(draft 경로)은 기본인 HTP로 떨어진다.
        self.assertEqual(llm_client.prompt_version_for(None), htp)


if __name__ == "__main__":
    unittest.main()
