"""생성 질문 안전 판정 파이프라인 (S15P11B209-596).

내부 계약 경로(question_service.generate)가 GMS로 만든 '아이에게 건넬 질문'을 아동 화면에
내보내기 전에 통과시키는 안전 판정 단계다. 흩어져 있던 규칙(정화·진단표현·위기 소재)을 한
순서 있는 파이프라인으로 묶어 결정적(deterministic)으로 판정한다 — LLM 재호출 없음.

역할 분담(팀 원칙): 판정은 규칙 기반, LLM은 문장화만. 이 모듈은 이미 검증된 규칙 검출기를
조립할 뿐, 새 판정 로직을 LLM에 맡기지 않는다.
- answer_check.sanitize: TTS로 곤란한 이모지·마크업 제거(형식 정화).
- answer_check.find_violations: 진단·심리해석·검사 채점 표현(아동에게 절대 금지).
- crisis_detection.detect: 자해·학대·위기 소재를 질문이 되레 담고 있는지(모델 오작동 방어).

판정 순서(먼저 걸리는 것이 사유가 된다):
  1) 형식 정화 → 정화본을 이후 단계·최종 출력에 쓴다.
  2) 진단·심리해석 표현 → 차단(DIAGNOSTIC_LANGUAGE).
  3) 위기 소재를 담은 질문 → 차단(CRISIS_CONTENT).
  4) 통과 → 정화본을 안전한 질문으로 돌려준다.

처리(차단 시): question_service가 SafetyBlockedError로 올려 엔드포인트가 422
AI_SAFETY_POLICY_BLOCKED로 매핑한다 → BE가 저장 없이 폴백 템플릿으로 대체한다.
(정화 후 빈 질문은 '안전 위반'이 아니라 '빈 출력'이라 여기서 다루지 않고 호출자가
기존 빈 응답 경로(UpstreamError → 폴백)로 처리한다.)

가드레일: 질문 원문은 로그로 남기지 않는다 — 매칭된 사유 '코드'만 남긴다.
"""

from __future__ import annotations

from dataclasses import dataclass

import answer_check
import crisis_detection

# 차단 사유 코드(SafetyResult.blockReasonCode로 전달). BE·후속 위기 안내가 이 값으로 분기한다.
DIAGNOSTIC_LANGUAGE = "DIAGNOSTIC_LANGUAGE"  # 진단·심리해석·검사 채점 표현
CRISIS_CONTENT = "CRISIS_CONTENT"  # 자해·학대·위기 소재를 질문이 담음

# 규칙 묶음의 버전 태그 — 규칙이 바뀌면 올려 재현성을 기록한다. 요청의 safety_rule_version과
# 별개로, '이 파이프라인이 어떤 규칙 집합으로 판정했는지'를 나타낸다.
PIPELINE_VERSION = "question-safety-1.0.0"


@dataclass(frozen=True)
class SafetyVerdict:
    """안전 판정 결과.

    status: "PASSED" | "BLOCKED".
    sanitized_text: 형식 정화까지 마친 질문 — PASSED면 이 값을 아동 화면에 쓴다.
    block_reason_code: 차단 사유 코드(PASSED면 None).
    """

    status: str
    sanitized_text: str
    block_reason_code: str | None = None

    @property
    def blocked(self) -> bool:
        return self.status == "BLOCKED"


def evaluate(question_text: str) -> SafetyVerdict:
    """생성 질문을 정화·판정한다(LLM 호출 없음, 결정적).

    Args:
        question_text: GMS가 생성한 질문 원문.

    Returns:
        SafetyVerdict. 차단이어도 sanitized_text는 채워 돌려준다(로그·감사용이 아니라
        호출자가 필요 시 참조할 수 있게 — 단, 차단이면 아동 화면엔 쓰지 않는다).
    """
    cleaned = answer_check.sanitize(question_text or "")

    # 진단·심리해석·검사 채점 표현 — 아동에게 절대 나가면 안 된다.
    if answer_check.find_violations(cleaned):
        return SafetyVerdict("BLOCKED", cleaned, DIAGNOSTIC_LANGUAGE)

    # 위기 소재(자해·학대·위기)를 질문이 되레 담고 있으면 차단 — 모델 오작동 방어.
    if crisis_detection.detect(cleaned):
        return SafetyVerdict("BLOCKED", cleaned, CRISIS_CONTENT)

    return SafetyVerdict("PASSED", cleaned, None)


if __name__ == "__main__":
    # 스모크 테스트:  cd ai && python question_safety.py
    samples = [
        "우와, 멋진 집이네! 누가 살고 있어? 😊",  # 정화만 → PASSED
        "이 그림은 불안을 의미하니? 😢",          # 진단 표현 → BLOCKED
        "혹시 죽고 싶었던 적 있어?",              # 위기 소재 → BLOCKED
        "**이 집에는** (누가) 살아?",             # 마크업 정화 → PASSED
    ]
    for s in samples:
        v = evaluate(s)
        print(f"IN : {s}")
        print(f"OUT: status={v.status} reason={v.block_reason_code} text={v.sanitized_text!r}")
        print("-" * 50)
