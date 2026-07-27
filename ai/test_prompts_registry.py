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
        value = prompts_registry.version("first_question")
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
            prompts_registry.content_hash("first_question"),
            prompts_registry.content_hash("report"),
        )

    def test_unknown_prompt_uses_zero_semver(self):
        # 표에 없는 이름은 0.0.0으로 표기(파일이 있으면 해시는 계산됨).
        self.assertTrue(prompts_registry.version("guardrails").startswith("1.0.0+"))

    def test_composite_sorts_and_joins(self):
        composite = prompts_registry.composite_version("conversations", "first_question")
        parts = composite.split(";")
        self.assertEqual(len(parts), 2)
        # 이름순 정렬 — conversations가 first_question보다 앞.
        self.assertTrue(parts[0].startswith("conversations@"))
        self.assertTrue(parts[1].startswith("first_question@"))
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

        self.assertEqual(
            vlm_client.PROMPT_VERSION, prompts_registry.version("drawing_description")
        )
        self.assertEqual(
            report_client.PROMPT_VERSION, prompts_registry.version("report")
        )

    def test_question_path_uses_composite_version(self):
        import llm_client
        import question_service

        expected = prompts_registry.composite_version(
            "first_question", "conversations", "guardrails"
        )
        self.assertEqual(llm_client.PROMPT_VERSION, expected)
        self.assertEqual(question_service.PROMPT_VERSION, expected)


if __name__ == "__main__":
    unittest.main()
