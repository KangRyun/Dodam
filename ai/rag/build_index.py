"""오프라인 인덱스 빌드 — 매니페스트 + 원문 텍스트 → index.json/npz (S15P11B209-613).

실행 (repo 루트 기준):
    cd ai && python -m rag.build_index \
        --manifest rag/corpus-manifest.json \
        --texts ../_workspace/rag-corpus \
        --out ../_workspace/rag-index

입력 규약:
- --texts 디렉토리에 자료별 `<sourceId>.txt` (UTF-8 평문). PDF→텍스트 추출과
  비진단 선별(excludedSections 제거)은 이 스크립트 이전의 준비 단계 책임이며,
  무엇을 뺐는지는 매니페스트에 기록한다(정책 §6).
- 매니페스트의 자료인데 .txt가 없으면 **실패**한다 — 일부만 빌드된 인덱스가
  "전부 반영된 것"으로 배포되는 사고를 막는다(조용한 부분 성공 금지).

출력·배포:
- --out 에 index.json + index.npz. 배포는 ai-models 볼륨 /models/rag/ 로
  kubectl cp (가중치와 동일 경로 — 정책 §5). 같은 매니페스트 → 같은 KB Version.

⚠️ GMS 키 필요(임베딩 호출). 원문·청크 내용은 로그로 남기지 않는다 — 건수만.
"""

from __future__ import annotations

import argparse
import logging
import sys
from pathlib import Path

import numpy as np
from openai import OpenAIError

import config
from gms import get_client
from rag import chunking, manifest, store

logger = logging.getLogger(__name__)

# GMS 임베딩 API 한 요청에 싣는 청크 수. 코퍼스가 수백 청크 규모라 배치 수는 한 자릿수다.
_EMBED_BATCH = 64


def _embed_batches(texts: list[str]) -> np.ndarray:
    vectors: list[list[float]] = []
    for start in range(0, len(texts), _EMBED_BATCH):
        batch = texts[start : start + _EMBED_BATCH]
        try:
            resp = get_client().embeddings.create(model=config.EMBEDDING_MODEL, input=batch)
        except OpenAIError as e:
            raise SystemExit(f"GMS 임베딩 실패({type(e).__name__}) — 배치 {start//_EMBED_BATCH}") from e
        vectors.extend(item.embedding for item in resp.data)
        logger.info("임베딩 %d/%d", min(start + _EMBED_BATCH, len(texts)), len(texts))
    return np.asarray(vectors, dtype=np.float32)


def build(manifest_path: Path, texts_dir: Path, out_dir: Path) -> store.Index:
    corpus = manifest.load(manifest_path)  # 라이선스 게이트 — 여기서 실패하면 빌드 없음

    records: list[store.ChunkRecord] = []
    for source in corpus.sources:
        text_path = texts_dir / f"{source.source_id}.txt"
        if not text_path.exists():
            raise SystemExit(
                f"원문 없음: {text_path} — 매니페스트의 자료는 전부 있어야 한다(부분 빌드 금지)"
            )
        chunks = chunking.split(source.source_id, text_path.read_text(encoding="utf-8"))
        if not chunks:
            raise SystemExit(f"{source.source_id}: 청크 0개 — 원문이 비었거나 형식 문제")
        records.extend(
            store.ChunkRecord(
                chunk_id=c.chunk_id, source_id=c.source_id, title=source.title, text=c.text
            )
            for c in chunks
        )
        logger.info("%s: 청크 %d개", source.source_id, len(chunks))

    vectors = _embed_batches([r.text for r in records])
    index = store.Index(
        knowledge_base_version=corpus.knowledge_base_version,
        embedding_model=config.EMBEDDING_MODEL,
        chunks=records,
        vectors=vectors,
    )
    store.save(out_dir, index)
    logger.info(
        "빌드 완료 — kb=%s sources=%d chunks=%d → %s",
        corpus.knowledge_base_version,
        len(corpus.sources),
        len(records),
        out_dir,
    )
    return index


def main(argv: list[str] | None = None) -> int:
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--texts", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    args = parser.parse_args(argv)
    build(args.manifest, args.texts, args.out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
