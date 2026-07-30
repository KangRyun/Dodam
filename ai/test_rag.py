"""rag/ 단위 테스트 — GMS·실 인덱스 없이 돈다 (S15P11B209-613).

검증 축:
- manifest: 정책 §2 라이선스 게이트(허용 외 거부·실확인 기록 필수·중복 sourceId 거부)
- chunking: 문단 병합(MIN)·장문 분할(MAX)·꼬리 보존
- store: 저장/로드 라운드트립 + 정규화 + json/npz 짝 불일치 검출
- retriever: 임베딩 mock으로 top-k·임계값·미배포(RagUnavailableError)·KB Version
"""

from __future__ import annotations

import json
import tempfile
import types
import unittest
from pathlib import Path
from unittest import mock

import numpy as np

from rag import chunking, manifest, retriever, store


def _manifest_dict(**source_overrides) -> dict:
    source = {
        "sourceId": "kicce-mr2303",
        "title": "아동의 사회·정서 발달지원 서비스 현황분석",
        "publisher": "육아정책연구소",
        "url": "https://repo.kicce.re.kr/example.pdf",
        "license": "KOGL-1",
        "licenseVerifiedAt": "2026-07-31",
        "collectedAt": "2026-07-31",
        "sha256": "abc123",
        "tags": ["DEV_STAGE"],
    }
    source.update(source_overrides)
    return {"knowledgeBaseVersion": "kb-2026.07-1", "sources": [source]}


def _write_manifest(directory: Path, data: dict) -> Path:
    path = directory / "corpus-manifest.json"
    path.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
    return path


class ManifestGateTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)
        self.addCleanup(self.tmp.cleanup)

    def test_valid_manifest_loads(self):
        loaded = manifest.load(_write_manifest(self.dir, _manifest_dict()))
        self.assertEqual(loaded.knowledge_base_version, "kb-2026.07-1")
        self.assertEqual(loaded.sources[0].source_id, "kicce-mr2303")

    def test_disallowed_license_rejected(self):
        # KOGL-3(변경금지)은 청크 발췌가 변형이라 정책 §2에서 배제 — 빌드 자체를 거부.
        path = _write_manifest(self.dir, _manifest_dict(license="KOGL-3"))
        with self.assertRaises(manifest.ManifestError):
            manifest.load(path)

    def test_missing_license_verification_rejected(self):
        # 자료 단위 실확인 기록이 없으면 거부 — 기관 단위 추정 채택 금지(정책 §2).
        path = _write_manifest(self.dir, _manifest_dict(licenseVerifiedAt=""))
        with self.assertRaises(manifest.ManifestError):
            manifest.load(path)

    def test_duplicate_source_id_rejected(self):
        data = _manifest_dict()
        data["sources"].append(dict(data["sources"][0]))
        with self.assertRaises(manifest.ManifestError):
            manifest.load(_write_manifest(self.dir, data))

    def test_bad_kb_version_rejected(self):
        data = _manifest_dict()
        data["knowledgeBaseVersion"] = "2026.07"
        with self.assertRaises(manifest.ManifestError):
            manifest.load(_write_manifest(self.dir, data))

    def test_empty_sources_rejected(self):
        data = {"knowledgeBaseVersion": "kb-2026.07-1", "sources": []}
        with self.assertRaises(manifest.ManifestError):
            manifest.load(_write_manifest(self.dir, data))


class ChunkingTest(unittest.TestCase):
    def test_short_paragraphs_merge_to_min(self):
        text = "\n\n".join(["가" * 100, "나" * 100, "다" * 150])
        chunks = chunking.split("src", text)
        self.assertEqual(len(chunks), 1)
        self.assertGreaterEqual(len(chunks[0].text), chunking.MIN_CHARS)

    def test_long_paragraph_splits_under_max(self):
        sentence = "아이들은 놀이를 통해 감정을 표현합니다. "
        chunks = chunking.split("src", sentence * 60)  # 약 1,400자 한 문단
        self.assertGreater(len(chunks), 1)
        for c in chunks:
            self.assertLessEqual(len(c.text), chunking.MAX_CHARS)

    def test_tail_shorter_than_min_is_kept(self):
        # 마지막 지식 단위를 버리지 않는다 — 꼬리 문단은 MIN 미만이어도 청크로 남긴다.
        text = ("가" * 400) + "\n\n" + ("나" * 50)
        chunks = chunking.split("src", text)
        self.assertEqual(len(chunks), 2)
        self.assertIn("나", chunks[-1].text)

    def test_chunk_ids_are_sequential_per_source(self):
        chunks = chunking.split("src", ("가" * 400) + "\n\n" + ("나" * 400))
        self.assertEqual([c.chunk_id for c in chunks], ["src#0", "src#1"])


def _sample_index(vectors: np.ndarray) -> store.Index:
    chunks = [
        store.ChunkRecord(
            chunk_id=f"src#{i}", source_id="src", title="제목", text=f"청크 {i}"
        )
        for i in range(vectors.shape[0])
    ]
    return store.Index(
        knowledge_base_version="kb-2026.07-1",
        embedding_model="text-embedding-3-small",
        chunks=chunks,
        vectors=vectors,
    )


class StoreRoundTripTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)
        self.addCleanup(self.tmp.cleanup)

    def test_save_and_load_round_trip_with_normalization(self):
        store.save(self.dir, _sample_index(np.array([[3.0, 4.0], [0.0, 2.0]])))
        loaded = store.load(self.dir)
        self.assertEqual(loaded.knowledge_base_version, "kb-2026.07-1")
        self.assertEqual(len(loaded.chunks), 2)
        # 저장 시 L2 정규화 — 모든 행의 노름이 1이어야 검색이 dot=cosine이 된다.
        np.testing.assert_allclose(np.linalg.norm(loaded.vectors, axis=1), [1.0, 1.0], rtol=1e-6)

    def test_missing_files_raise_file_not_found(self):
        with self.assertRaises(FileNotFoundError):
            store.load(self.dir)

    def test_mismatched_pair_rejected(self):
        store.save(self.dir, _sample_index(np.eye(3, dtype=np.float32)))
        meta = json.loads((self.dir / store.INDEX_META).read_text(encoding="utf-8"))
        meta["chunks"] = meta["chunks"][:2]  # json만 다른 빌드로 조작
        (self.dir / store.INDEX_META).write_text(json.dumps(meta), encoding="utf-8")
        with self.assertRaises(store.IndexFormatError):
            store.load(self.dir)


class RetrieverTest(unittest.TestCase):
    """retriever의 지연 로딩 전역 상태를 테스트마다 초기화하고, 임베딩은 mock."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)
        self.addCleanup(self.tmp.cleanup)
        retriever._index = None
        retriever._load_failed = False
        self.addCleanup(lambda: setattr(retriever, "_index", None))
        self.addCleanup(lambda: setattr(retriever, "_load_failed", False))

    def _deploy_index(self):
        # 정규화된 3개 청크: x축·y축·x축 근처. 질의를 x축으로 주면 0·2가 상위.
        vectors = np.array(
            [[1.0, 0.0], [0.0, 1.0], [0.98, 0.199]], dtype=np.float32
        )
        store.save(self.dir, _sample_index(vectors))

    def _patch(self, query_vector):
        embed = mock.patch.object(
            retriever, "_embed_query", return_value=np.asarray(query_vector, dtype=np.float32)
        )
        index_dir = mock.patch.object(retriever.config, "RAG_INDEX_DIR", str(self.dir))
        return embed, index_dir

    def test_returns_top_k_above_threshold(self):
        self._deploy_index()
        embed, index_dir = self._patch([1.0, 0.0])
        with embed, index_dir:
            chunks = retriever.retrieve("관찰 특징: 집을 크게 그림", k=2, score_threshold=0.5)
        self.assertEqual([c.chunk_id for c in chunks], ["src#0", "src#2"])
        self.assertGreaterEqual(chunks[0].score, chunks[1].score)

    def test_below_threshold_returns_empty_not_error(self):
        # 저점수 근거는 버린다 — 빈 목록은 '쓸 근거 없음'이지 실패가 아니다.
        self._deploy_index()
        embed, index_dir = self._patch([-1.0, 0.0])
        with embed, index_dir:
            chunks = retriever.retrieve("질의", k=3, score_threshold=0.5)
        self.assertEqual(chunks, [])

    def test_missing_index_raises_unavailable(self):
        embed, index_dir = self._patch([1.0, 0.0])
        with embed, index_dir:
            with self.assertRaises(retriever.RagUnavailableError):
                retriever.retrieve("질의")

    def test_missing_index_failure_is_remembered(self):
        # 미배포 판정은 캐시된다 — 매 리포트 호출마다 디스크를 두드리지 않는다.
        _, index_dir = self._patch([1.0, 0.0])
        with index_dir:
            self.assertIsNone(retriever.knowledge_base_version())
            with mock.patch.object(retriever.store, "load") as load_spy:
                self.assertIsNone(retriever.knowledge_base_version())
                load_spy.assert_not_called()

    def test_kb_version_exposed_when_deployed(self):
        self._deploy_index()
        _, index_dir = self._patch([1.0, 0.0])
        with index_dir:
            self.assertEqual(retriever.knowledge_base_version(), "kb-2026.07-1")

    def test_gms_error_maps_to_unavailable(self):
        self._deploy_index()
        index_dir = mock.patch.object(retriever.config, "RAG_INDEX_DIR", str(self.dir))
        fake_client = mock.Mock()
        from openai import OpenAIError

        fake_client.embeddings.create.side_effect = OpenAIError("boom")
        with index_dir, mock.patch.object(retriever, "get_client", return_value=fake_client):
            with self.assertRaises(retriever.RagUnavailableError):
                retriever.retrieve("질의")


if __name__ == "__main__":
    unittest.main()
