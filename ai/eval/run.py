"""프롬프트 회귀 평가 러너 (S15P11B209-792).

실행:
    cd ai && python -m eval.run              # A층(무료) + B층(GMS 실호출)
    cd ai && python -m eval.run --layer a    # 조립 검증만 — 키 없이 돌고 비용 0
    cd ai && python -m eval.run --repeat 3   # 표본 3회(LLM은 비결정적이라 1회는 근거가 얇다)

산출: docs/ai/prompt-eval-<날짜시각>.md + 표준출력 요약. 종료 코드는 실패 수(회귀 게이트용).

⚠️ B층은 GMS에 실제로 요금이 나가는 호출을 한다. 케이스 7종 중 인젝션 1건은 GMS를
   타지 않으므로 현재 질문 10콜 + 리포트 2콜 = 회당 12콜이다(--repeat 배).
⚠️ 리포트에는 모델이 생성한 문장이 그대로 실린다. 입력은 전부 합성이라 아동 데이터는
   없지만, 산출물을 저장소에 커밋할 때는 한 번 눈으로 훑고 넣는다.
"""

from __future__ import annotations

import argparse
import sys
import traceback
from datetime import datetime
from pathlib import Path

# `python -m eval.run` 은 cwd(ai/)를 sys.path에 넣어 준다. 다른 위치에서 부를 때를 위해
# ai/ 를 명시적으로 얹는다 — 이 저장소의 ai 모듈은 전부 평면 import(`import config`)다.
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import config  # noqa: E402
import llm_client  # noqa: E402
import question_service  # noqa: E402
import report_client  # noqa: E402

from eval import cases, checks  # noqa: E402
from eval.checks import Finding  # noqa: E402

_SUBJECT_KO = {"HOUSE": "집", "TREE": "나무", "PERSON": "사람"}


# ── A층: 조립 검증 ─────────────────────────────────────────────
def run_layer_a() -> list[tuple[str, list[Finding]]]:
    """GMS 호출 없이 프롬프트 조립만 검증한다(결정적·무료)."""
    results: list[tuple[str, list[Finding]]] = []

    for case in cases.QUESTION_CASES:
        req = case.request
        # _build_messages는 private이지만 docstring이 "테스트 편의용" 직접 호출을 명시한다
        # (S15P11B209-713). 여기서 llm_client.render_*를 직접 부르면 activity_block(주제 고정·
        # 반복 방지)이 빠져 실제 운영 프롬프트와 다른 것을 재게 된다.
        system = question_service._build_messages(req)[0]["content"]
        is_first = not any(
            (m.sender_type or "").upper() == "CHILD" for m in req.recent_messages
        )
        found = checks.check_prompt_assembly(
            system,
            activity_type=req.activity_type,
            difficulty=req.difficulty,
            is_first=is_first,
        )
        if req.activity_type == "HTP" and req.drawing_subject:
            found.append(
                checks.check_subject_pinned(system, _SUBJECT_KO[req.drawing_subject])
            )
        results.append((case.id, found))

    for case in cases.REPORT_CASES:
        is_htp = report_client._is_htp(case.request)
        system = report_client._system_prompt(is_htp)
        variant, common = report_client._prompt_names(is_htp)
        expected_htp = case.meta.get("expects_rag", False)
        found = [
            Finding(
                "A",
                f"리포트 변형 선택({variant})",
                is_htp == expected_htp,
                f"is_htp={is_htp} (기대 {expected_htp})",
            ),
            Finding(
                "A",
                f"공통 규칙 포함({common})",
                "출력 형식" in system and "overallSummary" in system,
                "",
            ),
        ]
        results.append((case.id, found))
    return results


# ── B층: 실호출 준수 검증 ───────────────────────────────────────
def run_layer_b(repeat: int) -> list[tuple[str, int, list[Finding]]]:
    """GMS를 실제로 호출해 모델이 규칙을 지키는지 판정한다."""
    results: list[tuple[str, int, list[Finding]]] = []

    for case in cases.QUESTION_CASES:
        # 인젝션 케이스는 GMS 이전에 결정적으로 처리되므로 반복해도 같은 답이다.
        turns = 1 if not case.calls_gms else repeat
        for n in range(1, turns + 1):
            try:
                resp = question_service.generate(case.request, f"eval-{case.id}-{n}")
                found = checks.check_question_response(case, resp)
                # 대화 품질 (S15P11B209-858) — 안전과 별개로 '아이에게 좋은 대화인가'를 본다.
                found += checks.check_conversation_quality(case, resp)
                found.append(
                    Finding("B", "생성 문장", True, resp.question_text)
                )
            except question_service.SafetyBlockedError as e:
                found = [Finding("B", "안전 차단(422)", False, f"{type(e).__name__}: {e}")]
            except question_service.UpstreamError as e:
                found = [Finding("B", "GMS 실패", False, f"{type(e).__name__}: {e}")]
            except Exception as e:  # noqa: BLE001 — 러너는 한 케이스 실패로 멈추지 않는다
                found = [Finding("B", "예외", False, f"{type(e).__name__}: {e}")]
            results.append((case.id, n, found))

    for case in cases.REPORT_CASES:
        for n in range(1, repeat + 1):
            try:
                result = report_client.generate(
                    case.request, drawing_description=case.drawing_description
                )
                found = checks.check_report_result(case, result)
                found.append(
                    Finding(
                        "B",
                        "생성 요약",
                        True,
                        result.observation_draft.overall_summary,
                    )
                )
            except Exception as e:  # noqa: BLE001
                found = [Finding("B", "예외", False, f"{type(e).__name__}: {e}")]
            results.append((case.id, n, found))
    return results


# ── 리포트 ─────────────────────────────────────────────────────
def _case_title(case_id: str) -> tuple[str, str]:
    for c in (*cases.QUESTION_CASES, *cases.REPORT_CASES):
        if c.id == case_id:
            return c.title, c.why
    return case_id, ""


def render_markdown(
    layer_a: list[tuple[str, list[Finding]]],
    layer_b: list[tuple[str, int, list[Finding]]],
    *,
    repeat: int,
    stamp: str,
) -> str:
    lines: list[str] = [
        "# 프롬프트 회귀 평가 결과",
        "",
        f"- 실행: {stamp} · 표본 {repeat}회",
        f"- 대화 프롬프트 버전(HTP): `{llm_client.prompt_version_for('HTP')}`",
        f"- 대화 프롬프트 버전(그림일기): `{llm_client.prompt_version_for('ART_DIARY')}`",
        f"- 리포트 프롬프트 버전: `{report_client.PROMPT_VERSION}`",
        f"- 모델: `{config.LLM_MODEL}`",
        "",
        "> 입력은 전부 합성 데이터다(가드레일 9절 — 아동 실데이터는 평가셋에 넣지 않는다).",
        "",
    ]

    a_fail = sum(1 for _, fs in layer_a for f in fs if f.is_failure)
    b_fail = sum(1 for _, _, fs in layer_b for f in fs if f.is_failure)
    a_warn = sum(1 for _, fs in layer_a for f in fs if f.mark == "WARN")
    b_warn = sum(1 for _, _, fs in layer_b for f in fs if f.mark == "WARN")
    lines += [
        "## 요약",
        "",
        "| 층 | 검증 | 실패 | 경고 |",
        "|---|---|---|---|",
        f"| A. 조립(무료·결정적) | {sum(len(fs) for _, fs in layer_a)} | **{a_fail}** | {a_warn} |",
        f"| B. 준수(GMS 실호출) | {sum(len(fs) for _, _, fs in layer_b)} | **{b_fail}** | {b_warn} |",
        "",
        "> WARN 은 기계적으로 정확히 판정하기 어려운 규칙이라 실패로 세지 않는다(S15P11B209-858).",
        "> 종료 코드에도 반영되지 않으니, 눈으로 읽고 판단할 것.",
        "",
    ]

    if layer_a:
        lines += ["## A층 — 프롬프트 조립", ""]
        for case_id, found in layer_a:
            title, why = _case_title(case_id)
            lines += [f"### {case_id} — {title}", "", f"*{why}*", ""]
            lines += ["| 규칙 | 결과 | 비고 |", "|---|---|---|"]
            for f in found:
                lines.append(f"| {f.rule} | {f.mark} | {f.detail} |")
            lines.append("")

    if layer_b:
        lines += ["## B층 — 모델 준수", ""]
        for case_id, n, found in layer_b:
            title, why = _case_title(case_id)
            lines += [f"### {case_id} #{n} — {title}", "", f"*{why}*", ""]
            lines += ["| 규칙 | 결과 | 비고 |", "|---|---|---|"]
            for f in found:
                detail = f.detail.replace("\n", " ").replace("|", "\\|")
                lines.append(f"| {f.rule} | {f.mark} | {detail} |")
            lines.append("")

    return "\n".join(lines)


def main() -> int:
    p = argparse.ArgumentParser(description="프롬프트 회귀 평가 (S15P11B209-792)")
    p.add_argument("--layer", choices=["a", "b", "all"], default="all")
    p.add_argument("--repeat", type=int, default=1, help="B층 표본 수(기본 1)")
    p.add_argument("--out", type=Path, default=None, help="결과 마크다운 경로")
    args = p.parse_args()

    layer_a = run_layer_a() if args.layer in ("a", "all") else []

    layer_b: list[tuple[str, int, list[Finding]]] = []
    if args.layer in ("b", "all"):
        if not config.GMS_KEY:
            print("GMS_KEY가 비어 있어 B층을 건너뜁니다(.env 확인). A층만 실행했습니다.")
        else:
            try:
                layer_b = run_layer_b(args.repeat)
            except Exception:  # noqa: BLE001
                traceback.print_exc()
                print("B층 실행 중 복구 불가 오류 — A층 결과만 남깁니다.")

    stamp = datetime.now().strftime("%Y-%m-%d %H:%M")
    md = render_markdown(layer_a, layer_b, repeat=args.repeat, stamp=stamp)

    out = args.out
    if out is None:
        docs = Path(__file__).resolve().parents[2] / "docs" / "ai"
        docs.mkdir(parents=True, exist_ok=True)
        out = docs / f"prompt-eval-{datetime.now().strftime('%Y%m%d-%H%M')}.md"
    out.write_text(md, encoding="utf-8")

    # 경고 등급(warn_only)은 종료 코드에 넣지 않는다 — 회귀 게이트는 확실한 위반만 센다.
    fails = sum(1 for _, fs in layer_a for f in fs if f.is_failure) + sum(
        1 for _, _, fs in layer_b for f in fs if f.is_failure
    )
    warns = sum(1 for _, fs in layer_a for f in fs if f.mark == "WARN") + sum(
        1 for _, _, fs in layer_b for f in fs if f.mark == "WARN"
    )
    print(f"결과: {out}")
    print(f"실패 {fails}건 · 경고 {warns}건")
    return fails


if __name__ == "__main__":
    raise SystemExit(main())
