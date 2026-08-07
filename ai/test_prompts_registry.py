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
            prompts_registry.content_hash("report_htp"),
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


class ShortVersionTest(unittest.TestCase):
    """저장·전송용 축약 버전 (S15P11B209-819)."""

    def test_short_version_format(self):
        value = prompts_registry.short_version("htp", "report_review", "report_htp")
        self.assertRegex(value, prompts_registry._TAG_PATTERN)

    def test_length_is_independent_of_file_count(self):
        """핵심 성질 — 파일이 늘어도 태그가 길어지지 않는다.

        정본(composite_version)은 파일당 30자쯤 늘어 786에서 컬럼을 넘겼다. 축약 태그는
        같은 라벨이면 파일 수와 무관하게 길이가 같아야 한다.
        """
        one = prompts_registry.short_version("x", "report_review")
        many = prompts_registry.short_version(
            "x", "report_review", "report_htp", "report_diary", "guardrails"
        )
        self.assertEqual(len(one), len(many))
        # 그래도 조합이 다르면 값은 달라야 한다 — 길이만 같고 구분은 살아 있다.
        self.assertNotEqual(one, many)

    def test_digest_reflects_any_member_content(self):
        # 구성원이 하나만 달라도 다이제스트가 달라진다(내용 변경 추적이 끊기지 않게).
        self.assertNotEqual(
            prompts_registry.composite_digest("report_review", "report_htp"),
            prompts_registry.composite_digest("report_review", "report_diary"),
        )

    def test_semver_is_max_of_members(self):
        # conversations_htp(4.x) > conversation_rules_htp(1.x) — 큰 쪽이 세대를 대표한다.
        # ⚠️ 기대값을 적어 두지 않고 레지스트리에서 가져온다. 하드코딩하면 프롬프트를
        #    올릴 때마다 이 테스트가 깨져, 규칙이 아니라 숫자를 고치게 된다(856에서 겪음).
        members = ("conversations_htp", "conversation_rules_htp")
        expected = max(
            (prompts_registry._PROMPT_SEMVER[m] for m in members),
            key=lambda s: tuple(int(p) for p in s.split(".")),
        )
        value = prompts_registry.short_version("conv", *members)
        self.assertTrue(value.startswith(f"conv@{expected}+"), value)
        # 작은 쪽이 대표가 되면 안 된다.
        self.assertNotEqual(
            expected, prompts_registry._PROMPT_SEMVER["conversation_rules_htp"]
        )


class VersionTagLengthTest(unittest.TestCase):
    """BE에 저장되는 모든 재현성 태그가 컬럼 한계 안에 있는지 (S15P11B209-819).

    이번 장애(815)의 본질은 43자가 50자 한계에 7자 남기고 통과하던 것을 아무도 보고 있지
    않다가, 프롬프트 파일이 하나 갈리자 76자가 되며 리포트 생성이 전량 실패한 것이다.
    한계를 테스트로 고정해 같은 회귀를 배포 전에 잡는다.

    ⚠️ AI 쪽에서 문자열을 자르지는 않는다 — 자르면 잘린 태그가 재현성 정보를 잃어
    필드의 존재 이유가 사라진다. 넘치면 여기서 실패시켜 축약 방식을 고치게 한다.
    """

    def _assert_fits(self, label: str, value: str):
        self.assertLessEqual(
            len(value),
            prompts_registry.MAX_VERSION_TAG,
            f"{label} 태그가 {prompts_registry.MAX_VERSION_TAG}자를 넘었다"
            f"({len(value)}자): {value}",
        )

    def test_report_model_version_fits(self):
        """generated_model_version·summary_model_version 컬럼에 들어가는 값."""
        import report_client

        for is_htp in (True, False):
            self._assert_fits(
                f"report(is_htp={is_htp})", report_client._generation_version(is_htp)
            )

    def test_question_prompt_version_fits(self):
        """QuestionResponse.promptVersion — 위기·인젝션 결정적 응답 포함."""
        import llm_client
        import question_service

        for activity in ("HTP", "ART_DIARY", None):
            self._assert_fits(
                f"question({activity})", llm_client.prompt_version_for(activity)
            )
        self._assert_fits("question(all)", question_service.PROMPT_VERSION)

    def test_analysis_prompt_version_fits(self):
        import vlm_client

        for activity in ("HTP", "ART_DIARY", None):
            self._assert_fits(
                f"analysis({activity})", vlm_client.prompt_version_for(activity)
            )
        self._assert_fits("analysis(all)", vlm_client.PROMPT_VERSION)


class VersionManifestTest(unittest.TestCase):
    """축약 태그가 정본으로 되짚어지는지 — 축약해도 재현성이 유지되는 근거 (S15P11B209-819)."""

    def test_report_manifest_resolves_to_composites(self):
        import report_client

        # 자체검토 프롬프트(report_review)도 한 번의 리포트 생성을 이루므로 조합에 들어간다 —
        # 검토 기준이 바뀌면 어떤 리포트가 보호자에게 열리는지가 바뀐다(2026-08-05).
        manifest = report_client.version_manifest()
        self.assertEqual(
            manifest[report_client._generation_version(True).split("prompt=")[1]],
            prompts_registry.composite_version("report_htp", "report_review"),
        )
        self.assertEqual(
            manifest[report_client._generation_version(False).split("prompt=")[1]],
            prompts_registry.composite_version("report_diary", "report_review"),
        )

    def test_question_manifest_resolves_to_composites(self):
        import llm_client

        manifest = llm_client.version_manifest()
        for activity in ("HTP", "ART_DIARY"):
            self.assertEqual(
                manifest[llm_client.prompt_version_for(activity)],
                prompts_registry.composite_version(
                    *llm_client.prompt_names_for(activity)
                ),
            )


class ClientVersionWiringTest(unittest.TestCase):
    """각 클라이언트 PROMPT_VERSION이 레지스트리에서 파생되는지."""

    def test_vlm_and_report_use_registry_versions(self):
        import report_client
        import vlm_client

        # 서술·리포트 프롬프트는 활동 유형별로 갈라져 통합 버전을 쓴다.
        self.assertEqual(
            vlm_client.PROMPT_VERSION,
            prompts_registry.short_version(
                "desc-all", "drawing_description_htp", "drawing_description_diary"
            ),
        )
        self.assertEqual(
            report_client.PROMPT_VERSION,
            prompts_registry.short_version(
                "report-all",
                "report_htp",
                "report_diary",
                "report_review",
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

        expected = prompts_registry.short_version(
            "conv-all",
            "first_question_htp",
            "first_question_diary",
            "conversations_htp",
            "conversations_diary",
            "conversation_rules_htp",
            "conversation_rules_diary",
            "conversation_tone_htp",
            "conversation_tone_diary",
            "activity_block_htp",
            "activity_block_diary",
            "guardrails",
            "htp_question_bank",
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
        # 태그는 축약됐지만(819) 어느 변형인지는 라벨로 구분된다 — 사후에 갈라볼 수 있어야 한다.
        self.assertTrue(htp.startswith("conv-htp@"))
        self.assertTrue(diary.startswith("conv-diary@"))
        # 조합 자체(태그가 가리키는 실체)는 변형 파일이 갈라져 있어야 한다.
        htp_names = llm_client.prompt_names_for("HTP")
        diary_names = llm_client.prompt_names_for("ART_DIARY")
        self.assertIn("first_question_htp", htp_names)
        self.assertIn("conversations_htp", htp_names)
        self.assertNotIn("first_question_diary", htp_names)
        self.assertIn("first_question_diary", diary_names)
        self.assertNotIn("first_question_htp", diary_names)
        # 기반 규칙·말투도 활동별 파일이다(993 — 공용 제거). 서로의 파일이 실리면 안 된다.
        self.assertIn("conversation_rules_htp", htp_names)
        self.assertIn("conversation_tone_htp", htp_names)
        self.assertNotIn("conversation_rules_diary", htp_names)
        self.assertIn("conversation_rules_diary", diary_names)
        self.assertIn("conversation_tone_diary", diary_names)
        self.assertNotIn("conversation_rules_htp", diary_names)
        # 남은 공유 파일은 guardrails 하나다 — 아동 안전 문구라 두 벌로 가르지 않는다.
        for names in (htp_names, diary_names):
            self.assertIn("guardrails", names)
        # 질문 뱅크(811)는 HTP 전용 — PDI는 HTP 프로토콜이라 그림일기엔 실리지 않는다.
        self.assertIn("htp_question_bank", htp_names)
        self.assertNotIn("htp_question_bank", diary_names)
        # 활동 유형을 모르는 호출(draft 경로)은 기본인 HTP로 떨어진다.
        self.assertEqual(llm_client.prompt_version_for(None), htp)


if __name__ == "__main__":
    unittest.main()
