package com.ssafy.b209.report.controller;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import com.ssafy.b209.conversation.service.GuardianUserResolver;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.global.response.ApiResponse;
import com.ssafy.b209.report.dto.ReportActivityFactsResponse;
import com.ssafy.b209.report.dto.ReportChildExpressionResponse;
import com.ssafy.b209.report.dto.ReportConversationSummaryResponse;
import com.ssafy.b209.report.dto.ReportDetailResponse;
import com.ssafy.b209.report.dto.ReportDrawingResponse;
import com.ssafy.b209.report.dto.ReportDrawingSessionResponse;
import com.ssafy.b209.report.dto.ReportExpertReviewResponse;
import com.ssafy.b209.report.exception.ReportDetailErrorCode;
import com.ssafy.b209.report.service.ReportDetailQueryService;
import java.time.LocalDateTime;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;

/** 리포트 상세 조회 Controller가 보호자를 식별하고 서비스에 위임해 공통 응답을 반환하는지 확인한다. */
@ExtendWith(MockitoExtension.class)
class ReportDetailControllerTest {
  @Mock private GuardianUserResolver guardianResolver;
  @Mock private ReportDetailQueryService reportDetailQueryService;

  private ReportDetailController controller;

  @BeforeEach
  void setUp() {
    controller = new ReportDetailController(guardianResolver, reportDetailQueryService);
  }

  @Test
  void delegatesResolvedGuardianAndReturnsOk() {
    ReportDetailResponse detail = sampleDetail();
    when(guardianResolver.resolve(null, "10")).thenReturn(10L);
    when(reportDetailQueryService.getReport(10L, 500L)).thenReturn(detail);

    ResponseEntity<ApiResponse<ReportDetailResponse>> response =
        controller.getReport(500L, null, "10");

    assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
    assertThat(response.getBody()).isNotNull();
    assertThat(response.getBody().data()).isSameAs(detail);
  }

  @Test
  void propagatesAccessDeniedFromService() {
    when(guardianResolver.resolve(null, "10")).thenReturn(10L);
    when(reportDetailQueryService.getReport(10L, 500L))
        .thenThrow(new BusinessException(ReportDetailErrorCode.REPORT_ACCESS_DENIED));

    assertThatThrownBy(() -> controller.getReport(500L, null, "10"))
        .isInstanceOf(BusinessException.class)
        .extracting("errorCode")
        .isEqualTo(ReportDetailErrorCode.REPORT_ACCESS_DENIED);
  }

  @Test
  void doesNotQueryWhenGuardianResolutionFails() {
    when(guardianResolver.resolve(null, null))
        .thenThrow(new BusinessException(ReportDetailErrorCode.REPORT_ACCESS_DENIED));

    assertThatThrownBy(() -> controller.getReport(500L, null, null))
        .isInstanceOf(BusinessException.class);

    verifyNoInteractions(reportDetailQueryService);
  }

  private ReportDetailResponse sampleDetail() {
    return new ReportDetailResponse(
        500L,
        1,
        "COMPLETED",
        new ReportDrawingSessionResponse(
            100L,
            1L,
            "HOUSE_TREE_PERSON",
            "집-나무-사람",
            "우리 가족",
            "CANVAS",
            LocalDateTime.parse("2026-07-21T02:00:00"),
            LocalDateTime.parse("2026-07-21T02:05:00"),
            300000L),
        new ReportDrawingResponse("https://cdn.example/final.png", "https://cdn.example/thumb.png"),
        new ReportChildExpressionResponse(List.of("HAPPY"), "행복한 하루였어요", List.of()),
        new ReportActivityFactsResponse(List.of("집"), 295000L, 4, 2, true, List.of("멈춤 4회 관찰")),
        new ReportConversationSummaryResponse(5, 4, 1, "아이가 편안하게 대화했습니다"),
        List.of("오늘 그림에 대해 함께 이야기해 보세요"),
        List.of("이 리포트는 진단이 아닙니다"),
        ReportExpertReviewResponse.notRequested(),
        LocalDateTime.parse("2026-07-21T02:06:00"));
  }
}
