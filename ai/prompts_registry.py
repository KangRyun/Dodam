"""프롬프트 파일 로딩·버전 관리 중앙화 (S15P11B209-595).

각 클라이언트(llm_client·vlm_client·report_client·question_service)가 흩어져 관리하던
프롬프트 로딩·버전 문자열을 한곳으로 모은다. 분석·질문 결과에 promptVersion을 저장해
"어떤 프롬프트로 뽑힌 결과인지" 재현·추적할 수 있게 한다.

버전 = 수동 semver + 내용 해시(예: "1.1.0+ab12cd34").
- semver: 프롬프트를 의미 있게 바꿀 때 _PROMPT_SEMVER에서 올린다.
- 내용 해시: 파일 내용에서 자동 계산한다. semver를 깜빡 안 올려도 내용이 바뀌면
  해시가 달라져 결과 추적이 끊기지 않는다(이중 안전장치).

여러 파일을 함께 쓰는 경로는 두 가지 표현을 갖는다(S15P11B209-819).
- composite_version(): 정본. 전부 풀어 쓴 문자열이라 사람이 그대로 읽을 수 있다. 로그·진단용.
- short_version(): BE에 저장되는 값. 조합 전체를 해시 하나로 접어 길이를 상수로 만든다.
  정본을 그대로 저장하면 길이가 파일 개수에 비례해 늘어나 컬럼을 넘긴다(아래 참고).

파일명은 ai/prompts/<name>.txt. torch·GMS 의존성이 없어 어디서든 import된다.
"""

from __future__ import annotations

import hashlib
import re
from functools import lru_cache
from pathlib import Path

PROMPT_DIR = Path(__file__).parent / "prompts"

# [[KEY]] 머리표로 프롬프트 한 파일 안에 여러 구획을 두는 규약(conversation_tone·
# htp_question_bank·activity_block). 한 파일에 모아 두면 구획들을 나란히 놓고 균형을 볼 수 있고,
# 파일 하나만 버전 추적하면 된다.
_SECTION_HEADER = re.compile(r"^\[\[([A-Z_]+)\]\]$", re.M)

# 프롬프트 파일별 의미 버전(semver). 프롬프트를 의미 있게 바꾸면 여기 값을 올린다.
# ⚠️ 키를 추가/삭제하면 verify_prompt_files()가 파일과의 불일치를 잡는다.
_PROMPT_SEMVER: dict[str, str] = {
    # 대화 프롬프트도 활동 유형별로 갈라진다(S15P11B209-786) — 대화의 '목적'이 다르다:
    #   HTP는 그림 자체가 궁금해 그림 안에서 좁혀 가고, 그림일기는 그림을 소재 삼아
    #   그날 일·아이 마음으로 넓혀 간다. 한 문장으로 두 목적을 시키면 어느 쪽도 안 된다.
    # 구 first_question(1.3.0)·conversations(1.4.0)를 갈라 만든 것이라 2.0.0에서 시작한다.
    # 2.1.0(HTP만): 첫 질문이 12/12 "오늘은 뭘 그렸어?"로 고정되던 것을 고쳤다(808 F-1).
    #   완성문을 예시로 두 번 적어 둔 것이 원인 — 모델이 규칙을 해석하는 대신 눈앞의 문장을
    #   복사했다. 세부가 있으면 반드시 그것을 묻게 하고, 질문 뱅크를 방향 힌트로 참조시킨다.
    # 2.2.0(HTP, S15P11B209-808): 이유 질문을 첫 질문에서 제외하고, 아이가 실마리를 먼저
    #   말한 경우에만 대화당 1회로 제한한다. 금지 예시 문장 자체도 앵커가 되므로 지웠다.
    "first_question_htp": "2.2.0",
    # 2.1.0(그림일기, S15P11B209-808): "오늘 있었던 일" 전제를 버리고 그림 속 이야기에서
    #   시작해, 실제 경험인지 상상인지 한 번 확인한 뒤 그 흐름을 따라간다.
    "first_question_diary": "2.1.0",
    # S15P11B209-831: 명시적인 질문 건너뛰기 의사를 내용 답변과 구분하고, 직전 질문을
    #   표현만 바꿔 반복하지 않은 채 아직 다루지 않은 방향으로 전환한다.
    "conversations_htp": "2.3.0",
    "conversations_diary": "2.2.0",
    # HTP 표준 사후질문(PDI)을 아동용으로 포장한 주제별 질문 뱅크(S15P11B209-811).
    # 현재 주제 구획 하나만 싣는다 — 셋을 다 실으면 주제 이탈(709 계열)이 다시 열린다.
    # 1.1.0(808): PDI 문항에서 "왜 이렇게 그렸어?"를 제외했다 — 뱅크가 이유 질문의 출처였다.
    "htp_question_bank": "1.1.0",
    # 공유 규칙(이름·분석결과 취급·출력 형식)은 변형 뒤에 이어붙는다. 문장 수·길이는
    # 여기서 정하지 않고 conversation_tone에 위임한다(구 프롬프트의 "한 문장만"이
    # UPPER_ELEMENTARY "한두 문장"과 어긋나던 것을 소유자를 하나로 만들어 없앴다).
    # 1.1.0(808): 추궁형 이유 질문을 금지 예시로도 노출하지 않고 긍정형 행동 지시로 바꾼다.
    "conversation_common": "1.1.0",
    # 구 question_service._activity_block 코드 문자열을 옮긴 것(S15P11B209-832).
    #   GPT에 나가는 지시문인데 버전 추적 밖이라, 788에서 문구를 크게 고쳐도 promptVersion이
    #   그대로였다 — 버전은 같은데 동작이 다른 상태였다. 이제 llm_client.prompt_names_for()에
    #   포함돼 문구가 바뀌면 다이제스트가 움직인다.
    "activity_block": "1.0.0",
    # 구 question_service._DIFFICULTY_RULES를 프롬프트 파일로 옮긴 것(버전 추적·draft 경로 반영).
    #   구 PRESCHOOL "10자 안팎"은 대화 프롬프트의 "반응한 다음 질문을 이어줘"와 동시에
    #   만족할 수 없어, 반응/질문 몫을 나눠 "두 문장 이내"로 고쳤다.
    "conversation_tone": "1.0.0",
    # 1.1.0: "중립적으로 반응"(대화 프롬프트의 '따뜻하게 반응'과 모순) 제거,
    #   길이 규칙 제거(각 프롬프트·난이도 블록이 소유), 입력 취급·개인정보 규칙 추가.
    # 1.2.0(S15P11B209-811): 금지 규칙의 '적용 대상'을 아이 본인으로 좁혔다. 평가·감정·슬픈
    #   주제 금지가 그림 속 인물에까지 걸려 HTP 사후질문(PDI)을 통째로 막고 있었다.
    #   진단·점수화·개인정보·외부 접촉 금지는 예외 없는 절대 규칙으로 그대로 둔다.
    "guardrails": "1.2.0",
    # 그림 서술은 활동 유형별로 갈라진다 — HTP는 탐지 목록에 고정, 그림일기는 탐지를
    # 힌트로만 쓴다(sketch 가중치가 자유 그림을 자주 놓쳐 목록 고정이 서술을 죽였다).
    # 1.1.0(S15P11B209-788 G): 세부가 흐려 확실한 것이 없을 때의 탈출구 추가 —
    #   "한두 가지는 꼭 넣어" ↔ "확실하지 않으면 빼"가 동시 충족 불가였다.
    "drawing_description_htp": "1.1.0",
    "drawing_description_diary": "1.0.0",
    # 답변 칩 2차 호출 프롬프트(S15P11B209-788 부수). question_service 코드 상수였던 것을
    # 파일로 옮겼다 — 아동 화면에 나갈 칩을 만드는 프롬프트가 버전 추적 밖에 있었다.
    #   ⚠️ 고정 안전 문구(CRISIS_SAFE_QUESTION·REASK_QUESTION·FALLBACK_QUESTION·
    #      DEFAULT_FOLLOW_UP_QUESTION)는 의도적으로 코드 상수로 남긴다 — 그건 '프롬프트'가
    #      아니라 LLM을 못 믿을 때 코드가 보장하는 출력이다(report_client 모듈 docstring).
    #      파일로 옮기면 프롬프트처럼 자유롭게 편집되어 그 보장이 약해진다.
    "answer_chips": "1.0.0",
    # 리포트도 활동 유형별로 갈라진다 — 근거 블록 구성이 다르고(주제별 vs 단일),
    # RAG 근거는 HTP 경로에만 실린다. 공통 규칙·JSON 스키마는 report_common이 소유한다.
    # S15P11B209-601: 진단 표현 금지 강화·한계 고지·후속 질문 목적 명시(구 report 1.2.0 계승).
    # 1.4.0(S15P11B209-788 E·F): 걱정 신호 배출구 두 곳의 역할을 갈라 명시("로만" 제거),
    #   형식적 분석 수치는 사실 자리·수치와 감정의 연결은 해석 자리로 자리를 못박음.
    # 1.5.0(S15P11B209-826): 렌더링 설명을 BE 실태에 맞춰 3갈래로 교정했다. 구 문구는 7항목 중
    #   4.5개가 거짓이었다 — overallSummary "리포트 맨 위"·positiveSignals "'아이의 좋은 모습'
    #   영역"·features "'관찰된 특징' 카드"는 보호자 화면에 존재하지 않는다(§13.1이 AI 관찰 초안을
    #   전문가 계층에 두고 REPORT-03이 미구현). 화면에 도달하는 것은 activityNotes·summaryText·
    #   followUpGuides.guidance 셋뿐이라 그쪽으로 공을 몰고, NOT NULL 필드와 조용히 잘리는
    #   길이 상한을 숫자로 명시했다.
    # 1.6.0(S15P11B209-808): 그림·형식 지표 기반 감정 추론은 유지하되, 단일 신호 추론을
    #   금지하고 독립 신호 2개 이상이 같은 방향일 때의 활동 한정 해석으로 범위를 좁힌다.
    # 1.7.0(2026-08-03 방침 완화 — "해석하지 않는다" → "과대해석만 피한다"):
    #   두 곳이 해석을 과하게 잠그고 있었다.
    #   (1) visibilityScope 기준이 "임상적으로 해석될 여지가 있으면 EXPERT_ONLY"·"애매하면
    #       보수적으로 EXPERT_ONLY"라, 근거를 갖춘 해석까지 전문가 쪽으로 빠져 보호자 화면에서
    #       사라졌다. 기준을 '주제가 무거운가' → '근거가 evidenceSummary 에 있는가'로 바꿨다.
    #   (2) "감정 해석은 긍정·중립을 기본으로"가 우려 소견을 전량 전문가 채널로 몰아, 보호자
    #       리포트가 늘 좋은 말만 하게 만들었다. 관찰된 대로 쓰되 낙인 없이 여지 표현으로.
    #   ⚠️ 단일 신호 추론 금지·활동 한정 표현(1.6.0)과 진단명·점수·낙인 금지는 그대로 둔다 —
    #      그게 이번 완화의 안전판이다. 코드 필터(report_safety)는 이미 여지 표현을 통과시키므로
    #      변경하지 않았다(과대해석만 잡는 규칙이라 새 방침과 이미 정합).
    "report_common": "1.7.0",
    # 1.4.0(826): 보호자 화면에 나가는 셋도 그림 내용에 근거하도록 지시 추가 —
    #   구 문구는 전문가 전용 필드만 "구체적으로 쓴다"고 해 노력 배분이 기울었다.
    # 1.5.0(2026-08-03 방침 완화 — report_common 1.7.0과 같은 결정):
    #   (1) 교차 비교 전면 금지를 풀었다. HTP인데 세 장을 아우르는 문장이 한 줄도 안 나오고
    #       있었다 — overallSummary 에서 종합하되 각 그림의 관찰 사실을 근거로 들게 했다.
    #       "차이 자체를 심리 상태로 단정" 금지는 남겨 과대해석을 막는다.
    #   (2) 부위의 상징 의미를 '무엇을 눈여겨볼지' 고르는 내부 기준으로만 허용한다(어휘 힌트).
    #       상징의 뜻 자체는 문장에 적지 않는다 — 적는 순간 리포트가 검사 해석으로 읽힌다.
    #       ⚠️ 금지 예시 문장을 적지 않은 것은 의도다. 808에서 확인했듯 금지 예시 자체가
    #          앵커가 되어 모델이 그 문장을 복사한다.
    #   (3) RAG 근거를 "어휘 보조로만"에서 "관찰을 일반 지식에 비추어 설명"으로 넓혔다.
    #       자료의 권위로 아이를 단정하는 문장 금지는 유지.
    "report_htp": "1.5.0",
    "report_diary": "1.4.0",
}

_UNKNOWN_SEMVER = "0.0.0"


@lru_cache(maxsize=None)
def load(name: str) -> str:
    """ai/prompts/<name>.txt 를 읽어 캐시한다(서버 기동 중 파일은 안 바뀐다고 가정)."""
    return (PROMPT_DIR / f"{name}.txt").read_text(encoding="utf-8").strip()


@lru_cache(maxsize=None)
def sections(name: str) -> dict[str, str]:
    """[[KEY]] 머리표로 나뉜 프롬프트 → {KEY: 본문}. 머리표 앞의 설명 문단은 버린다.

    구획을 고르는 소비자가 여럿이라(llm_client의 말투·질문 뱅크, question_service의 활동 블록)
    파싱을 여기 둔다 — 프롬프트 파일의 구조는 로딩·버전과 함께 레지스트리가 소유한다.
    """
    text = load(name)
    headers = list(_SECTION_HEADER.finditer(text))
    return {
        match.group(1): text[
            match.end() : (headers[i + 1].start() if i + 1 < len(headers) else len(text))
        ].strip()
        for i, match in enumerate(headers)
    }


@lru_cache(maxsize=None)
def content_hash(name: str) -> str:
    """프롬프트 내용의 짧은 SHA-256 해시(앞 8자리). 내용이 바뀌면 값이 달라진다."""
    return hashlib.sha256(load(name).encode("utf-8")).hexdigest()[:8]


def version(name: str) -> str:
    """단일 프롬프트의 버전 문자열: "<semver>+<content_hash>"."""
    semver = _PROMPT_SEMVER.get(name, _UNKNOWN_SEMVER)
    return f"{semver}+{content_hash(name)}"


def composite_version(*names: str) -> str:
    """여러 프롬프트를 함께 쓰는 경로(예: 질문 생성)의 통합 버전.

    "name@<version>" 을 프롬프트 이름순으로 정렬해 이어붙인다 — 어떤 파일 조합·내용으로
    생성됐는지 한 문자열로 재현 가능하게 한다.

    ⚠️ 이건 정본이라 길이가 파일 개수에 비례한다. 저장·전송에는 short_version()을 쓴다.
    """
    return ";".join(f"{name}@{version(name)}" for name in sorted(names))


# ── 저장·전송용 축약 버전 (S15P11B209-819) ────────────────────────
# BE는 재현성 태그를 좁은 VARCHAR에 넣는다(generated_model_version·summary_model_version은
# VARCHAR(50)). 정본(composite_version)은 파일 하나당 30자쯤 늘어나, 786에서 리포트 프롬프트가
# report_common+report_htp/report_diary로 갈리자 43자 → 76자가 되며 컬럼을 넘겨 리포트 생성이
# 전량 실패했다(S15P11B209-815). 파일이 더 갈릴 예정이라 컬럼만 넓히면 같은 사고가 반복된다.
#
# 그래서 조합 전체를 해시 하나로 접어 길이를 파일 개수와 무관한 상수로 만든다. 잘라 버리는 게
# 아니라 접는 것이라, 정본은 기동 로그·버전 엔드포인트에 그대로 남아 다이제스트로 되짚을 수 있다
# (자르면 재현성 정보가 죽는다 — 이 필드의 존재 이유가 사라진다).
MAX_VERSION_TAG = 50

_TAG_PATTERN = r"^[a-z-]+@\d+\.\d+\.\d+\+[0-9a-f]{8}$"


def composite_digest(*names: str) -> str:
    """조합 전체(composite_version 출력)의 짧은 해시. 파일 하나라도 내용이 바뀌면 달라진다."""
    return hashlib.sha256(composite_version(*names).encode("utf-8")).hexdigest()[:8]


def _max_semver(*names: str) -> str:
    """조합 구성원 semver의 최댓값 — 사람이 세대를 눈으로 구분하는 용도."""
    return max(
        (_PROMPT_SEMVER.get(name, _UNKNOWN_SEMVER) for name in names),
        key=lambda s: tuple(int(p) for p in s.split(".")),
        default=_UNKNOWN_SEMVER,
    )


def short_version(label: str, *names: str) -> str:
    """저장·전송용 조합 버전: "<label>@<최대 semver>+<조합 해시8>".

    label은 이 조합이 무엇인지 가리키는 짧은 고정 어휘(예: "htp"·"diary"). 어느 활동 변형으로
    생성됐는지는 태그만 보고 구분돼야 한다 — 두 변형을 뭉뚱그리면 사후에 갈라볼 수 없다(786).

    길이는 label 길이 + 15자로 고정이라 프롬프트 파일이 늘어도 커지지 않는다.
    """
    return f"{label}@{_max_semver(*names)}+{composite_digest(*names)}"


def verify_prompt_files() -> list[str]:
    """semver 표와 실제 프롬프트 파일의 불일치를 돌려준다(빈 리스트면 일치).

    - 표에 있는데 파일이 없으면 "<name>: missing file"
    - prompts 폴더에 있는데 표에 없으면 "<name>: unversioned"
    스모크/기동 점검에서 호출해 프롬프트 추가 시 버전 등록 누락을 즉시 잡는다.
    """
    problems: list[str] = []
    for name in _PROMPT_SEMVER:
        if not (PROMPT_DIR / f"{name}.txt").exists():
            problems.append(f"{name}: missing file")
    for path in PROMPT_DIR.glob("*.txt"):
        if path.stem not in _PROMPT_SEMVER:
            problems.append(f"{path.stem}: unversioned")
    return problems
