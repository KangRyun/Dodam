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

⚠️ 수신자는 사유 코드마다 다르다 (S15P11B209-890). 위기 신호라고 전부 보호자에게 보내지 않는다.

    자해·위기 의도  → 보호자 안내(GuardianAlert). 보호자가 곁에서 돕는 것이 아이에게 이롭다.
    학대 진술       → 보호자 자동 전달 금지(ExpertOnlyNote). 전문가 검토 경로로만 남긴다.

   왜 학대는 다른가: 아동 학대는 **가해자가 보호자 본인일 가능성**이 있는 유형이다. "아이가
   이야기했다"는 사실이 가해자에게 자동 통지되면 입막음·보복으로 이어져 아이가 더 위험해지고,
   신고 자원 안내가 가해자 손에 먼저 들어간다. 그래서 이 모듈은 학대에 대해 보호자용 안내를
   만들지 않는다 — 신호를 버리는 것이 아니라 **수신자를 바꾸는 것**이다.

   ⚠️ 되돌리지 말 것: "학대도 보호자에게 알려야 하지 않나"는 직관은 위 위험을 놓친 것이다.
      보호자에게 알릴지는 안전한 수신자인지 사람이 판단한 뒤에만 결정한다.

⚠️ 전달 경로(계약): 이 안내를 '보호자에게 실제로 띄우는' BE 배선(알림/화면 필드)은 계약 확장이
   필요한 공동 후속이다. 이 모듈은 그 문구를 만드는 AI 규칙까지를 책임진다.
   전문가 조회·검토 화면도 아직 없다 — ExpertOnlyNote는 현재 '저장·로그 신호'까지가 범위다.
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
    """**보호자에게 전달할** 위기 안내(검토된 템플릿에서 조립).

    아이 발화 원문은 담지 않는다 — reason_code와 일반적 서술만.
    이 타입으로 존재한다는 것 자체가 "보호자에게 보내도 되는 신호"라는 뜻이다.
    보호자에게 보내면 안 되는 사유 코드는 이 타입을 만들지 않는다(ExpertOnlyNote 참고).
    """

    reason_code: str
    severity: str
    title: str
    message: str
    action_steps: list[str]
    resources: list[CrisisResource] = field(default_factory=list)
    disclaimer: str = DISCLAIMER


@dataclass(frozen=True)
class ExpertOnlyNote:
    """보호자에게 **자동 전달하지 않는** 위기 기록 (S15P11B209-890).

    GuardianAlert와 의도적으로 다른 타입이다 — 같은 타입이면 보호자 전달 코드에 그대로 흘러들어
    갈 수 있다. 타입이 다르면 그 실수가 컴파일/리뷰 단계에서 눈에 띈다.

    담기는 것: 전문가 검토자가 상황을 파악할 수 있는 일반적 서술과 참고 자원.
    담기지 않는 것: 아이 발화 원문, 보호자에게 그대로 읽어줄 안내 문구.
    """

    reason_code: str
    severity: str
    title: str
    summary: str
    review_reason: str
    # 전문가 검토자 참고용 자원 — **보호자에게 자동 전달 금지**(수신자 판단 후 사람이 전달).
    resources: list[CrisisResource] = field(default_factory=list)
    requires_expert_review: bool = True
    guardian_auto_delivery_allowed: bool = False
    disclaimer: str = DISCLAIMER


# 공식 상담·신고 자원.
#
# ⚠️ 번호는 통폐합으로 바뀐다. 여기 값은 아래 '확인일' 기준이며, 고칠 때는 기관 공식 안내에서
#    자료 단위로 다시 확인하고 확인일·출처를 함께 갱신한다. "예전에 맞았다"는 근거가 아니다
#    (rag-corpus-policy.md 의 licenseVerifiedAt 과 같은 취지).
#    위기 안내에 죽은 번호가 실리면 그 안내는 도움이 아니라 해가 된다.
#
# 최종 확인: 2026-08-04 (S15P11B209-853)
#   - 자살예방 109: 2024-01-01 자 1393 등 8개 상담전화를 통합. 보건복지부 보도자료
#     https://www.mohw.go.kr/board.es?mid=a10503010100&bid=0027&act=view&list_no=1479607
#   - 정신건강 1577-0199 · 청소년 1388: 109 통합 대상이 아니며 각 영역에서 그대로 운영.
#   - 아동학대 신고 112: 아동학대 신고 창구가 112로 일원화됐다(아동권리보장원 공지).
#     구 중앙아동보호전문기관 대표번호 1577-1391 은 폐지돼 더 쓰지 않는다.
_R_SUICIDE = CrisisResource("자살예방 상담전화", "109", "24시간 무료 상담")
_R_MENTAL = CrisisResource("정신건강상담전화", "1577-0199", "24시간 정신건강 위기 상담")
_R_YOUTH = CrisisResource("청소년상담전화", "1388", "청소년·보호자 상담")
_R_REPORT_112 = CrisisResource("아동학대 신고", "112", "24시간 신고·상담")
_R_WELFARE = CrisisResource("보건복지상담센터", "129", "복지·위기 지원 안내")


# 보호자에게 자동 전달하지 않는 사유 코드 (S15P11B209-890).
# 여기 있는 코드는 _GUIDANCE(보호자 안내)에 **넣지 않는다** — 두 곳에 동시에 있으면 안 된다.
EXPERT_ONLY_REASONS = frozenset({crisis_detection.ABUSE_DISCLOSURE})


# 사유 코드 → 보호자 안내 템플릿. crisis_detection의 코드에 맞춘다(드리프트 방지 위해 상수 참조).
# ⚠️ EXPERT_ONLY_REASONS 의 코드는 여기 오지 않는다(모듈 하단 정합성 검증이 막는다).
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


# 사유 코드 → 전문가 전용 기록 (S15P11B209-890). 보호자 자동 전달 금지 대상만 들어간다.
_EXPERT_ONLY: dict[str, ExpertOnlyNote] = {
    crisis_detection.ABUSE_DISCLOSURE: ExpertOnlyNote(
        reason_code=crisis_detection.ABUSE_DISCLOSURE,
        severity=SEVERITY_HIGH,
        title="학대 관련 신호가 관찰됐어요 (전문가 검토 필요)",
        summary=(
            "활동 중 아이가 누군가에게 힘든 일을 겪었을 수 있는 이야기를 내비친 신호가 "
            "관찰됐습니다. 신호 유형만 기록하며, 아이가 한 말 자체는 담지 않습니다."
        ),
        review_reason=(
            "보호자가 안전한 수신자인지 확인되지 않은 상태에서는 보호자에게 자동으로 알리지 "
            "않습니다. 가해자가 보호자일 가능성이 있어, 자동 통지가 아이를 더 위험하게 만들 수 "
            "있습니다. 전달 여부는 사람이 판단합니다."
        ),
        resources=[_R_REPORT_112, _R_WELFARE, _R_YOUTH],
    ),
}


# 정합성 검증(모듈 로드 시점) — 한 코드가 두 경로에 동시에 있으면 즉시 실패한다.
# 보호자 안내 맵에 학대가 슬쩍 되돌아오는 회귀를 import 단계에서 막는다.
_overlap = set(_GUIDANCE) & set(_EXPERT_ONLY)
if _overlap:  # pragma: no cover - 설정 오류는 로드 시점에 드러난다
    raise AssertionError(f"보호자 안내와 전문가 전용에 동시에 있는 사유 코드: {sorted(_overlap)}")
_leaked = EXPERT_ONLY_REASONS & set(_GUIDANCE)
if _leaked:  # pragma: no cover
    raise AssertionError(f"보호자 자동 전달 금지 코드가 보호자 안내에 있다: {sorted(_leaked)}")


def guidance_for(reason_code: str | None) -> GuardianAlert | None:
    """**보호자에게 전달할** 안내를 반환한다(없으면 None).

    반환값은 사전 검토된 템플릿이라 아이 발화 원문을 담지 않는다.

    ⚠️ None인 경우가 두 가지다 — 모르는 코드이거나, **보호자에게 보내면 안 되는 코드**다
       (학대 진술 등 EXPERT_ONLY_REASONS). 어느 쪽이든 보호자에게 보낼 것이 없다는 뜻이라
       이 함수만 쓰는 호출부는 기본적으로 안전하다. 신호를 놓치지 않으려면
       expert_note_for()도 함께 확인한다.
    """
    if not reason_code:
        return None
    return _GUIDANCE.get(reason_code)


def expert_note_for(reason_code: str | None) -> ExpertOnlyNote | None:
    """전문가 검토 경로로만 남길 기록을 반환한다(해당 없으면 None) (S15P11B209-890).

    보호자에게 그대로 노출하지 않는다 — 전달 여부는 안전한 수신자인지 사람이 판단한 뒤 정한다.
    """
    if not reason_code:
        return None
    return _EXPERT_ONLY.get(reason_code)


def has_guidance(reason_code: str | None) -> bool:
    """해당 사유 코드에 **보호자에게 전달할** 안내가 있으면 True.

    학대 진술처럼 보호자 자동 전달을 금지한 코드는 False다 — 신호가 없다는 뜻이 아니라
    보호자에게 보낼 것이 없다는 뜻이다. 신호 존재 여부는 is_known_reason()으로 본다.
    """
    return guidance_for(reason_code) is not None


def requires_expert_review(reason_code: str | None) -> bool:
    """전문가 검토로 보내야 하는 사유 코드면 True (리포트 expertReviewRequired 신호)."""
    note = expert_note_for(reason_code)
    return note is not None and note.requires_expert_review


def guardian_auto_delivery_allowed(reason_code: str | None) -> bool:
    """보호자에게 자동으로 알려도 되는 사유 코드면 True.

    호출부가 "안내가 없다"와 "보내면 안 된다"를 구분해 처리할 수 있게 명시적으로 제공한다.
    """
    if not reason_code:
        return False
    if reason_code in EXPERT_ONLY_REASONS or reason_code in _EXPERT_ONLY:
        return False
    return reason_code in _GUIDANCE


def is_known_reason(reason_code: str | None) -> bool:
    """이 모듈이 아는 위기 사유 코드면 True(보호자 안내든 전문가 전용이든)."""
    if not reason_code:
        return False
    return reason_code in _GUIDANCE or reason_code in _EXPERT_ONLY


if __name__ == "__main__":
    # 스모크 테스트:  cd ai && python crisis_guidance.py
    for code in (
        crisis_detection.SELF_HARM_RISK,
        crisis_detection.ABUSE_DISCLOSURE,
        crisis_detection.CRISIS_INTENT,
    ):
        assert is_known_reason(code), code
        alert = guidance_for(code)
        if alert is not None:
            print(f"[보호자 안내 · {alert.severity}] {code} — {alert.title}")
            print(f"  {alert.message}")
            for step in alert.action_steps:
                print(f"  · {step}")
            for r in alert.resources:
                print(f"  ☎ {r.name} {r.contact} ({r.note})")
        else:
            # 보호자 자동 전달 금지 코드 — 전문가 검토 경로로만 남는다(S15P11B209-890).
            note = expert_note_for(code)
            assert note is not None, code
            assert not guardian_auto_delivery_allowed(code), code
            print(f"[전문가 전용 · {note.severity}] {code} — {note.title}")
            print(f"  {note.summary}")
            print(f"  보호자 자동 전달 보류 사유: {note.review_reason}")
            print(f"  전문가 검토 필요: {note.requires_expert_review}")
            for r in note.resources:
                print(f"  ☎(검토자 참고) {r.name} {r.contact} ({r.note})")
        print("-" * 60)
