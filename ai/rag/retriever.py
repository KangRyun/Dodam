"""런타임 검색 — retrieve(query_text, k) (S15P11B209-613).

질의 임베딩 1회(GMS) + 정규화 벡터 dot product(cosine) top-k + 점수 임계값.
인덱스는 첫 호출에서 지연 로딩한다 — 파일이 없어도 import·기동은 성공하고
(gms.get_client 패턴), 호출 시 RagUnavailableError 를 던져 소비처(614/615)가
'RAG 없이 생성' 폴백으로 처리한다.

가드레일: 질의 텍스트는 관찰 특징·감정·탐지 객체로만 만든다(정책 §1-1).
아이 발화 원문을 질의에 넣지 않는다 — 외부(GMS)로 나가는 표면을 늘리지 않는다.
"""

from __future__ import annotations

import logging
import threading
from dataclasses import dataclass

import numpy as np
from openai import OpenAIError

import config
from gms import get_client
from rag import store

logger = logging.getLogger(__name__)


class RagUnavailableError(RuntimeError):
    """인덱스 미배포·임베딩 실패 등으로 검색을 수행할 수 없다.

    소비처는 이 예외를 '차단'이 아니라 '기능 저하'로 다룬다 — 리포트는 RAG 없이
    기존 경로로 생성한다(615 폴백 정책, 548 AI 장애 폴백과 정합).
    """


@dataclass(frozen=True)
class Chunk:
    """검색 결과 하나 — 프롬프트 근거 블록과 출처 반환(614)의 재료."""

    chunk_id: str
    source_id: str
    title: str
    text: str
    score: float  # cosine 유사도 (정규화 벡터 dot)


_lock = threading.Lock()
_index: store.Index | None = None
_load_failed = False  # 미배포 상태를 매 호출 디스크 확인 없이 기억(파드 재시작으로 리셋)


def _get_index() -> store.Index:
    global _index, _load_failed
    if _index is not None:
        return _index
    if _load_failed:
        raise RagUnavailableError("RAG 인덱스가 배포되지 않았어요.")
    with _lock:
        if _index is not None:  # 경합 이중 로딩 방지
            return _index
        try:
            _index = store.load(config.RAG_INDEX_DIR)
        except FileNotFoundError as e:
            _load_failed = True
            # 미배포는 정상 운영 상태일 수 있다(인덱스 나가기 전) — 에러가 아니라 정보.
            logger.info("RAG 인덱스 없음(%s) — 검색 비활성", config.RAG_INDEX_DIR)
            raise RagUnavailableError("RAG 인덱스가 배포되지 않았어요.") from e
        except store.IndexFormatError as e:
            _load_failed = True
            logger.error("RAG 인덱스 형식 오류: %s", e)
            raise RagUnavailableError("RAG 인덱스를 읽지 못했어요.") from e
        logger.info(
            "RAG 인덱스 로드 — kb=%s chunks=%d",
            _index.knowledge_base_version,
            len(_index.chunks),
        )
        return _index


def knowledge_base_version() -> str | None:
    """배포된 인덱스의 KB Version. 미배포면 None (health의 rag READY 판정 재료)."""
    try:
        return _get_index().knowledge_base_version
    except RagUnavailableError:
        return None


def _embed_query(text: str) -> np.ndarray:
    try:
        resp = get_client().embeddings.create(
            model=config.EMBEDDING_MODEL, input=[text]
        )
    except OpenAIError as e:
        # ⚠️ 질의 내용은 로그로 남기지 않는다 — 에러 유형만(기존 클라이언트들과 동일).
        logger.error("GMS 임베딩 호출 실패: %s", type(e).__name__)
        raise RagUnavailableError("질의 임베딩에 실패했어요(GMS).") from e
    vector = np.asarray(resp.data[0].embedding, dtype=np.float32)
    norm = np.linalg.norm(vector)
    return vector / norm if norm else vector


def retrieve(
    query_text: str,
    k: int | None = None,
    *,
    score_threshold: float | None = None,
) -> list[Chunk]:
    """질의와 유사한 청크 top-k. 임계값 미만은 버린다(빈 목록 = '쓸 근거 없음').

    빈 목록은 예외가 아니다 — 저점수 근거를 억지로 실으면 리포트가 엉뚱한
    지식을 인용한다(정책 §1-2). 소비처는 빈 목록이면 근거 블록 없이 진행한다.

    Raises:
        RagUnavailableError: 인덱스 미배포 또는 질의 임베딩 실패.
    """
    index = _get_index()
    if not index.chunks:
        return []
    top_k = k or config.RAG_TOP_K
    threshold = config.RAG_SCORE_THRESHOLD if score_threshold is None else score_threshold

    query = _embed_query(query_text)
    scores = index.vectors @ query  # 양쪽 정규화 → dot = cosine
    order = np.argsort(scores)[::-1][:top_k]
    return [
        Chunk(
            chunk_id=index.chunks[i].chunk_id,
            source_id=index.chunks[i].source_id,
            title=index.chunks[i].title,
            text=index.chunks[i].text,
            score=float(scores[i]),
        )
        for i in order
        if float(scores[i]) >= threshold
    ]
