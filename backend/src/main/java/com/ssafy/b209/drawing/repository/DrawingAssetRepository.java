package com.ssafy.b209.drawing.repository;

import com.ssafy.b209.drawing.domain.DrawingAsset;
import com.ssafy.b209.drawing.domain.DrawingAssetType;
import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;

/** 그림 파일 Metadata의 저장과 세션 내 중복 여부 조회를 담당한다. */
public interface DrawingAssetRepository extends JpaRepository<DrawingAsset, Long> {

  /**
   * HTP 원본 이미지 업로드의 멱등 키로 저장 결과를 조회한다.
   *
   * @param uploadIdempotencyKey 업로드 요청의 {@code Idempotency-Key}
   * @return 같은 키로 저장된 파일, 없으면 빈 값
   */
  Optional<DrawingAsset> findByUploadIdempotencyKey(String uploadIdempotencyKey);

  /**
   * 세션에서 가장 최근 생성된 그림 파일 Metadata를 조회한다.
   *
   * @param drawingSessionId 그림 활동 세션 식별자
   * @return 생성 시각과 식별자 역순의 첫 번째 그림 파일, 없으면 빈 값
   */
  Optional<DrawingAsset> findFirstByDrawingSessionIdOrderByCreatedAtDescIdDesc(
      Long drawingSessionId);

  /**
   * 세션의 모든 그림 파일 Metadata를 최신순으로 조회한다.
   *
   * @param drawingSessionId 그림 활동 세션 식별자
   * @return 생성 시각과 식별자 역순의 그림 파일 목록, 없으면 빈 목록
   */
  List<DrawingAsset> findAllByDrawingSessionIdOrderByCreatedAtDescIdDesc(Long drawingSessionId);

  /**
   * 동일 세션·유형·버전의 그림 파일이 이미 존재하는지 확인한다.
   *
   * @param drawingSessionId 그림 활동 세션 식별자
   * @param assetType 그림 파일 용도
   * @param assetVersion 그림 파일 버전
   * @return 중복 Metadata가 존재하면 {@code true}
   */
  boolean existsByDrawingSessionIdAndAssetTypeAndAssetVersion(
      Long drawingSessionId, DrawingAssetType assetType, int assetVersion);

  /**
   * 세션에 특정 유형의 그림 파일이 하나라도 존재하는지 확인한다.
   *
   * @param drawingSessionId 그림 활동 세션 식별자
   * @param assetType 그림 파일 용도
   * @return 해당 유형의 Metadata가 존재하면 {@code true}
   */
  boolean existsByDrawingSessionIdAndAssetType(Long drawingSessionId, DrawingAssetType assetType);

  /**
   * 세션과 파일 유형에 해당하는 가장 높은 버전의 Metadata 한 건을 조회한다.
   *
   * @param drawingSessionId 그림 활동 세션 식별자
   * @param assetType 그림 파일 용도
   * @return 가장 높은 버전의 Metadata, 해당 파일이 없으면 빈 값
   */
  Optional<DrawingAsset> findFirstByDrawingSessionIdAndAssetTypeOrderByAssetVersionDesc(
      Long drawingSessionId, DrawingAssetType assetType);

  /**
   * 여러 세션의 특정 유형 그림 파일을 세션·버전·식별자 순으로 한 번에 조회한다.
   *
   * <p>목록 조회에서 세션마다 개별 조회를 하지 않고 배치로 읽어 조립하기 위한 경계다. 각 세션의 첫 항목이 가장 높은 버전이다.
   *
   * @param drawingSessionIds 그림 활동 세션 식별자 목록
   * @param assetType 그림 파일 용도
   * @return 세션 식별자 오름차순, 버전과 식별자 역순으로 정렬된 그림 파일 목록
   */
  List<DrawingAsset>
      findByDrawingSessionIdInAndAssetTypeOrderByDrawingSessionIdAscAssetVersionDescIdDesc(
          List<Long> drawingSessionIds, DrawingAssetType assetType);

  /**
   * 세션의 가장 최근 DRAFT Metadata를 조회한다.
   *
   * @param drawingSessionId 그림 활동 세션 식별자
   * @return 가장 높은 초안 버전, 초안이 없으면 빈 값
   */
  default Optional<DrawingAsset> findLatestDraft(Long drawingSessionId) {
    return findFirstByDrawingSessionIdAndAssetTypeOrderByAssetVersionDesc(
        drawingSessionId, DrawingAssetType.DRAFT);
  }
}
