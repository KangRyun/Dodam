package com.ssafy.b209.drawing.service;

import com.ssafy.b209.drawing.domain.DrawingAsset;
import com.ssafy.b209.drawing.domain.DrawingAssetType;
import com.ssafy.b209.drawing.domain.DrawingInputMethod;
import com.ssafy.b209.drawing.domain.DrawingSession;
import com.ssafy.b209.drawing.repository.DrawingAssetRepository;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.function.Function;
import java.util.stream.Collectors;
import org.springframework.stereotype.Component;

/**
 * 세션의 결과물로 인정할 최종 그림을 한 건 확정한다.
 *
 * <p>Canvas 세션은 {@code FINAL} 스냅샷만 최종 그림으로 인정한다. 사진 업로드 세션은 최종 그림을 다시 그리지 않고 업로드한 사진 자체가 결과물이므로
 * {@code FINAL}이 없으면 같은 세션의 {@code UPLOADED} 원본을 최종 그림으로 인정한다.
 *
 * <p>HTP 완료 게이트와 리포트 재생성이 같은 판단을 하도록 규칙을 이 경계에만 둔다. 공개 분석 요청의 Asset 정책은 이 규칙과 무관하게 유지된다.
 */
@Component
public class StageFinalImageFinder {

  private final DrawingAssetRepository drawingAssetRepository;

  /**
   * 최종 그림 조회에 사용할 저장소를 주입받는다.
   *
   * @param drawingAssetRepository 그림 파일 Metadata 저장소
   */
  public StageFinalImageFinder(DrawingAssetRepository drawingAssetRepository) {
    this.drawingAssetRepository = drawingAssetRepository;
  }

  /**
   * 세션 하나의 최종 그림을 찾는다.
   *
   * @param session 최종 그림을 찾을 그림 활동 세션
   * @return 최종 그림으로 인정한 그림 파일, 없으면 빈 값
   */
  public Optional<DrawingAsset> find(DrawingSession session) {
    return Optional.ofNullable(findAllBySession(List.of(session)).get(session.getId()));
  }

  /**
   * 여러 세션의 최종 그림을 세션별로 한 건씩 찾는다.
   *
   * <p>세션마다 개별 조회하지 않고 파일 유형별로 한 번씩 배치 조회한다. 반환 Map은 최종 그림이 있는 세션만 담는다.
   *
   * @param sessions 최종 그림을 찾을 그림 활동 세션 목록
   * @return 세션 식별자를 Key로 하는 최종 그림 Map
   */
  public Map<Long, DrawingAsset> findAllBySession(List<DrawingSession> sessions) {
    if (sessions.isEmpty()) {
      return Map.of();
    }
    List<Long> sessionIds = sessions.stream().map(DrawingSession::getId).toList();
    Map<Long, DrawingAsset> images =
        new LinkedHashMap<>(latestAssetsBySession(sessionIds, DrawingAssetType.FINAL));
    List<Long> uploadSessionIds =
        sessions.stream()
            .filter(session -> session.getInputMethod() == DrawingInputMethod.UPLOAD)
            .map(DrawingSession::getId)
            .filter(sessionId -> !images.containsKey(sessionId))
            .toList();
    if (!uploadSessionIds.isEmpty()) {
      latestAssetsBySession(uploadSessionIds, DrawingAssetType.UPLOADED)
          .forEach(images::putIfAbsent);
    }
    return images;
  }

  private Map<Long, DrawingAsset> latestAssetsBySession(
      List<Long> sessionIds, DrawingAssetType assetType) {
    return drawingAssetRepository
        .findByDrawingSessionIdInAndAssetTypeOrderByDrawingSessionIdAscAssetVersionDescIdDesc(
            sessionIds, assetType)
        .stream()
        .collect(
            Collectors.toMap(
                asset -> asset.getDrawingSession().getId(),
                Function.identity(),
                (latest, ignored) -> latest));
  }
}
