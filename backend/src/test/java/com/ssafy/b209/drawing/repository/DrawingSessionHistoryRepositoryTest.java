package com.ssafy.b209.drawing.repository;

import static org.assertj.core.api.Assertions.assertThat;

import com.ssafy.b209.analysis.domain.DrawingAnalysis;
import com.ssafy.b209.analysis.domain.DrawingAnalysisScope;
import com.ssafy.b209.analysis.domain.DrawingAnalysisState;
import com.ssafy.b209.analysis.dto.DrawingAnalysisType;
import com.ssafy.b209.analysis.repository.DrawingAnalysisRepository;
import com.ssafy.b209.child.domain.Child;
import com.ssafy.b209.child.domain.ChildFixture;
import com.ssafy.b209.child.domain.ChildProfileStatus;
import com.ssafy.b209.child.domain.ChildTutorialStatus;
import com.ssafy.b209.child.repository.ChildRepository;
import com.ssafy.b209.drawing.domain.DrawingAsset;
import com.ssafy.b209.drawing.domain.DrawingAssetType;
import com.ssafy.b209.drawing.domain.DrawingEmotionCode;
import com.ssafy.b209.drawing.domain.DrawingInputMethod;
import com.ssafy.b209.drawing.domain.DrawingSession;
import com.ssafy.b209.drawing.domain.DrawingSessionEmotion;
import com.ssafy.b209.drawing.domain.DrawingSessionStatus;
import com.ssafy.b209.drawing.domain.DrawingType;
import com.ssafy.b209.drawing.domain.DrawingTypeFixture;
import com.ssafy.b209.drawing.domain.DrawingTypeSelectableBy;
import com.ssafy.b209.report.domain.Report;
import com.ssafy.b209.report.domain.ReportStatus;
import com.ssafy.b209.report.repository.ReportRepository;
import jakarta.persistence.EntityManager;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Sort;
import org.springframework.test.context.ActiveProfiles;

@DataJpaTest
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@ActiveProfiles("test")
class DrawingSessionHistoryRepositoryTest {

  private static final Sort STARTED_DESC = Sort.by(Sort.Direction.DESC, "startedAt");

  @Autowired private EntityManager entityManager;
  @Autowired private ChildRepository childRepository;
  @Autowired private DrawingTypeRepository drawingTypeRepository;
  @Autowired private DrawingSessionRepository drawingSessionRepository;
  @Autowired private DrawingSessionEmotionRepository drawingSessionEmotionRepository;
  @Autowired private DrawingAssetRepository drawingAssetRepository;
  @Autowired private DrawingAnalysisRepository drawingAnalysisRepository;
  @Autowired private ReportRepository reportRepository;

  private Long childId;
  private DrawingType house;
  private DrawingType tree;
  private DrawingSession completedHouse;
  private DrawingSession inProgressTree;
  private DrawingSession failedHouse;

  @BeforeEach
  void setUp() {
    Child child =
        childRepository.save(
            ChildFixture.create(
                null,
                LocalDate.of(2018, 7, 24),
                ChildTutorialStatus.COMPLETED,
                ChildProfileStatus.ACTIVE,
                null));
    childId = child.getId();
    house =
        drawingTypeRepository.save(
            DrawingTypeFixture.create(
                null, "HOUSE", "집", DrawingTypeSelectableBy.BOTH, 6, 10, true));
    tree =
        drawingTypeRepository.save(
            DrawingTypeFixture.create(
                null, "TREE", "나무", DrawingTypeSelectableBy.BOTH, 6, 10, true));

    completedHouse = saveSession(child, house, LocalDateTime.of(2026, 7, 1, 10, 0), "hist-k1");
    inProgressTree = saveSession(child, tree, LocalDateTime.of(2026, 7, 5, 9, 0), "hist-k2");
    failedHouse = saveSession(child, house, LocalDateTime.of(2026, 7, 10, 8, 0), "hist-k3");
    DrawingSession deletedStatus =
        saveSession(child, house, LocalDateTime.of(2026, 7, 3, 8, 0), "hist-k4");
    DrawingSession softDeleted =
        saveSession(child, house, LocalDateTime.of(2026, 7, 4, 8, 0), "hist-k5");

    entityManager.flush();
    setStatus(completedHouse.getId(), "COMPLETED", LocalDateTime.of(2026, 7, 1, 10, 30));
    setStatus(failedHouse.getId(), "FAILED", null);
    setStatus(deletedStatus.getId(), "DELETED", null);
    softDelete(softDeleted.getId(), LocalDateTime.of(2026, 7, 4, 9, 0));
    entityManager.clear();
  }

  @Test
  void returnsNonDeletedSessionsForChildOrderedByStartedAtDesc() {
    Page<DrawingSession> page =
        drawingSessionRepository.findHistoryPage(
            childId, null, null, null, null, null, PageRequest.of(0, 20, STARTED_DESC));

    assertThat(page.getTotalElements()).isEqualTo(3);
    assertThat(page.getContent())
        .extracting(DrawingSession::getId)
        .containsExactly(failedHouse.getId(), inProgressTree.getId(), completedHouse.getId());
  }

  @Test
  void filtersByDrawingTypeCode() {
    Page<DrawingSession> page =
        drawingSessionRepository.findHistoryPage(
            childId, null, null, "HOUSE", null, null, PageRequest.of(0, 20, STARTED_DESC));

    assertThat(page.getContent())
        .extracting(DrawingSession::getId)
        .containsExactly(failedHouse.getId(), completedHouse.getId());
  }

  @Test
  void filtersBySessionStatus() {
    Page<DrawingSession> page =
        drawingSessionRepository.findHistoryPage(
            childId,
            null,
            null,
            null,
            DrawingSessionStatus.COMPLETED,
            null,
            PageRequest.of(0, 20, STARTED_DESC));

    assertThat(page.getContent())
        .extracting(DrawingSession::getId)
        .containsExactly(completedHouse.getId());
  }

  @Test
  void filtersByStartedAtRangeWithExclusiveUpperBound() {
    Page<DrawingSession> page =
        drawingSessionRepository.findHistoryPage(
            childId,
            LocalDateTime.of(2026, 7, 4, 0, 0),
            LocalDateTime.of(2026, 7, 7, 0, 0),
            null,
            null,
            null,
            PageRequest.of(0, 20, STARTED_DESC));

    assertThat(page.getContent())
        .extracting(DrawingSession::getId)
        .containsExactly(inProgressTree.getId());
  }

  @Test
  void filtersByLatestReportStatusOnly() {
    DrawingAsset asset = saveDraft(failedHouse, 1, LocalDateTime.of(2026, 7, 10, 8, 1));
    DrawingAnalysis analysis =
        drawingAnalysisRepository.save(
            DrawingAnalysis.processing(
                failedHouse,
                asset,
                DrawingAnalysisScope.FINAL,
                DrawingAnalysisType.OBJECT_DETECTION,
                "hist-analysis-1",
                LocalDateTime.of(2026, 7, 10, 8, 2)));
    Report older = Report.generating(failedHouse, analysis, 1, LocalDateTime.of(2026, 7, 10, 8, 3));
    older.fail("older failed", LocalDateTime.of(2026, 7, 10, 8, 4));
    reportRepository.save(older);
    Report latest =
        Report.generating(failedHouse, analysis, 2, LocalDateTime.of(2026, 7, 10, 8, 5));
    latest.complete(false, "latest completed", LocalDateTime.of(2026, 7, 10, 8, 6));
    reportRepository.save(latest);
    entityManager.flush();
    entityManager.clear();

    assertThat(
            drawingSessionRepository
                .findHistoryPage(
                    childId,
                    null,
                    null,
                    null,
                    null,
                    ReportStatus.COMPLETED,
                    PageRequest.of(0, 20, STARTED_DESC))
                .getContent())
        .extracting(DrawingSession::getId)
        .containsExactly(failedHouse.getId());
    assertThat(
            drawingSessionRepository
                .findHistoryPage(
                    childId,
                    null,
                    null,
                    null,
                    null,
                    ReportStatus.FAILED,
                    PageRequest.of(0, 20, STARTED_DESC))
                .getContent())
        .isEmpty();
  }

  @Test
  void filtersLatestReportByCreatedAtBeforeId() {
    DrawingAsset asset = saveDraft(failedHouse, 1, LocalDateTime.of(2026, 7, 10, 8, 1));
    DrawingAnalysis analysis =
        drawingAnalysisRepository.save(
            DrawingAnalysis.processing(
                failedHouse,
                asset,
                DrawingAnalysisScope.FINAL,
                DrawingAnalysisType.OBJECT_DETECTION,
                "hist-analysis-created-at",
                LocalDateTime.of(2026, 7, 10, 8, 2)));
    Report latestByTime =
        Report.generating(failedHouse, analysis, 1, LocalDateTime.of(2026, 7, 10, 9, 0));
    latestByTime.complete(false, "latest completed", LocalDateTime.of(2026, 7, 10, 9, 1));
    reportRepository.save(latestByTime);
    Report higherIdButOlder =
        Report.generating(failedHouse, analysis, 2, LocalDateTime.of(2026, 7, 10, 8, 0));
    higherIdButOlder.fail("older failed", LocalDateTime.of(2026, 7, 10, 8, 1));
    reportRepository.save(higherIdButOlder);
    entityManager.flush();
    entityManager.clear();

    assertThat(
            drawingSessionRepository
                .findHistoryPage(
                    childId,
                    null,
                    null,
                    null,
                    null,
                    ReportStatus.COMPLETED,
                    PageRequest.of(0, 20, STARTED_DESC))
                .getContent())
        .extracting(DrawingSession::getId)
        .containsExactly(failedHouse.getId());
  }

  @Test
  void sortsByCompletedAtAndPaginates() {
    Sort completedDesc =
        Sort.by(
            new Sort.Order(Sort.Direction.DESC, "completedAt", Sort.NullHandling.NULLS_LAST),
            new Sort.Order(Sort.Direction.DESC, "id"));
    Page<DrawingSession> firstPage =
        drawingSessionRepository.findHistoryPage(
            childId, null, null, null, null, null, PageRequest.of(0, 2, completedDesc));

    assertThat(firstPage.getTotalElements()).isEqualTo(3);
    assertThat(firstPage.getTotalPages()).isEqualTo(2);
    assertThat(firstPage.getContent())
        .extracting(DrawingSession::getId)
        .containsExactly(completedHouse.getId(), failedHouse.getId());
    assertThat(firstPage.hasNext()).isTrue();
  }

  @Test
  void batchQueriesGroupRelatedResourcesBySession() {
    drawingSessionEmotionRepository.save(
        DrawingSessionEmotion.create(completedHouse, DrawingEmotionCode.CALM, 1));
    drawingSessionEmotionRepository.save(
        DrawingSessionEmotion.create(completedHouse, DrawingEmotionCode.HAPPY, 0));

    DrawingAsset olderAsset = saveDraft(inProgressTree, 1, LocalDateTime.of(2026, 7, 5, 9, 1));
    DrawingAsset newerAsset = saveDraft(inProgressTree, 2, LocalDateTime.of(2026, 7, 5, 9, 2));
    drawingAnalysisRepository.save(
        DrawingAnalysis.processing(
            inProgressTree,
            olderAsset,
            DrawingAnalysisScope.INTERMEDIATE,
            DrawingAnalysisType.OBJECT_DETECTION,
            "hist-a-old",
            LocalDateTime.of(2026, 7, 5, 9, 3)));
    DrawingAnalysis newerAnalysis =
        drawingAnalysisRepository.save(
            DrawingAnalysis.processing(
                inProgressTree,
                newerAsset,
                DrawingAnalysisScope.FINAL,
                DrawingAnalysisType.OBJECT_DETECTION,
                "hist-a-new",
                LocalDateTime.of(2026, 7, 5, 9, 4)));
    insertThumbnail(completedHouse.getId(), 1, "https://cdn.example.com/v1.png");
    insertThumbnail(completedHouse.getId(), 2, "https://cdn.example.com/v2.png");
    entityManager.flush();
    entityManager.clear();

    List<Long> ids = List.of(completedHouse.getId(), inProgressTree.getId());

    assertThat(
            drawingSessionEmotionRepository
                .findByDrawingSessionIdInOrderByDrawingSessionIdAscSelectionOrderAscIdAsc(ids)
                .stream()
                .filter(e -> e.getDrawingSession().getId().equals(completedHouse.getId()))
                .map(DrawingSessionEmotion::getEmotionCode)
                .toList())
        .containsExactly(DrawingEmotionCode.HAPPY, DrawingEmotionCode.CALM);

    var analyses =
        drawingAnalysisRepository
            .findByDrawingSessionIdInOrderByDrawingSessionIdAscRequestedAtDescIdDesc(ids);
    assertThat(analyses.getFirst().getId()).isEqualTo(newerAnalysis.getId());
    assertThat(analyses.getFirst().getState()).isEqualTo(DrawingAnalysisState.PROCESSING);

    var thumbnails =
        drawingAssetRepository
            .findByDrawingSessionIdInAndAssetTypeOrderByDrawingSessionIdAscAssetVersionDescIdDesc(
                ids, DrawingAssetType.THUMBNAIL);
    assertThat(thumbnails.getFirst().getAssetVersion()).isEqualTo(2);
    assertThat(thumbnails.getFirst().getFileUrl()).isEqualTo("https://cdn.example.com/v2.png");
  }

  private DrawingSession saveSession(
      Child child, DrawingType type, LocalDateTime startedAt, String key) {
    return drawingSessionRepository.save(
        DrawingSession.start(child, type, DrawingInputMethod.CANVAS, startedAt, key));
  }

  private DrawingAsset saveDraft(DrawingSession session, int version, LocalDateTime createdAt) {
    return drawingAssetRepository.save(
        DrawingAsset.draft(
            session,
            version,
            "drafts/" + session.getId() + "/" + version + ".png",
            "image/png",
            1024,
            String.valueOf(version % 10).repeat(64),
            version,
            createdAt,
            createdAt));
  }

  private void setStatus(Long sessionId, String status, LocalDateTime completedAt) {
    entityManager
        .createNativeQuery(
            "update drawing_sessions set session_status = ?, completed_at = ? where id = ?")
        .setParameter(1, status)
        .setParameter(2, completedAt)
        .setParameter(3, sessionId)
        .executeUpdate();
  }

  private void softDelete(Long sessionId, LocalDateTime deletedAt) {
    entityManager
        .createNativeQuery("update drawing_sessions set deleted_at = ? where id = ?")
        .setParameter(1, deletedAt)
        .setParameter(2, sessionId)
        .executeUpdate();
  }

  private void insertThumbnail(Long sessionId, int version, String fileUrl) {
    entityManager
        .createNativeQuery(
            "insert into drawing_assets "
                + "(drawing_session_id, asset_type, asset_version, storage_key, file_url, "
                + "mime_type, file_size_bytes, checksum_sha256, captured_at, created_at) "
                + "values (?, 'THUMBNAIL', ?, ?, ?, 'image/png', 100, ?, ?, ?)")
        .setParameter(1, sessionId)
        .setParameter(2, version)
        .setParameter(3, "thumbs/" + sessionId + "/" + version + ".png")
        .setParameter(4, fileUrl)
        .setParameter(5, String.valueOf(version).repeat(64))
        .setParameter(6, LocalDateTime.of(2026, 7, 1, 11, 0))
        .setParameter(7, LocalDateTime.of(2026, 7, 1, 11, 0))
        .executeUpdate();
  }
}
