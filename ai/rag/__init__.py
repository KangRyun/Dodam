"""RAG 검색 파이프라인 (S15P11B209-613).

관찰 리포트 생성이 참조할 '일반 전문 지식'(발달 단계·정서 어휘·부모 대화법)을
인덱스에서 찾아 준다. Corpus 채택 기준·라이선스·매니페스트 형식은
docs/ai/rag-corpus-policy.md 가 정본이다.

가드레일:
- 아동 데이터는 인덱스·질의 어느 쪽에도 넣지 않는다(정책 §1-1). 질의는 관찰
  특징·감정·탐지 객체 텍스트로만 만든다 — 아이 발화 원문은 쓰지 않는다.
- 인덱스가 없어도 import·기동은 실패하지 않는다(지연 로딩 — gms.get_client 패턴).
  검색 실패의 폴백 정책(리포트는 RAG 없이 생성)은 615가 소비처에서 구현한다.
"""

from rag.retriever import Chunk, RagUnavailableError, retrieve

__all__ = ["Chunk", "RagUnavailableError", "retrieve"]
