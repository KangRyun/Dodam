"""Corpus 매니페스트 로드·검증 — 라이선스 게이트 (S15P11B209-613).

매니페스트(ai/rag/corpus-manifest.json)가 Corpus의 정본이다(정책 §5 — 원문은
보관하지 않고 URL+체크섬으로 재현). 여기의 검증이 정책 §2를 코드로 강제한다:
허용 라이선스가 아니거나 자료 단위 실확인 기록(licenseVerifiedAt)이 없으면
인덱스 빌드를 거부한다. "검증 통과 + 저장값 오염"(sync-secrets 사고 패턴)을
만들지 않도록, 검증은 빌드 입구 한 곳에서만 하고 통과한 것만 흘려보낸다.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path

# 정책 §2 채택 기준과 1:1. 여기 없는 값은 전부 거부한다(허용 목록 방식 —
# 거부 목록이면 새 라이선스 표기가 조용히 통과한다).
ALLOWED_LICENSES = {"KOGL-1", "PD", "CC0", "CC-BY"}


class ManifestError(ValueError):
    """매니페스트가 정책을 위반해 빌드를 진행할 수 없다."""


@dataclass(frozen=True)
class Source:
    """채택 확정된 자료 하나(정책 §6). 필드는 매니페스트 스키마와 1:1."""

    source_id: str
    title: str
    publisher: str
    url: str
    license: str
    license_verified_at: str
    collected_at: str
    sha256: str
    tags: list[str] = field(default_factory=list)
    excluded_sections: list[str] = field(default_factory=list)


@dataclass(frozen=True)
class Manifest:
    knowledge_base_version: str
    sources: list[Source]


def _require(value, name: str, source_id: str) -> str:
    if not value or not str(value).strip():
        raise ManifestError(f"{source_id}: '{name}' 누락 — 정책 §6 필수 필드")
    return str(value).strip()


def load(path: str | Path) -> Manifest:
    """매니페스트를 읽고 정책 게이트를 통과시킨다.

    Raises:
        ManifestError: 형식 오류, 비허용 라이선스, 실확인 기록 누락,
            sourceId 중복, KB Version 형식 위반.
    """
    raw = json.loads(Path(path).read_text(encoding="utf-8"))

    kb_version = str(raw.get("knowledgeBaseVersion", "")).strip()
    # 정책 §7: kb-<YYYY.MM>-<seq>. 형식이 어긋나면 614가 반환할 값이 오염된다.
    if not kb_version.startswith("kb-") or len(kb_version.split("-")) != 3:
        raise ManifestError(f"knowledgeBaseVersion 형식 위반: {kb_version!r} (kb-<YYYY.MM>-<seq>)")

    sources: list[Source] = []
    seen_ids: set[str] = set()
    for item in raw.get("sources", []):
        source_id = _require(item.get("sourceId"), "sourceId", "(unknown)")
        if source_id in seen_ids:
            raise ManifestError(f"{source_id}: sourceId 중복 — 출처 반환(614)의 키라 유일해야 한다")
        seen_ids.add(source_id)

        license_code = _require(item.get("license"), "license", source_id)
        if license_code not in ALLOWED_LICENSES:
            raise ManifestError(
                f"{source_id}: 비허용 라이선스 {license_code!r} — 허용: {sorted(ALLOWED_LICENSES)} (정책 §2)"
            )
        sources.append(
            Source(
                source_id=source_id,
                title=_require(item.get("title"), "title", source_id),
                publisher=_require(item.get("publisher"), "publisher", source_id),
                url=_require(item.get("url"), "url", source_id),
                license=license_code,
                # 자료 단위 실확인 게이트(정책 §2) — 기관 단위 추정 채택을 막는다.
                license_verified_at=_require(
                    item.get("licenseVerifiedAt"), "licenseVerifiedAt", source_id
                ),
                collected_at=_require(item.get("collectedAt"), "collectedAt", source_id),
                sha256=_require(item.get("sha256"), "sha256", source_id),
                tags=list(item.get("tags", [])),
                excluded_sections=list(item.get("excludedSections", [])),
            )
        )

    if not sources:
        raise ManifestError("sources 가 비어 있다 — 빌드할 Corpus가 없다")
    return Manifest(knowledge_base_version=kb_version, sources=sources)
