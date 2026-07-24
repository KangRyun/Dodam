"""HTP 47클래스 → 계약 라벨·그룹 매핑과 집계 (S15P11B209-376).

YOLO 가중치(htp_best.pt)가 내놓는 클래스명은 한국어 47종이다. 이걸 그대로 BE·FE로
흘리면 두 가지가 깨진다.
  1) BE↔AI 그림분석 계약(docs/api/ai-drawing-analysis-contract.md)은 Enum을
     UPPER_SNAKE_CASE 문자열로 직렬화한다 — 한국어 라벨은 계약 위반.
  2) 47종을 평면으로 주면 소비자(질문 생성·리포트·FE 표시)가 매번 "이게 집 부위인가
     사람 부위인가"를 다시 판단해야 한다.

그래서 여기서 (계약 라벨, 그룹, 전체/부위) 세 값을 한 번에 확정하고 집계까지 제공한다.

라벨 규칙 — 그룹이 있는 것은 `<그룹>_<부위>`, 그림 주제 자체(집·나무·사람 '전체')는
`<그룹>`, 배경 사물은 접두사 없이 그 자체:
    집전체 → HOUSE          지붕 → HOUSE_ROOF
    나무전체 → TREE          뿌리 → TREE_ROOT
    사람전체 → PERSON        눈 → PERSON_EYE
    태양 → SUN              구름 → CLOUD
계약 예시(HOUSE·TREE)가 곧 '전체' 라벨이 되도록 맞췄고, BE는 `label.startswith("HOUSE")`
로 집 계열을 한 번에 고를 수 있다.

torch·ultralytics를 import하지 않는다 — 계약 엔드포인트·테스트가 추론 의존성 없이
이 모듈만 쓸 수 있어야 한다.
"""

from __future__ import annotations

import logging
from collections import Counter
from dataclasses import dataclass
from typing import Iterable, Protocol

logger = logging.getLogger(__name__)

# ── 그룹 ────────────────────────────────────────────────────────
#   HTP(House-Tree-Person)의 세 주제 + 배경 사물(SCENERY).
#   SCENERY는 심리 해석에서 '주제 밖 부가 요소'로 따로 보므로 주제 셋과 나란히 두지 않는다.
GROUP_HOUSE = "HOUSE"
GROUP_TREE = "TREE"
GROUP_PERSON = "PERSON"
GROUP_SCENERY = "SCENERY"
GROUP_UNKNOWN = "UNKNOWN"

#: 그림 주제 세 그룹 — 리포트·질문 생성이 "무엇을 그렸나"를 판단할 때 쓰는 축.
SUBJECT_GROUPS = (GROUP_HOUSE, GROUP_TREE, GROUP_PERSON)


@dataclass(frozen=True)
class LabelSpec:
    """한국어 클래스 하나에 대한 다운스트림 계약값."""

    contract_label: str  # UPPER_SNAKE_CASE. 계약 detections[].label 에 그대로 들어간다.
    group: str
    is_whole: bool  # '집전체'처럼 주제 전체를 감싸는 박스인지(부위와 구분)


def _spec(label: str, group: str, *, whole: bool = False) -> LabelSpec:
    return LabelSpec(contract_label=label, group=group, is_whole=whole)


# ── 47클래스 매핑 ───────────────────────────────────────────────
#   키 순서 = 가중치의 클래스 id 순서(ai/models/htp_yolo/stageB_htp/data.yaml, 가나다순).
#   ⚠️ 가중치를 재학습해 클래스 집합이 바뀌면 이 표도 같이 고쳐야 한다 —
#      불일치는 아래 verify_against_model_names()가 기동/스모크 시점에 잡는다.
_SPEC_BY_CLASS: dict[str, LabelSpec] = {
    # ── 나무 계열 ──
    "가지": _spec("TREE_BRANCH", GROUP_TREE),
    # '기둥'은 집 기둥이 아니라 나무 줄기(trunk)다 — 학습 라벨에서 나무 그림에만 180건
    # 나오고 집 그림엔 0건(stageB_htp/train, 2026-07-24 실측).
    "기둥": _spec("TREE_TRUNK", GROUP_TREE),
    # '나무'(id 8) vs '나무전체'(id 9): 전자는 배경 나무, 후자가 나무 그림의 주제다 —
    # '나무'는 집 그림에만 218건·나무 그림엔 0건으로 정반대 분포(같은 실측).
    "나무전체": _spec("TREE", GROUP_TREE, whole=True),
    "나뭇잎": _spec("TREE_LEAF", GROUP_TREE),
    "뿌리": _spec("TREE_ROOT", GROUP_TREE),
    "수관": _spec("TREE_CROWN", GROUP_TREE),
    "열매": _spec("TREE_FRUIT", GROUP_TREE),
    # ── 집 계열 ──
    "굴뚝": _spec("HOUSE_CHIMNEY", GROUP_HOUSE),
    "문": _spec("HOUSE_DOOR", GROUP_HOUSE),
    "연기": _spec("HOUSE_SMOKE", GROUP_HOUSE),  # 굴뚝 연기 — 집 요소로 함께 본다
    "지붕": _spec("HOUSE_ROOF", GROUP_HOUSE),
    "집벽": _spec("HOUSE_WALL", GROUP_HOUSE),
    "집전체": _spec("HOUSE", GROUP_HOUSE, whole=True),
    "창문": _spec("HOUSE_WINDOW", GROUP_HOUSE),
    # ── 사람 계열 ──
    "귀": _spec("PERSON_EAR", GROUP_PERSON),
    "남자구두": _spec("PERSON_DRESS_SHOES_MENS", GROUP_PERSON),
    "눈": _spec("PERSON_EYE", GROUP_PERSON),
    "다리": _spec("PERSON_LEG", GROUP_PERSON),
    "단추": _spec("PERSON_BUTTON", GROUP_PERSON),
    "머리": _spec("PERSON_HEAD", GROUP_PERSON),
    "머리카락": _spec("PERSON_HAIR", GROUP_PERSON),
    "목": _spec("PERSON_NECK", GROUP_PERSON),
    "발": _spec("PERSON_FOOT", GROUP_PERSON),
    "사람전체": _spec("PERSON", GROUP_PERSON, whole=True),
    "상체": _spec("PERSON_UPPER_BODY", GROUP_PERSON),
    "손": _spec("PERSON_HAND", GROUP_PERSON),
    "얼굴": _spec("PERSON_FACE", GROUP_PERSON),
    "여자구두": _spec("PERSON_DRESS_SHOES_WOMENS", GROUP_PERSON),
    "운동화": _spec("PERSON_SNEAKERS", GROUP_PERSON),
    "입": _spec("PERSON_MOUTH", GROUP_PERSON),
    "주머니": _spec("PERSON_POCKET", GROUP_PERSON),
    "코": _spec("PERSON_NOSE", GROUP_PERSON),
    "팔": _spec("PERSON_ARM", GROUP_PERSON),
    # ── 배경 사물 ──
    "구름": _spec("CLOUD", GROUP_SCENERY),
    "그네": _spec("SWING", GROUP_SCENERY),
    "길": _spec("PATH", GROUP_SCENERY),
    "꽃": _spec("FLOWER", GROUP_SCENERY),
    "나무": _spec("SCENERY_TREE", GROUP_SCENERY),
    "다람쥐": _spec("SQUIRREL", GROUP_SCENERY),
    "달": _spec("MOON", GROUP_SCENERY),
    "별": _spec("STAR", GROUP_SCENERY),
    "산": _spec("MOUNTAIN", GROUP_SCENERY),
    "새": _spec("BIRD", GROUP_SCENERY),
    "연못": _spec("POND", GROUP_SCENERY),
    "울타리": _spec("FENCE", GROUP_SCENERY),
    "잔디": _spec("GRASS", GROUP_SCENERY),
    "태양": _spec("SUN", GROUP_SCENERY),
}

#: 알 수 없는 클래스에 쓰는 폴백. 계약이 label을 "비어 있지 않은 문자열"로 요구하므로
#: 빈 값·한국어 원문을 흘리지 않고 이 값으로 접는다(원인은 warning 로그로 남는다).
UNKNOWN_LABEL = "UNKNOWN"
_UNKNOWN_SPEC = _spec(UNKNOWN_LABEL, GROUP_UNKNOWN)


def spec_of(class_name: str) -> LabelSpec:
    """한국어 클래스명 → LabelSpec. 모르는 이름은 UNKNOWN으로 접고 경고를 남긴다.

    모르는 이름이 나온다는 건 가중치의 클래스 집합과 이 표가 어긋났다는 뜻이다 —
    조용히 통과시키면 BE에 쓰레기 라벨이 저장되므로 로그로 드러낸다.
    """
    found = _SPEC_BY_CLASS.get(class_name)
    if found is None:
        logger.warning("HTP 매핑에 없는 클래스명 — UNKNOWN으로 처리")
        return _UNKNOWN_SPEC
    return found


def to_contract_label(class_name: str) -> str:
    """한국어 클래스명 → 계약 라벨(UPPER_SNAKE_CASE)."""
    return spec_of(class_name).contract_label


def group_of(class_name: str) -> str:
    """한국어 클래스명 → 그룹(HOUSE/TREE/PERSON/SCENERY/UNKNOWN)."""
    return spec_of(class_name).group


def is_whole(class_name: str) -> bool:
    """'집전체'처럼 주제 전체 박스인지."""
    return spec_of(class_name).is_whole


def verify_against_model_names(names: Iterable[str]) -> list[str]:
    """가중치의 클래스명 목록과 이 표를 대조해 '표에 없는 이름'을 돌려준다.

    빈 리스트면 일치. 스모크 검증·기동 점검에서 호출해 재학습으로 클래스가 바뀐 걸
    런타임 UNKNOWN 폭증 대신 즉시 알아채기 위한 장치다.
    """
    return [name for name in names if name not in _SPEC_BY_CLASS]


# ── 집계 ────────────────────────────────────────────────────────
class _DetectionLike(Protocol):
    """yolo_client.Detection 구조만 요구한다(추론 모듈을 import하지 않기 위해)."""

    label: str
    confidence: float


def suppress_cross_subject_parts(detections: Iterable[_DetectionLike]) -> list[_DetectionLike]:
    """다른 주제의 '부위' 오탐을 제거한다.

    HTP 검사지는 한 장에 한 주제(집/나무/사람)만 그린다. 그런데 실측(test 80장)에서
    나무 그림에 PERSON_EYE·PERSON_SNEAKERS가 conf 0.63으로 잡히는 등, 신뢰도만으로는
    거를 수 없는 교차 주제 오탐이 나온다 — 임계값을 올리면 진짜 부위가 같이 잘린다.

    규칙: 어떤 주제의 '전체' 박스가 잡혔다면, '전체'가 잡히지 않은 다른 주제 그룹의
    탐지는 버린다. 배경(SCENERY)과 UNKNOWN은 건드리지 않는다 — 나무 그림의 구름·태양은
    정상이고, UNKNOWN은 매핑 불일치 신호라 조용히 지우면 안 된다.

    어떤 주제의 '전체'도 없으면(=주제 판단 불가) 아무것도 버리지 않는다. 근거 없이
    지우는 것보다 그대로 넘기고 소비자가 판단하게 두는 편이 안전하다.
    """
    kept_by_group = {
        group: False for group in SUBJECT_GROUPS
    }
    for det in detections:
        spec = spec_of(det.label)
        if spec.is_whole and spec.group in kept_by_group:
            kept_by_group[spec.group] = True

    if not any(kept_by_group.values()):
        return list(detections)

    return [
        det
        for det in detections
        if kept_by_group.get(spec_of(det.label).group, True)
    ]


@dataclass(frozen=True)
class GroupSummary:
    """한 그룹(집/나무/사람/배경)의 탐지 요약."""

    group: str
    whole_detected: bool  # '전체' 박스가 잡혔는지 = 그 주제를 그렸다고 볼 근거
    part_labels: tuple[str, ...]  # 잡힌 부위 계약 라벨(중복 제거·정렬)
    label_counts: dict[str, int]  # 계약 라벨별 개수(눈 2개 / 창문 3개 같은 정보)
    max_confidence: float  # 그룹 내 최고 신뢰도. 탐지 없으면 0.0


@dataclass(frozen=True)
class DetectionSummary:
    """탐지 전체 요약 — 질문 생성·리포트가 쓰는 형태."""

    total: int
    groups: dict[str, GroupSummary]
    subjects_drawn: tuple[str, ...]  # HOUSE/TREE/PERSON 중 '전체'가 잡힌 것
    is_empty: bool  # 무탐지(빈 종이·과도한 임계값·저품질 입력)


def summarize(detections: Iterable[_DetectionLike]) -> DetectionSummary:
    """탐지 목록 → 그룹별 집계.

    무탐지(is_empty)는 오류가 아니라 정상 결과다 — 계약도 `detections: []`를 정상으로
    규정한다. 소비자가 "그림에서 아무것도 못 찾음"을 분기할 수 있게 플래그로 준다.
    """
    counts_by_group: dict[str, Counter] = {}
    whole_by_group: dict[str, bool] = {}
    max_conf_by_group: dict[str, float] = {}
    total = 0

    for det in detections:
        total += 1
        spec = spec_of(det.label)
        group = spec.group
        counts_by_group.setdefault(group, Counter())[spec.contract_label] += 1
        if spec.is_whole:
            whole_by_group[group] = True
        confidence = float(det.confidence)
        if confidence > max_conf_by_group.get(group, 0.0):
            max_conf_by_group[group] = confidence

    groups: dict[str, GroupSummary] = {}
    for group, counter in counts_by_group.items():
        whole_detected = whole_by_group.get(group, False)
        # 부위 = '전체'가 아닌 라벨. 그룹명과 같은 라벨(HOUSE/TREE/PERSON)이 곧 전체다.
        parts = tuple(sorted(label for label in counter if label != group))
        groups[group] = GroupSummary(
            group=group,
            whole_detected=whole_detected,
            part_labels=parts,
            label_counts=dict(counter),
            max_confidence=max_conf_by_group.get(group, 0.0),
        )

    subjects = tuple(
        group for group in SUBJECT_GROUPS if groups.get(group) and groups[group].whole_detected
    )
    return DetectionSummary(
        total=total,
        groups=groups,
        subjects_drawn=subjects,
        is_empty=total == 0,
    )
