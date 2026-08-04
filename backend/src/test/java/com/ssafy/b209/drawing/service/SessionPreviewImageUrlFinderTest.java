package com.ssafy.b209.drawing.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.verifyNoMoreInteractions;

import com.ssafy.b209.drawing.domain.DrawingAsset;
import com.ssafy.b209.drawing.domain.DrawingAssetType;
import com.ssafy.b209.drawing.domain.DrawingSession;
import com.ssafy.b209.drawing.repository.DrawingAssetRepository;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class SessionPreviewImageUrlFinderTest {

  @Mock private DrawingAssetRepository drawingAssetRepository;

  private SessionPreviewImageUrlFinder finder;

  @BeforeEach
  void setUp() {
    finder =
        new SessionPreviewImageUrlFinder(drawingAssetRepository, new DrawingAssetFileUrlFactory());
  }

  @Test
  void prefersThumbnailWithoutQueryingLaterTypes() {
    givenAssets(List.of(1L), DrawingAssetType.THUMBNAIL, assetOf(1L, 30L));

    Map<Long, String> urls = finder.findAllBySessionId(List.of(1L));

    assertThat(urls).containsExactly(Map.entry(1L, "/api/v1/drawing-assets/30/file"));
    verify(drawingAssetRepository)
        .findByDrawingSessionIdInAndAssetTypeOrderByDrawingSessionIdAscAssetVersionDescIdDesc(
            List.of(1L), DrawingAssetType.THUMBNAIL);
    verifyNoMoreInteractions(drawingAssetRepository);
  }

  @Test
  void fallsBackToFinalSnapshotWhenThumbnailMissing() {
    givenAssets(List.of(1L), DrawingAssetType.THUMBNAIL);
    givenAssets(List.of(1L), DrawingAssetType.FINAL, assetOf(1L, 31L));

    Map<Long, String> urls = finder.findAllBySessionId(List.of(1L));

    assertThat(urls).containsExactly(Map.entry(1L, "/api/v1/drawing-assets/31/file"));
    verify(drawingAssetRepository, org.mockito.Mockito.never())
        .findByDrawingSessionIdInAndAssetTypeOrderByDrawingSessionIdAscAssetVersionDescIdDesc(
            List.of(1L), DrawingAssetType.UPLOADED);
  }

  @Test
  void fallsBackToUploadedOriginalWhenSessionHasNoSnapshot() {
    givenAssets(List.of(1L), DrawingAssetType.THUMBNAIL);
    givenAssets(List.of(1L), DrawingAssetType.FINAL);
    givenAssets(List.of(1L), DrawingAssetType.UPLOADED, assetOf(1L, 32L));

    Map<Long, String> urls = finder.findAllBySessionId(List.of(1L));

    assertThat(urls).containsExactly(Map.entry(1L, "/api/v1/drawing-assets/32/file"));
  }

  @Test
  void resolvesEachSessionIndependentlyAndNarrowsLaterQueries() {
    givenAssets(List.of(1L, 2L, 3L), DrawingAssetType.THUMBNAIL, assetOf(1L, 30L));
    givenAssets(List.of(2L, 3L), DrawingAssetType.FINAL, assetOf(2L, 31L));
    givenAssets(List.of(3L), DrawingAssetType.UPLOADED, assetOf(3L, 32L));

    Map<Long, String> urls = finder.findAllBySessionId(List.of(1L, 2L, 3L));

    assertThat(urls)
        .containsOnly(
            Map.entry(1L, "/api/v1/drawing-assets/30/file"),
            Map.entry(2L, "/api/v1/drawing-assets/31/file"),
            Map.entry(3L, "/api/v1/drawing-assets/32/file"));
  }

  @Test
  void omitsSessionsWithoutAnyImage() {
    givenAssets(List.of(1L), DrawingAssetType.THUMBNAIL);
    givenAssets(List.of(1L), DrawingAssetType.FINAL);
    givenAssets(List.of(1L), DrawingAssetType.UPLOADED);

    assertThat(finder.findAllBySessionId(List.of(1L))).isEmpty();
  }

  @Test
  void keepsHighestVersionWhenSessionHasSeveralAssetsOfSameType() {
    // 저장소가 버전 내림차순으로 돌려주므로 먼저 만난 파일이 최신 버전이다.
    givenAssets(List.of(1L), DrawingAssetType.THUMBNAIL, assetOf(1L, 41L), assetOf(1L, 40L));

    assertThat(finder.findAllBySessionId(List.of(1L)))
        .containsExactly(Map.entry(1L, "/api/v1/drawing-assets/41/file"));
  }

  @Test
  void queriesNothingForEmptySessionList() {
    assertThat(finder.findAllBySessionId(List.of())).isEmpty();
    verifyNoInteractions(drawingAssetRepository);
  }

  @Test
  void deduplicatesRepeatedSessionIds() {
    givenAssets(List.of(1L), DrawingAssetType.THUMBNAIL, assetOf(1L, 30L));

    assertThat(finder.findAllBySessionId(List.of(1L, 1L)))
        .containsExactly(Map.entry(1L, "/api/v1/drawing-assets/30/file"));
  }

  private void givenAssets(
      List<Long> sessionIds, DrawingAssetType assetType, DrawingAsset... assets) {
    given(
            drawingAssetRepository
                .findByDrawingSessionIdInAndAssetTypeOrderByDrawingSessionIdAscAssetVersionDescIdDesc(
                    sessionIds, assetType))
        .willReturn(List.of(assets));
  }

  private DrawingAsset assetOf(Long sessionId, Long assetId) {
    DrawingSession session = mock(DrawingSession.class);
    given(session.getId()).willReturn(sessionId);
    DrawingAsset asset = mock(DrawingAsset.class);
    given(asset.getId()).willReturn(assetId);
    given(asset.getDrawingSession()).willReturn(session);
    return asset;
  }
}
