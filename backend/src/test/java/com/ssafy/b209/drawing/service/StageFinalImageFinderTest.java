package com.ssafy.b209.drawing.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;

import com.ssafy.b209.child.domain.Child;
import com.ssafy.b209.child.domain.ChildFixture;
import com.ssafy.b209.child.domain.ChildProfileStatus;
import com.ssafy.b209.child.domain.ChildTutorialStatus;
import com.ssafy.b209.drawing.domain.DrawingAsset;
import com.ssafy.b209.drawing.domain.DrawingAssetType;
import com.ssafy.b209.drawing.domain.DrawingInputMethod;
import com.ssafy.b209.drawing.domain.DrawingSession;
import com.ssafy.b209.drawing.domain.DrawingType;
import com.ssafy.b209.drawing.domain.DrawingTypeFixture;
import com.ssafy.b209.drawing.domain.DrawingTypeSelectableBy;
import com.ssafy.b209.drawing.repository.DrawingAssetRepository;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.test.util.ReflectionTestUtils;

@ExtendWith(MockitoExtension.class)
class StageFinalImageFinderTest {

  private static final LocalDateTime SERVER_TIME = LocalDateTime.of(2026, 7, 30, 1, 0);
  private static final long CANVAS_SESSION_ID = 100L;
  private static final long UPLOAD_SESSION_ID = 101L;

  @Mock private DrawingAssetRepository drawingAssetRepository;

  private StageFinalImageFinder finder;
  private Child child;
  private DrawingType drawingType;

  @BeforeEach
  void setUp() {
    finder = new StageFinalImageFinder(drawingAssetRepository);
    child =
        ChildFixture.create(
            1L,
            LocalDate.of(2018, 7, 30),
            ChildTutorialStatus.COMPLETED,
            ChildProfileStatus.ACTIVE,
            null);
    drawingType =
        DrawingTypeFixture.create(
            10L, "HTP", "집·나무·사람 그림", DrawingTypeSelectableBy.GUARDIAN, 4, 12, true);
  }

  @Test
  void usesTheFinalSnapshotOfACanvasSession() {
    DrawingSession canvas = session(CANVAS_SESSION_ID, DrawingInputMethod.CANVAS);
    DrawingAsset finalImage = finalAsset(canvas, 501L, 1);
    stubAssets(List.of(CANVAS_SESSION_ID), DrawingAssetType.FINAL, List.of(finalImage));

    assertThat(finder.find(canvas)).containsSame(finalImage);
    verify(drawingAssetRepository, never())
        .findByDrawingSessionIdInAndAssetTypeOrderByDrawingSessionIdAscAssetVersionDescIdDesc(
            List.of(CANVAS_SESSION_ID), DrawingAssetType.UPLOADED);
  }

  @Test
  void picksTheHighestFinalVersionOfASession() {
    DrawingSession canvas = session(CANVAS_SESSION_ID, DrawingInputMethod.CANVAS);
    DrawingAsset latest = finalAsset(canvas, 502L, 2);
    DrawingAsset previous = finalAsset(canvas, 501L, 1);
    stubAssets(List.of(CANVAS_SESSION_ID), DrawingAssetType.FINAL, List.of(latest, previous));

    assertThat(finder.find(canvas)).containsSame(latest);
  }

  @Test
  void rejectsACanvasSessionWithoutAFinalSnapshotInsteadOfUsingAnUploadedPhoto() {
    DrawingSession canvas = session(CANVAS_SESSION_ID, DrawingInputMethod.CANVAS);
    stubAssets(List.of(CANVAS_SESSION_ID), DrawingAssetType.FINAL, List.of());

    assertThat(finder.find(canvas)).isEmpty();
    verify(drawingAssetRepository, never())
        .findByDrawingSessionIdInAndAssetTypeOrderByDrawingSessionIdAscAssetVersionDescIdDesc(
            List.of(CANVAS_SESSION_ID), DrawingAssetType.UPLOADED);
  }

  @Test
  void fallsBackToTheUploadedPhotoOfAnUploadSessionWithoutAFinalSnapshot() {
    DrawingSession upload = session(UPLOAD_SESSION_ID, DrawingInputMethod.UPLOAD);
    DrawingAsset uploaded = uploadedAsset(upload, 601L);
    stubAssets(List.of(UPLOAD_SESSION_ID), DrawingAssetType.FINAL, List.of());
    stubAssets(List.of(UPLOAD_SESSION_ID), DrawingAssetType.UPLOADED, List.of(uploaded));

    assertThat(finder.find(upload)).containsSame(uploaded);
  }

  @Test
  void prefersTheFinalSnapshotOverTheUploadedPhotoOfAnUploadSession() {
    DrawingSession upload = session(UPLOAD_SESSION_ID, DrawingInputMethod.UPLOAD);
    DrawingAsset finalImage = finalAsset(upload, 503L, 1);
    stubAssets(List.of(UPLOAD_SESSION_ID), DrawingAssetType.FINAL, List.of(finalImage));

    assertThat(finder.find(upload)).containsSame(finalImage);
    verify(drawingAssetRepository, never())
        .findByDrawingSessionIdInAndAssetTypeOrderByDrawingSessionIdAscAssetVersionDescIdDesc(
            List.of(UPLOAD_SESSION_ID), DrawingAssetType.UPLOADED);
  }

  @Test
  void appliesTheFallbackOnlyToUploadSessionsOfAMixedBatch() {
    DrawingSession canvas = session(CANVAS_SESSION_ID, DrawingInputMethod.CANVAS);
    DrawingSession upload = session(UPLOAD_SESSION_ID, DrawingInputMethod.UPLOAD);
    DrawingAsset uploaded = uploadedAsset(upload, 601L);
    stubAssets(List.of(CANVAS_SESSION_ID, UPLOAD_SESSION_ID), DrawingAssetType.FINAL, List.of());
    stubAssets(List.of(UPLOAD_SESSION_ID), DrawingAssetType.UPLOADED, List.of(uploaded));

    assertThat(finder.findAllBySession(List.of(canvas, upload)))
        .containsOnlyKeys(UPLOAD_SESSION_ID)
        .containsEntry(UPLOAD_SESSION_ID, uploaded);
  }

  @Test
  void returnsAnEmptyResultWithoutQueryingWhenNoSessionIsGiven() {
    assertThat(finder.findAllBySession(List.of())).isEmpty();
    verifyNoInteractions(drawingAssetRepository);
  }

  private void stubAssets(
      List<Long> sessionIds, DrawingAssetType assetType, List<DrawingAsset> assets) {
    given(
            drawingAssetRepository
                .findByDrawingSessionIdInAndAssetTypeOrderByDrawingSessionIdAscAssetVersionDescIdDesc(
                    sessionIds, assetType))
        .willReturn(assets);
  }

  private DrawingSession session(Long id, DrawingInputMethod inputMethod) {
    DrawingSession session =
        DrawingSession.start(child, drawingType, inputMethod, SERVER_TIME, "session-key-" + id);
    ReflectionTestUtils.setField(session, "id", id);
    return session;
  }

  private DrawingAsset finalAsset(DrawingSession session, Long id, int assetVersion) {
    DrawingAsset asset =
        DrawingAsset.snapshot(
            session,
            DrawingAssetType.FINAL,
            assetVersion,
            "images/" + id + ".png",
            "image/png",
            1024,
            320,
            320,
            "a".repeat(64),
            SERVER_TIME.minusMinutes(40),
            SERVER_TIME.minusMinutes(40));
    ReflectionTestUtils.setField(asset, "id", id);
    return asset;
  }

  private DrawingAsset uploadedAsset(DrawingSession session, Long id) {
    DrawingAsset asset =
        DrawingAsset.uploaded(
            session,
            "images/" + id + ".jpg",
            "image/jpeg",
            2048,
            1440,
            1080,
            "b".repeat(64),
            SERVER_TIME.minusMinutes(45),
            SERVER_TIME.minusMinutes(44),
            "upload-key-" + id,
            "f".repeat(64),
            0,
            true);
    ReflectionTestUtils.setField(asset, "id", id);
    return asset;
  }
}
