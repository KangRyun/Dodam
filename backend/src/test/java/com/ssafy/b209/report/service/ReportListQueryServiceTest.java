package com.ssafy.b209.report.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;

import com.ssafy.b209.auth.authorization.GuardianResourceAccessValidator;
import com.ssafy.b209.auth.service.CurrentAuthenticatedUserResolver;
import com.ssafy.b209.drawing.domain.DrawingAsset;
import com.ssafy.b209.drawing.domain.DrawingAssetType;
import com.ssafy.b209.drawing.domain.DrawingEmotionCode;
import com.ssafy.b209.drawing.domain.DrawingSession;
import com.ssafy.b209.drawing.domain.DrawingSessionEmotion;
import com.ssafy.b209.drawing.domain.DrawingType;
import com.ssafy.b209.drawing.repository.DrawingAssetRepository;
import com.ssafy.b209.drawing.repository.DrawingSessionEmotionRepository;
import com.ssafy.b209.drawing.service.DrawingAssetFileUrlFactory;
import com.ssafy.b209.report.domain.Report;
import com.ssafy.b209.report.domain.ReportStatus;
import com.ssafy.b209.report.dto.ReportListPageResponse;
import com.ssafy.b209.report.repository.ReportRepository;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.data.domain.PageImpl;
import org.springframework.data.domain.PageRequest;

@ExtendWith(MockitoExtension.class)
class ReportListQueryServiceTest {

  @Mock private ReportRepository reportRepository;
  @Mock private DrawingAssetRepository drawingAssetRepository;
  @Mock private DrawingSessionEmotionRepository drawingSessionEmotionRepository;
  @Mock private CurrentAuthenticatedUserResolver currentUserResolver;
  @Mock private GuardianResourceAccessValidator accessValidator;

  private ReportListQueryService service;

  @BeforeEach
  void setUp() {
    service =
        new ReportListQueryService(
            reportRepository,
            drawingAssetRepository,
            drawingSessionEmotionRepository,
            new DrawingAssetFileUrlFactory(),
            currentUserResolver,
            accessValidator);
  }

  @Test
  void mapsReportPageWithAuthenticatedThumbnailAndSelectedEmotions() {
    PageRequest pageable = PageRequest.of(0, 20);
    DrawingType drawingType = mock(DrawingType.class);
    given(drawingType.getId()).willReturn(7L);
    given(drawingType.getCode()).willReturn("ART_DIARY");
    given(drawingType.getName()).willReturn("그림 일기");

    DrawingSession session = mock(DrawingSession.class);
    given(session.getId()).willReturn(10L);
    given(session.getDrawingType()).willReturn(drawingType);
    given(session.getTitle()).willReturn("오늘의 그림");
    given(session.getStartedAt()).willReturn(LocalDateTime.parse("2026-07-22T04:00:00"));
    given(session.getCompletedAt()).willReturn(LocalDateTime.parse("2026-07-22T04:05:00"));

    Report report = mock(Report.class);
    given(report.getId()).willReturn(50L);
    given(report.getReportVersion()).willReturn(2);
    given(report.getDrawingSession()).willReturn(session);
    given(report.getStatus()).willReturn(ReportStatus.COMPLETED);

    DrawingAsset thumbnail = mock(DrawingAsset.class);
    given(thumbnail.getId()).willReturn(30L);
    given(thumbnail.getDrawingSession()).willReturn(session);

    DrawingSessionEmotion emotion = mock(DrawingSessionEmotion.class);
    given(emotion.getDrawingSession()).willReturn(session);
    given(emotion.getEmotionCode()).willReturn(DrawingEmotionCode.HAPPY);

    given(currentUserResolver.requireUserId()).willReturn(99L);
    given(
            reportRepository.findVisiblePage(
                3L,
                LocalDateTime.parse("2026-07-01T00:00:00"),
                LocalDateTime.parse("2026-08-01T00:00:00"),
                "ART_DIARY",
                ReportStatus.COMPLETED,
                pageable))
        .willReturn(new PageImpl<>(List.of(report), pageable, 1));
    given(
            drawingAssetRepository
                .findByDrawingSessionIdInAndAssetTypeOrderByDrawingSessionIdAscAssetVersionDescIdDesc(
                    List.of(10L), DrawingAssetType.THUMBNAIL))
        .willReturn(List.of(thumbnail));
    given(
            drawingSessionEmotionRepository
                .findByDrawingSessionIdInOrderByDrawingSessionIdAscSelectionOrderAscIdAsc(
                    List.of(10L)))
        .willReturn(List.of(emotion));

    ReportListPageResponse response =
        service.getReports(
            3L,
            LocalDate.of(2026, 7, 1),
            LocalDate.of(2026, 7, 31),
            "ART_DIARY",
            ReportStatus.COMPLETED,
            pageable);

    verify(accessValidator).requireChildAccess(99L, 3L);
    assertThat(response.totalElements()).isEqualTo(1);
    assertThat(response.content())
        .singleElement()
        .satisfies(
            item -> {
              assertThat(item.reportId()).isEqualTo(50L);
              assertThat(item.reportVersion()).isEqualTo(2);
              assertThat(item.drawingType().code()).isEqualTo("ART_DIARY");
              assertThat(item.thumbnailUrl()).isEqualTo("/api/v1/drawing-assets/30/file");
              assertThat(item.activityDate()).isEqualTo(LocalDate.of(2026, 7, 22));
              assertThat(item.durationMs()).isEqualTo(300000L);
              assertThat(item.selectedEmotions()).containsExactly("HAPPY");
              assertThat(item.expertReviewAvailable()).isFalse();
            });
  }

  @Test
  void returnsEmptyPageWithoutAssetOrEmotionQueries() {
    PageRequest pageable = PageRequest.of(0, 20);
    given(currentUserResolver.requireUserId()).willReturn(99L);
    given(reportRepository.findVisiblePage(3L, null, null, null, null, pageable))
        .willReturn(new PageImpl<>(List.of(), pageable, 0));

    ReportListPageResponse response = service.getReports(3L, null, null, null, null, pageable);

    assertThat(response.content()).isEmpty();
    assertThat(response.totalElements()).isZero();
  }
}
