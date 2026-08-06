"""config 환경변수 해석 규칙 단위 테스트 (S15P11B209-972).

config 는 import 시점에 os.environ 을 읽어 모듈 상수를 굳힌다. 그래서 "환경변수가 없을 때
무엇으로 떨어지는가"는 모듈을 그 환경으로 **다시 로드해야만** 검증된다 — 이미 로드된 값을
읽는 것으로는 폴백 규칙이 아니라 지금 셸의 상태를 확인하게 된다.

⚠️ importlib.reload 는 모듈 객체를 제자리에서 갈아끼우므로 `import config` 를 들고 있는
   다른 모듈에도 즉시 보인다. 반드시 tearDown 에서 실제 환경으로 되돌린다.
"""

from __future__ import annotations

import importlib
import os
import unittest
from unittest import mock

import config


def _reload_with(env: dict[str, str]):
    """주어진 환경변수만 있는 상태로 config 를 다시 로드한다.

    clear=True 로 환경을 비우는 이유: '미설정'을 재현하려면 키를 지워야 하는데
    patch.dict 는 덮어쓰기만 한다. config 가 읽는 다른 키들은 전부 기본값으로 떨어지며,
    이 테스트는 모델 이름만 본다.

    load_dotenv 를 무력화하는 이유: 그대로 두면 상위 디렉터리의 실제 .env 를 찾아
    환경을 도로 채운다 — 테스트가 실행 머신의 로컬 설정에 따라 결과를 바꾼다.
    """
    with mock.patch.dict(os.environ, env, clear=True), mock.patch("dotenv.load_dotenv"):
        return importlib.reload(config)


class ReportLlmModelFallbackTest(unittest.TestCase):
    """리포트 모델은 대화 모델과 분리하되, 모르는 환경에서는 종전과 똑같이 돌아야 한다."""

    def tearDown(self):
        # 실제 프로세스 환경으로 원복 — 다른 테스트 모듈이 같은 config 객체를 본다.
        importlib.reload(config)

    def test_unset_falls_back_to_llm_model(self):
        """REPORT_LLM_MODEL 을 모르는 환경(로컬·CI·구 배포)은 종전 동작 그대로다."""
        reloaded = _reload_with({"LLM_MODEL": "only-one-model"})
        self.assertEqual(reloaded.REPORT_LLM_MODEL, "only-one-model")
        self.assertEqual(reloaded.REPORT_LLM_MODEL, reloaded.LLM_MODEL)

    def test_set_overrides_llm_model(self):
        reloaded = _reload_with(
            {"LLM_MODEL": "conversation-model", "REPORT_LLM_MODEL": "report-model"}
        )
        self.assertEqual(reloaded.LLM_MODEL, "conversation-model")
        self.assertEqual(reloaded.REPORT_LLM_MODEL, "report-model")

    def test_empty_value_is_treated_as_unset(self):
        """빈 값으로 GMS 를 부르면 원인이 안 드러나는 400이 된다 — 미설정으로 본다.

        AI_INTERNAL_API_KEY 와 같은 규약. 배포 템플릿에서 키만 있고 값이 빈 채로 주입되는
        일이 실제로 있으므로(infra/.env.example 헤더의 키 누락 사고 참조) 방어한다.
        """
        reloaded = _reload_with({"LLM_MODEL": "only-one-model", "REPORT_LLM_MODEL": ""})
        self.assertEqual(reloaded.REPORT_LLM_MODEL, "only-one-model")

    def test_both_default_when_nothing_is_set(self):
        """아무것도 없으면 둘 다 코드 기본값 — 기본값끼리도 어긋나면 안 된다."""
        reloaded = _reload_with({})
        self.assertEqual(reloaded.LLM_MODEL, "gpt-4o-mini")
        self.assertEqual(reloaded.REPORT_LLM_MODEL, reloaded.LLM_MODEL)

    def test_reload_restores_process_environment(self):
        """tearDown 의 원복이 실제로 도는지 — 이 테스트가 뒤 테스트를 오염시키지 않는 근거."""
        _reload_with({"LLM_MODEL": "throwaway"})
        importlib.reload(config)
        self.assertEqual(config.LLM_MODEL, os.environ.get("LLM_MODEL", "gpt-4o-mini"))


if __name__ == "__main__":
    unittest.main()
