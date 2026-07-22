package com.ssafy.b209.drawing.repository;

import com.ssafy.b209.drawing.domain.DrawingAsset;
import com.ssafy.b209.drawing.domain.DrawingAssetType;
import org.springframework.data.jpa.repository.JpaRepository;

/** 그림 파일 Metadata의 저장과 세션 내 중복 여부 조회를 담당한다. */
public interface DrawingAssetRepository extends JpaRepository<DrawingAsset, Long> {

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
}
