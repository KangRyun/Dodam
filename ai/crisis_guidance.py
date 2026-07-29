"""보호자 위기 안내 문구 생성 규칙 (S15P11B209-598).

위기 신호(자해·학대·위기)를 감지하면(crisis_detection, S15P11B209-593) 아이에게는 대화를 끊지
않는 부드러운 지지 응답만 주고(child_screen_guard로 경고 문구는 아이 화면에서 비노출, 597),
'무슨 일이 있었고 어떻게 도우면 되는지'는 이 모듈이 만드는 보호자용 안내로 전한다.

역할 분담(팀 원칙): 안전·위기 문구는 LLM 즉흥 생성이 아니라 사전 검토된 규칙 템플릿을 쓴다.
위기 상황에서 LLM이 잘못된 조언·진단을 지어내는 위험을 원천 차단하기 위함이다. 이 모듈은
crisis_detection의 사유 코드를 받아 미리 검토된 GuardianAlert(안내 메시지·행동 단계·상담 자원)로
매핑할 뿐, 새 문구를 생성하지 않는다.

원칙:
- 비진단·비낙인: "장애다/위험하다"라고 단정하지 않고, 관찰된 '신호'와 따뜻한 대응을 안내한다.
- 개인정보 보호: 아이 발화 원문은 담지 않는다 — 신호 유형만 일반적으로 서술한다.
- 실질적 도움: 상황에 맞는 공식 상담·신고 자원(전화번호)을 함께 제공한다.

⚠️ 전달 경로(계약): 이 안내를 '보호자에게 실제로 띄우는' BE 배선(알림/화면 필드)은 계약 확장이
   필요한 공동 후속이다. 이 모듈은 그 문구를 만드는 AI 규칙까지를 책임진다.
"""

from __future__ import annotations

from dataclasses import dataclass, field

import crisis_detection

# 심각도 — 보호자 알림 우선순위·표시 강조에 쓴다(BE가 소비할 때 참고).
SEVERITY_HIGH = "HIGH"  # 즉각적 안전 우려(자해·학대) — 빠른 확인·전문가 연계 권고
SEVERITY_ELEVATED = "ELEVATED"  # 정서적 소진·고립 신호 — 주의 깊은 관찰·대화 권고

# 공통 고지 — 관찰 신호일 뿐 진단이 아님을 분명히 한다(리포트 고지와 같은 취지).
DISCLAIMER = (
    "이 안내는 그림·대화 활동 중 관찰된 신호를 바탕으로 한 것으로, 전문적 진단이 아닙니다. "
    "아이의 상태가 걱정되시면 아동·청소년 전문가와 상담해 주세요."
)


@dataclass(frozen=True)
class CrisisResource:
    """보호자에게 안내할 공식 상담·신고 자원."""

    name: str
    contact: str
    note: str = ""


@dataclass(frozen=True)
class GuardianAlert:
    """보호자용 위기 안내(검토된 템플릿에서 조립).

    아이 발화 원문은 담지 않는다 — reason_code와 일반적 서술만.
    """

    reason_code: str
    severity: str
    title: str
    message: str
    action_steps: list[str]
    resources: list[CrisisResource] = field(default_factory=list)
    disclaimer: str = DISCLAIMER


# 자주 쓰는 공식 상담·신고 자원(2026 기준 국내 대표 번호).
_R_SUICIDE = CrisisResource("자살예방상담전화", "1393", "24시간 무료 상담")
_R_MENTAL = CrisisResource("정신건강상담전화", "1577-0199", "24시간 정신건강 위기 상담")
_R_YOUTH = CrisisResource("청소년상담전화", "1388", "청소년·보호자 상담")
_R_CHILD_PROTECT = CrisisResource("아동보호전문기관", "1577-1391", "아동학대 상담·지원")
_R_REPORT_112 = CrisisResource("아동학대 신고", "112", "긴급 시 즉시 신고")
_R_WELFARE = CrisisResource("보건복지상담센터", "129", "복지·위기 지원 안내")


# 사유 코드 → 보호자 안내 템플릿. crisis_detection의 코드에 맞춘다(드리프트 방지 위해 상수 참조).
_GUIDANCE: dict[str, GuardianAlert] = {
    crisis_detection.SELF_HARM_RISK: GuardianAlert(
        reason_code=crisis_detection.SELF_HARM_RISK,
        severity=SEVERITY_HIGH,
        title="아이의 마음을 살펴봐 주세요",
        message=(
            "아이가 활동 중 스스로를 많이 힘들어하는 마음을 내비쳤어요. "
            "놀라거나 다그치지 마시고, 아이가 안전하다고 느끼도록 곁에서 차분히 이야기를 "
            "들어봐 주세요. 마음이 무겁다는 신호일 수 있으니 이른 시일에 전문가의 도움을 "
            "받아보시길 권해요."
        ),
        action_steps=[
            "혼자 두지 말고 지금 아이 곁에서 따뜻하게 안심시켜 주세요.",
            "왜 그랬냐고 캐묻기보다 \"많이 힘들었구나\"라고 마음을 먼저 알아주세요.",
            "가까운 시일에 소아·청소년 정신건강 전문가와 상담을 예약해 주세요.",
        ],
        resources=[_R_SUICIDE, _R_MENTAL, _R_YOUTH],
    ),
    crisis_detection.ABUSE_DISCLOSURE: GuardianAlert(
        reason_code=crisis_detection.ABUSE_DISCLOSURE,
        severity=SEVERITY_HIGH,
        title="아이가 힘든 경험을 이야기했어요",
        message=(
            "아이가 활동 중 누군가에게 힘든 일을 겪었을 수 있는 이야기를 내비쳤어요. "
            "아이를 탓하지 마시고, 용기 내어 이야기한 것을 따뜻하게 지지해 주세요. "
            "아이의 안전이 우선이며, 필요하면 전문기관의 도움을 받을 수 있어요."
        ),
        action_steps=[
            "아이가 안전한 곳에 있는지 먼저 확인하고 안심시켜 주세요.",
            "이야기해 줘서 고맙다고 말하고, 아이의 말을 끝까지 들어주세요.",
            "안전이 우려되면 아동보호전문기관에 상담하거나 긴급 시 112에 신고해 주세요.",
        ],
        resources=[_R_CHILD_PROTECT, _R_REPORT_112, _R_WELFARE],
    ),
    crisis_detection.CRISIS_INTENT: GuardianAlert(
        reason_code=crisis_detection.CRISIS_INTENT,
        severity=SEVERITY_ELEVATED,
        title="아이의 감정을 함께 살펴봐 주세요",
        message=(
            "아이가 활동 중 마음이 지치거나 외롭다고 느끼는 신호를 보였어요. "
            "오늘 아이의 하루가 어땠는지 편안하게 이야기 나누며 마음을 들여다봐 주세요. "
            "신호가 이어진다면 전문 상담의 도움을 받아보시는 것도 좋아요."
        ),
        action_steps=[
            "조용한 시간에 아이와 눈을 맞추고 요즘 기분을 물어봐 주세요.",
            "감정을 부정하지 말고 \"그럴 수 있어\"라고 있는 그대로 받아주세요.",
            "힘들어하는 모습이 계속되면 청소년상담전화 등 전문 상담을 이용해 주세요.",
        ],
        resources=[_R_YOUTH, _R_MENTAL],
    ),
}


def guidance_for(reason_code: str | None) -> GuardianAlert | None:
    """위기 사유 코드에 맞는 보호자 안내를 반환한다(모르는 코드·None이면 None).

    반환값은 사전 검토된 템플릿이라 아이 발화 원문을 담지 않는다.
    """
    if not reason_code:
        return None
    return _GUIDANCE.get(reason_code)


def has_guidance(reason_code: str | None) -> bool:
    """해당 사유 코드에 대한 보호자 안내가 정의돼 있으면 True."""
    return guidance_for(reason_code) is not None


if __name__ == "__main__":
    # 스모크 테스트:  cd ai && python crisis_guidance.py
    for code in (
        crisis_detection.SELF_HARM_RISK,
        crisis_detection.ABUSE_DISCLOSURE,
        crisis_detection.CRISIS_INTENT,
    ):
        alert = guidance_for(code)
        assert alert is not None
        print(f"[{alert.severity}] {code} — {alert.title}")
        print(f"  {alert.message}")
        for step in alert.action_steps:
            print(f"  · {step}")
        for r in alert.resources:
            print(f"  ☎ {r.name} {r.contact} ({r.note})")
        print("-" * 60)
