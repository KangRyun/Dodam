"""아동 화면 위험 문구 비노출 가드 (S15P11B209-597).

계약 원칙(ai-conversation-question-contract §5): "기술 오류·차단 사유를 아동에게 노출하지 않는다."
아이 화면에 뜨는 텍스트(질문·선택 칩)에는 다음이 절대 새면 안 된다:
  1) 내부 사유·오류 코드(SELF_HARM_RISK, AI_SAFETY_POLICY_BLOCKED 등) — 대문자 스네이크 토큰.
  2) 보호자·전문가용 위기 경고/안내 문구(신고·상담 전화·핫라인·"위험 감지"·"보호자에게 알림" 등).
     같은 위기라도 아이에겐 부드러운 지지만(S15P11B209-593), 경고·안내는 보호자 경로(S15P11B209-598)로.

이 모듈은 그런 '아동 부적절 신호'를 규칙으로 탐지하는 1차 가드다. question_safety 파이프라인의
마지막 단계로 결합돼, 걸리면 질문을 차단(→422→BE 폴백 템플릿)해 아이 화면엔 뜨지 않게 한다.

과잉 차단 방지: 아이 그림 대화에 자연스러운 낱말(예: '경찰차', '위험한 곳')까지 막지 않도록
'경고·신고·안내'를 이루는 형태로 좁힌다 — 바로 그 phrasing만 잡는다.

가드레일: 원문은 로그로 남기지 않는다 — 매칭된 사유 '코드/패턴'만 남긴다.
"""

from __future__ import annotations

import re

# 내부 사유·오류 코드 유출. 한국어 아동 질문엔 자연히 나오지 않는다.
# 예: AI_SAFETY_POLICY_BLOCKED, SELF_HARM_RISK, DIAGNOSTIC_LANGUAGE, CRISIS_CONTENT.
# ⚠️ question_safety 파이프라인은 정화(sanitize)로 밑줄을 지운 텍스트를 넘긴다
#    (SELF_HARM_RISK → SELFHARMRISK). 그래서 밑줄형과 '연속 대문자 6+'형을 함께 잡는다.
_REASON_CODE = re.compile(r"[A-Z][A-Z0-9]*(?:_[A-Z0-9]+)+|[A-Z]{6,}")

# 보호자·전문가용 위기 경고/안내 문구. 아이 화면에 뜨면 겁을 주거나 낙인이 된다.
_RISK_NOTICE = [
    r"신고",  # 학대/위기 신고 안내
    r"상담\s*(전화|센터|기관)",
    r"핫라인",
    r"자살\s*예방",
    # 앞뒤 숫자를 배제해 더 긴 수(1091·2109 등) 안에서 걸리지 않게 한다.
    r"(?<!\d)109(?!\d)",  # 자살예방 상담전화(2024-01 통합 번호)
    # 구 번호도 계속 막는다 — 옛 문구·캐시·외부 인용이 아이 화면으로 흘러도 걸러야 한다.
    r"1393",  # 구 자살예방상담전화(109로 통합)
    r"1577\s*-?\s*1391",  # 구 중앙아동보호전문기관(폐지)
    r"아동\s*학대",
    r"위기\s*(신호|상황|개입|경보|징후)",
    r"위험\s*(신호|징후)",
    r"위험(이|을)?\s*감지",
    r"자해\s*(위험|징후|신호)",
    r"보호자(에게|께)\s*(알림|알렸|연락|안내)",
    r"부모님?(께|에게)\s*(알림|알렸|연락)",
    r"전문가(에게|와|의)\s*(상담|연계|의뢰)",
    r"오류(가|를)?\s*(발생|생겼|났)",
    r"차단\s*(되었|됐)",
    r"에러",
]
_RISK_NOTICE_RE = [re.compile(p) for p in _RISK_NOTICE]


def find_child_unsafe(text: str) -> list[str]:
    """아이 화면에 노출되면 안 되는 신호를 찾아 매칭된 '코드/패턴' 목록을 반환한다(없으면 빈 목록).

    반환값은 코드·패턴이라 로그에 남겨도 원문이 새지 않는다.
    """
    if not text:
        return []
    hits: list[str] = []
    if _REASON_CODE.search(text):
        hits.append("REASON_CODE")
    hits.extend(rx.pattern for rx in _RISK_NOTICE_RE if rx.search(text))
    return hits


def contains_child_unsafe(*texts: str) -> bool:
    """주어진 텍스트 중 하나라도 아동 화면 부적절 신호를 담으면 True."""
    return any(find_child_unsafe(t) for t in texts if t)
