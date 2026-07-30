"""인덱스 산출물 저장·로드 — npz(임베딩) + json(청크·메타) 짝 (S15P11B209-613).

파일 이름은 고정(index.npz / index.json)이고 KB Version은 json 안에 둔다 —
배포가 "디렉토리 교체"로 끝나고, 어떤 버전이 실렸는지는 로더가 메타에서 읽는다
(가중치(*.pt)와 같은 ai-models 볼륨 경로 /models/rag/ 로 나간다 — 정책 §5).

임베딩은 저장 시 L2 정규화한다 — 검색이 dot product 한 번으로 cosine이 된다.
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path

import numpy as np

INDEX_META = "index.json"
INDEX_VECTORS = "index.npz"


class IndexFormatError(ValueError):
    """인덱스 파일 짝이 없거나 서로 어긋난다(빌드 산출물 불일치)."""


@dataclass(frozen=True)
class ChunkRecord:
    """인덱스에 저장된 청크 하나 — 검색 결과·출처 반환(614)의 재료."""

    chunk_id: str
    source_id: str
    title: str  # 자료 제목(출처 표시용) — 청크마다 실어 조회 시 조인 불요
    text: str


@dataclass(frozen=True)
class Index:
    knowledge_base_version: str
    embedding_model: str
    chunks: list[ChunkRecord]
    vectors: np.ndarray  # float32 [N, D], L2 정규화 완료


def save(directory: str | Path, index: Index) -> None:
    """인덱스를 디렉토리에 저장한다(원자성: 메타를 마지막에 써서 반쪽 상태 방지)."""
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)

    vectors = index.vectors.astype(np.float32)
    norms = np.linalg.norm(vectors, axis=1, keepdims=True)
    norms[norms == 0] = 1.0  # 0벡터 방어(정규화 나눗셈)
    np.savez_compressed(directory / INDEX_VECTORS, vectors=vectors / norms)

    meta = {
        "knowledgeBaseVersion": index.knowledge_base_version,
        "embeddingModel": index.embedding_model,
        "dim": int(vectors.shape[1]) if vectors.size else 0,
        "chunks": [
            {
                "chunkId": c.chunk_id,
                "sourceId": c.source_id,
                "title": c.title,
                "text": c.text,
            }
            for c in index.chunks
        ],
    }
    (directory / INDEX_META).write_text(
        json.dumps(meta, ensure_ascii=False, indent=2), encoding="utf-8"
    )


def load(directory: str | Path) -> Index:
    """인덱스 짝을 읽는다. 파일이 없으면 FileNotFoundError(호출부가 '미구축'으로 해석).

    Raises:
        FileNotFoundError: 메타 또는 벡터 파일이 없다(인덱스 미배포 상태).
        IndexFormatError: 청크 수와 벡터 행 수가 어긋난다(짝이 다른 빌드).
    """
    directory = Path(directory)
    meta = json.loads((directory / INDEX_META).read_text(encoding="utf-8"))
    with np.load(directory / INDEX_VECTORS) as data:
        vectors = data["vectors"]

    chunks = [
        ChunkRecord(
            chunk_id=item["chunkId"],
            source_id=item["sourceId"],
            title=item["title"],
            text=item["text"],
        )
        for item in meta.get("chunks", [])
    ]
    if len(chunks) != vectors.shape[0]:
        raise IndexFormatError(
            f"청크 {len(chunks)}개 ↔ 벡터 {vectors.shape[0]}행 불일치 — json/npz 짝이 다른 빌드다"
        )
    return Index(
        knowledge_base_version=str(meta.get("knowledgeBaseVersion", "")),
        embedding_model=str(meta.get("embeddingModel", "")),
        chunks=chunks,
        vectors=vectors,
    )
