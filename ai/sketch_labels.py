"""그림일기(자유 그림) 모델 클래스 → 계약 라벨·표시명 매핑 (S15P11B209-711).

`htp_labels`와 짝을 이루는 ART_DIARY용 표다. 두 모델은 클래스 집합이 완전히 다르다 —
HTP 가중치는 한국어 47종, 그림일기(sketch) 가중치는 영어 카테고리다.

**이 표가 없어서 생긴 문제**: `analysis_service`가 ART_DIARY 탐지에도 `htp_labels`를
태우고 있었다. 영어 클래스는 HTP 표에 없으니 전부 `UNKNOWN`으로 접히고
`OBJECT_CODE_UNMAPPED` 경고가 항상 붙었다 — 그림일기의 객체 코드가 통째로 무의미했다.

가중치 세대와 이 표의 관계(2026-07-29 실측):
- 배포 중인 `sketch_base.pt`(v1)는 **33종**이다.
- 노트북(`ai/models/sketch_base.ipynb`)의 현재 설정은 `sketch_base_v4.pt` **100종**
  (Quick Draw 99종 + HTP 사람 스프라이트에서 온 `person`)이다.
- **33종은 100종의 완전한 부분집합**이라, 이 표를 100종 기준 상위집합으로 두면
  두 세대 모두에 맞는다. 모델이 내지 않는 항목이 표에 남아 있는 것은 무해하다.
- `school bus`는 v4에서 `bus`로 병합됐다 — 병합 전 가중치도 같은 코드로 접히게 둔다.

계약 라벨 규칙: HTP와 겹치는 대상은 **같은 코드를 재사용한다**(`house`→`HOUSE`,
`door`→`HOUSE_DOOR`, `eye`→`PERSON_EYE` …). 코드가 갈리면 리포트 집계가 두 벌이 된다.

⚠️ 가중치를 재학습해 클래스 집합이 바뀌면 이 표도 같이 고쳐야 한다. 데이터셋·가중치는
저장소에 커밋하지 않으므로(.gitignore) **이 표가 클래스 집합의 유일한 저장소 기록**이다 —
불일치는 verify_against_model_names()가 기동/스모크 시점에 잡는다.
"""

from __future__ import annotations

import logging
from dataclasses import replace
from typing import Iterable

from htp_labels import (
    GROUP_HOUSE,
    GROUP_PERSON,
    GROUP_SCENERY,
    GROUP_TREE,
    GROUP_UNKNOWN,
    UNKNOWN_LABEL,
    LabelSpec,
)

logger = logging.getLogger(__name__)

# 자유 그림에만 나오는 갈래. HTP 주제 그룹(집·나무·사람)과 배경은 그대로 재사용하고,
# 주제 개념이 없는 것들만 여기서 나눈다 — 그림일기 프롬프트가 "무엇을 그렸나"를
# 뭉뚱그리지 않게 하기 위한 축이다(주제 필터에는 쓰이지 않는다).
GROUP_ANIMAL = "ANIMAL"
GROUP_VEHICLE = "VEHICLE"
GROUP_FOOD = "FOOD"
GROUP_OBJECT = "OBJECT"


def _spec(label: str, group: str, *, display: str, whole: bool = False) -> LabelSpec:
    return LabelSpec(
        contract_label=label, display_name=display, group=group, is_whole=whole
    )


# ── 클래스 매핑 ─────────────────────────────────────────────────
#   키는 가중치가 내는 영어 클래스명 그대로다(공백·하이픈 포함).
#   표시명은 아이에게 그대로 읽어줄 수 있는 한국어여야 한다.
_SPEC_BY_CLASS: dict[str, LabelSpec] = {
    # ── 집·나무 (HTP와 코드 공유) ──
    "house": _spec("HOUSE", GROUP_HOUSE, display="집", whole=True),
    "door": _spec("HOUSE_DOOR", GROUP_HOUSE, display="문"),
    "tree": _spec("TREE", GROUP_TREE, display="나무", whole=True),
    "palm tree": _spec("PALM_TREE", GROUP_TREE, display="야자나무"),
    "leaf": _spec("TREE_LEAF", GROUP_TREE, display="나뭇잎"),
    # ── 사람 (HTP와 코드 공유) ──
    #   person은 v4에서 HTP '사람전체' 스프라이트로 추가된 클래스다.
    "person": _spec("PERSON", GROUP_PERSON, display="사람", whole=True),
    "face": _spec("PERSON_FACE", GROUP_PERSON, display="얼굴"),
    "eye": _spec("PERSON_EYE", GROUP_PERSON, display="눈"),
    "nose": _spec("PERSON_NOSE", GROUP_PERSON, display="코"),
    "mouth": _spec("PERSON_MOUTH", GROUP_PERSON, display="입"),
    "ear": _spec("PERSON_EAR", GROUP_PERSON, display="귀"),
    "arm": _spec("PERSON_ARM", GROUP_PERSON, display="팔"),
    "hand": _spec("PERSON_HAND", GROUP_PERSON, display="손"),
    "leg": _spec("PERSON_LEG", GROUP_PERSON, display="다리"),
    "foot": _spec("PERSON_FOOT", GROUP_PERSON, display="발"),
    "shoe": _spec("PERSON_SHOES", GROUP_PERSON, display="신발"),
    "sock": _spec("PERSON_SOCK", GROUP_PERSON, display="양말"),
    "t-shirt": _spec("PERSON_SHIRT", GROUP_PERSON, display="티셔츠"),
    "pants": _spec("PERSON_PANTS", GROUP_PERSON, display="바지"),
    "hat": _spec("HAT", GROUP_PERSON, display="모자"),
    "crown": _spec("CROWN", GROUP_PERSON, display="왕관"),
    # ── 자연·배경 (일부 HTP와 코드 공유) ──
    "sun": _spec("SUN", GROUP_SCENERY, display="해"),
    "cloud": _spec("CLOUD", GROUP_SCENERY, display="구름"),
    "moon": _spec("MOON", GROUP_SCENERY, display="달"),
    "star": _spec("STAR", GROUP_SCENERY, display="별"),
    "rainbow": _spec("RAINBOW", GROUP_SCENERY, display="무지개"),
    "snowflake": _spec("SNOWFLAKE", GROUP_SCENERY, display="눈송이"),
    "lightning": _spec("LIGHTNING", GROUP_SCENERY, display="번개"),
    "snowman": _spec("SNOWMAN", GROUP_SCENERY, display="눈사람"),
    "mountain": _spec("MOUNTAIN", GROUP_SCENERY, display="산"),
    "river": _spec("RIVER", GROUP_SCENERY, display="강"),
    # HTP의 POND(연못)와는 다른 대상이라 코드를 분리한다.
    "pool": _spec("POOL", GROUP_SCENERY, display="수영장"),
    "garden": _spec("GARDEN", GROUP_SCENERY, display="정원"),
    "grass": _spec("GRASS", GROUP_SCENERY, display="잔디"),
    "flower": _spec("FLOWER", GROUP_SCENERY, display="꽃"),
    "bush": _spec("BUSH", GROUP_SCENERY, display="덤불"),
    "fence": _spec("FENCE", GROUP_SCENERY, display="울타리"),
    "swing set": _spec("SWING", GROUP_SCENERY, display="그네"),
    "castle": _spec("CASTLE", GROUP_SCENERY, display="성"),
    # '다리'는 사람 다리(PERSON_LEG)와 표시명이 겹친다 — 구분되게 적는다.
    "bridge": _spec("BRIDGE", GROUP_SCENERY, display="강 위 다리"),
    # ── 동물 ──
    "bird": _spec("BIRD", GROUP_ANIMAL, display="새"),
    "squirrel": _spec("SQUIRREL", GROUP_ANIMAL, display="다람쥐"),
    "cat": _spec("CAT", GROUP_ANIMAL, display="고양이"),
    "dog": _spec("DOG", GROUP_ANIMAL, display="강아지"),
    "rabbit": _spec("RABBIT", GROUP_ANIMAL, display="토끼"),
    "bear": _spec("BEAR", GROUP_ANIMAL, display="곰"),
    "lion": _spec("LION", GROUP_ANIMAL, display="사자"),
    "tiger": _spec("TIGER", GROUP_ANIMAL, display="호랑이"),
    "elephant": _spec("ELEPHANT", GROUP_ANIMAL, display="코끼리"),
    "giraffe": _spec("GIRAFFE", GROUP_ANIMAL, display="기린"),
    "monkey": _spec("MONKEY", GROUP_ANIMAL, display="원숭이"),
    "pig": _spec("PIG", GROUP_ANIMAL, display="돼지"),
    "cow": _spec("COW", GROUP_ANIMAL, display="소"),
    "horse": _spec("HORSE", GROUP_ANIMAL, display="말"),
    "sheep": _spec("SHEEP", GROUP_ANIMAL, display="양"),
    "duck": _spec("DUCK", GROUP_ANIMAL, display="오리"),
    "penguin": _spec("PENGUIN", GROUP_ANIMAL, display="펭귄"),
    "owl": _spec("OWL", GROUP_ANIMAL, display="부엉이"),
    "fish": _spec("FISH", GROUP_ANIMAL, display="물고기"),
    "butterfly": _spec("BUTTERFLY", GROUP_ANIMAL, display="나비"),
    "bee": _spec("BEE", GROUP_ANIMAL, display="벌"),
    "spider": _spec("SPIDER", GROUP_ANIMAL, display="거미"),
    "frog": _spec("FROG", GROUP_ANIMAL, display="개구리"),
    "snake": _spec("SNAKE", GROUP_ANIMAL, display="뱀"),
    # ── 탈것 ──
    "car": _spec("CAR", GROUP_VEHICLE, display="자동차"),
    "bus": _spec("BUS", GROUP_VEHICLE, display="버스"),
    # v4에서 bus로 병합됐다 — 병합 전 가중치도 같은 코드로 접는다.
    "school bus": _spec("BUS", GROUP_VEHICLE, display="버스"),
    "truck": _spec("TRUCK", GROUP_VEHICLE, display="트럭"),
    "firetruck": _spec("FIRE_TRUCK", GROUP_VEHICLE, display="소방차"),
    "train": _spec("TRAIN", GROUP_VEHICLE, display="기차"),
    "airplane": _spec("AIRPLANE", GROUP_VEHICLE, display="비행기"),
    "helicopter": _spec("HELICOPTER", GROUP_VEHICLE, display="헬리콥터"),
    "bicycle": _spec("BICYCLE", GROUP_VEHICLE, display="자전거"),
    # ── 먹을 것 ──
    "apple": _spec("APPLE", GROUP_FOOD, display="사과"),
    "banana": _spec("BANANA", GROUP_FOOD, display="바나나"),
    "strawberry": _spec("STRAWBERRY", GROUP_FOOD, display="딸기"),
    "watermelon": _spec("WATERMELON", GROUP_FOOD, display="수박"),
    "carrot": _spec("CARROT", GROUP_FOOD, display="당근"),
    "ice cream": _spec("ICE_CREAM", GROUP_FOOD, display="아이스크림"),
    "cake": _spec("CAKE", GROUP_FOOD, display="케이크"),
    "pizza": _spec("PIZZA", GROUP_FOOD, display="피자"),
    "hamburger": _spec("HAMBURGER", GROUP_FOOD, display="햄버거"),
    "cookie": _spec("COOKIE", GROUP_FOOD, display="쿠키"),
    "donut": _spec("DONUT", GROUP_FOOD, display="도넛"),
    "lollipop": _spec("LOLLIPOP", GROUP_FOOD, display="막대사탕"),
    # ── 사물 ──
    "ladder": _spec("LADDER", GROUP_OBJECT, display="사다리"),
    "stairs": _spec("STAIRS", GROUP_OBJECT, display="계단"),
    "chair": _spec("CHAIR", GROUP_OBJECT, display="의자"),
    "table": _spec("TABLE", GROUP_OBJECT, display="탁자"),
    "bed": _spec("BED", GROUP_OBJECT, display="침대"),
    "clock": _spec("CLOCK", GROUP_OBJECT, display="시계"),
    "book": _spec("BOOK", GROUP_OBJECT, display="책"),
    "cup": _spec("CUP", GROUP_OBJECT, display="컵"),
    "umbrella": _spec("UMBRELLA", GROUP_OBJECT, display="우산"),
    "pencil": _spec("PENCIL", GROUP_OBJECT, display="연필"),
    "smiley face": _spec("SMILEY_FACE", GROUP_OBJECT, display="웃는 얼굴"),
    "soccer ball": _spec("SOCCER_BALL", GROUP_OBJECT, display="축구공"),
    "basketball": _spec("BASKETBALL", GROUP_OBJECT, display="농구공"),
    "skateboard": _spec("SKATEBOARD", GROUP_OBJECT, display="스케이트보드"),
    # '기타'만 쓰면 '그 외'로 읽힌다 — 악기임을 남긴다.
    "guitar": _spec("GUITAR", GROUP_OBJECT, display="기타(악기)"),
    "piano": _spec("PIANO", GROUP_OBJECT, display="피아노"),
}

_UNKNOWN_SPEC = _spec(UNKNOWN_LABEL, GROUP_UNKNOWN, display="알 수 없는 것")


def spec_of(class_name: str) -> LabelSpec:
    """영어 클래스명 → LabelSpec. 모르는 이름은 UNKNOWN으로 접고 경고를 남긴다."""
    found = _SPEC_BY_CLASS.get(class_name)
    if found is None:
        logger.warning("그림일기 매핑에 없는 클래스명 — UNKNOWN으로 처리")
        return _UNKNOWN_SPEC
    return found


def to_contract_label(class_name: str) -> str:
    """영어 클래스명 → 계약 라벨(UPPER_SNAKE_CASE)."""
    return spec_of(class_name).contract_label


def display_name_of(class_name: str) -> str:
    """영어 클래스명 → 프롬프트·리포트에 나가는 한국어 표시명."""
    return spec_of(class_name).display_name


def group_of(class_name: str) -> str:
    """영어 클래스명 → 그룹."""
    return spec_of(class_name).group


def is_whole(class_name: str) -> bool:
    """'house'처럼 대상 전체를 감싸는 박스인지."""
    return spec_of(class_name).is_whole


def verify_against_model_names(names: Iterable[str]) -> list[str]:
    """가중치의 클래스명 목록과 이 표를 대조해 '표에 없는 이름'을 돌려준다.

    빈 리스트면 일치. 데이터셋·가중치가 저장소에 없으므로 재학습으로 클래스가 바뀐 것을
    런타임 UNKNOWN 폭증 대신 여기서 즉시 알아채기 위한 장치다.
    """
    return [name for name in names if name not in _SPEC_BY_CLASS]


# 표시명을 비운 항목이 없어야 한다 — 위 표는 전부 명시하므로 방어적으로만 확인한다.
_SPEC_BY_CLASS = {
    name: spec if spec.display_name else replace(spec, display_name=name)
    for name, spec in _SPEC_BY_CLASS.items()
}
