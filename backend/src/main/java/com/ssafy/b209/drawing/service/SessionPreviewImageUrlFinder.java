package com.ssafy.b209.drawing.service;

import com.ssafy.b209.drawing.domain.DrawingAsset;
import com.ssafy.b209.drawing.domain.DrawingAssetType;
import com.ssafy.b209.drawing.repository.DrawingAssetRepository;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.springframework.stereotype.Component;

/**
 * 목록·미리보기 화면에 표시할 세션 대표 이미지 URL을 세션마다 한 건씩 확정한다.
 *
 * <p>축소 이미지({@code THUMBNAIL})가 있으면 그것을, 없으면 최종 스냅샷({@code FINAL})을, 그래도 없으면 업로드 원본({@code
 * UPLOADED})을 대표 이미지로 인정한다. 사진 업로드로 진행한 세션은 최종 그림을 다시 그리지 않아 업로드 원본만 존재하므로, 마지막 폴백이 없으면 대표 이미지가 없는
 * 세션으로 취급되어 화면에 빈 자리가 남는다.
 *
 * <p>{@code UPLOADED}는 사진 업로드 경로에서만 저장되므로 유형 우선순위만으로 폴백해도 Canvas 세션의 결과는 달라지지 않는다. 세션 유형별로 규칙이 갈리지
 * 않게 이 경계 한 곳에만 우선순위를 둔다. 최종 그림 한 건을 확정하는 규칙은 {@link StageFinalImageFinder}가 담당하며, 이쪽은 화면 표시용 대표
 * 이미지만 고른다.
 */
@Component
public class SessionPreviewImageUrlFinder {

  private static final List<DrawingAssetType> PREVIEW_PRIORITY =
      List.of(DrawingAssetType.THUMBNAIL, DrawingAssetType.FINAL, DrawingAssetType.UPLOADED);

  private final DrawingAssetRepository drawingAssetRepository;
  private final DrawingAssetFileUrlFactory fileUrlFactory;

  /**
   * 대표 이미지 조회에 사용할 저장소와 URL 생성기를 주입받는다.
   *
   * @param drawingAssetRepository 그림 파일 Metadata 저장소
   * @param fileUrlFactory 인증된 그림 파일 조회 URL 생성기
   */
  public SessionPreviewImageUrlFinder(
      DrawingAssetRepository drawingAssetRepository, DrawingAssetFileUrlFactory fileUrlFactory) {
    this.drawingAssetRepository = drawingAssetRepository;
    this.fileUrlFactory = fileUrlFactory;
  }

  /**
   * 여러 세션의 대표 이미지 URL을 세션별로 한 건씩 찾는다.
   *
   * <p>세션마다 개별 조회하지 않고 파일 유형별로 한 번씩 배치 조회하며, 앞선 유형에서 이미 대표 이미지를 찾은 세션은 다음 유형 조회 대상에서 제외한다. 반환 Map은
   * 대표 이미지가 있는 세션만 담는다.
   *
   * @param sessionIds 대표 이미지를 찾을 그림 활동 세션 식별자 목록
   * @return 세션 식별자를 Key로 하는 대표 이미지 조회 URL Map
   */
  public Map<Long, String> findAllBySessionId(List<Long> sessionIds) {
    Map<Long, String> urlBySession = new LinkedHashMap<>();
    List<Long> remainingSessionIds = sessionIds.stream().distinct().toList();
    for (DrawingAssetType assetType : PREVIEW_PRIORITY) {
      if (remainingSessionIds.isEmpty()) {
        return urlBySession;
      }
      for (DrawingAsset asset :
          drawingAssetRepository
              .findByDrawingSessionIdInAndAssetTypeOrderByDrawingSessionIdAscAssetVersionDescIdDesc(
                  remainingSessionIds, assetType)) {
        urlBySession.putIfAbsent(
            asset.getDrawingSession().getId(), fileUrlFactory.create(asset.getId()));
      }
      remainingSessionIds =
          remainingSessionIds.stream()
              .filter(sessionId -> !urlBySession.containsKey(sessionId))
              .toList();
    }
    return urlBySession;
  }
}
