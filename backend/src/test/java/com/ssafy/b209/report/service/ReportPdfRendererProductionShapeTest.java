package com.ssafy.b209.report.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.report.dto.ReportActivityFactsResponse;
import com.ssafy.b209.report.dto.ReportChildExpressionResponse;
import com.ssafy.b209.report.dto.ReportConversationSummaryResponse;
import com.ssafy.b209.report.dto.ReportDetailResponse;
import com.ssafy.b209.report.dto.ReportDrawingResponse;
import com.ssafy.b209.report.dto.ReportDrawingSessionResponse;
import com.ssafy.b209.report.dto.ReportExpertReviewResponse;
import com.ssafy.b209.report.dto.ReportUtteranceResponse;
import java.time.LocalDateTime;
import java.util.List;
import org.apache.pdfbox.Loader;
import org.apache.pdfbox.pdmodel.PDDocument;
import org.apache.pdfbox.text.PDFTextStripper;
import org.junit.jupiter.api.Test;

/**
 * 배포 서버에서 PDF 다운로드가 실패한 실제 응답 모양으로 렌더링을 고정한다(S15P11B209-860).
 *
 * <p>기존 {@link ReportPdfRendererTest}는 모든 필드가 채워진 이상적인 리포트만 검증했다. 실제로 500이 난 report 54는 그렇지 않았다 —
 * {@code title}·{@code expressedEmotionText}·{@code drawingDurationMs}·{@code pauseCount}·{@code
 * eraseCount}가 모두 {@code null}이고 {@code guardianConversationGuide}는 빈 목록이었다. 여기서는 그 모양을 그대로 재현한다.
 *
 * <p>렌더러가 던지는 예외 종류도 함께 고정한다. 다운로드가 {@code COMMON_500_001}(미분류 서버 오류)로 응답된 것이 이 이슈의 출발점이었고, 그 코드로는
 * 무엇이 실패했는지 알 수 없었다.
 */
class ReportPdfRendererProductionShapeTest {

  private final ReportPdfRenderer renderer = new ReportPdfRenderer();

  @Test
  void rendersReportWithNullOptionalFieldsAndEmptyGuide() throws Exception {
    byte[] pdf = renderer.render(productionShapedReport());

    assertThat(pdf).startsWith("%PDF".getBytes());
    try (PDDocument document = Loader.loadPDF(pdf)) {
      String text = new PDFTextStripper().getText(document);
      assertThat(text).contains("도담 관찰 리포트").contains("그림 일기").contains("이거 달 아니고 피자인데");
    }
  }

  @Test
  void rendersReportWithoutAnyOptionalSection() {
    ReportDetailResponse bareReport =
        new ReportDetailResponse(
            54L,
            1,
            "COMPLETED",
            null,
            null,
            null,
            null,
            null,
            null,
            List.of(),
            List.of(),
            ReportExpertReviewResponse.notRequested(),
            LocalDateTime.of(2026, 8, 3, 7, 53, 39));

    assertThatCode(() -> renderer.render(bareReport)).doesNotThrowAnyException();
  }

  @Test
  void classifiesUnexpectedFailureAsReportExportFailedInsteadOfLeakingIt() {
    // 렌더링 도중 나는 예상 밖 예외(여기서는 입력이 null 이라 발생하는 NPE)가 전역 핸들러까지
    // 올라가면 COMMON_500_001 로 뭉개진다. 그것이 이 이슈의 출발점이었으므로 분류를 고정한다.
    assertThatThrownBy(() -> renderer.render(null))
        .isInstanceOf(BusinessException.class)
        .extracting(exception -> ((BusinessException) exception).getErrorCode().getCode())
        .isEqualTo("REPORT_EXPORT_500_001");
  }

  /** report 54(그림 일기, childId 146)의 실제 응답 모양. 널 필드와 빈 목록을 그대로 둔다. */
  private ReportDetailResponse productionShapedReport() {
    return new ReportDetailResponse(
        54L,
        1,
        "COMPLETED",
        new ReportDrawingSessionResponse(
            3327L,
            146L,
            "ART_DIARY",
            "그림 일기",
            null,
            "CANVAS",
            LocalDateTime.of(2026, 8, 3, 7, 51, 49, 416_598_000),
            LocalDateTime.of(2026, 8, 3, 7, 53, 45, 333_467_000),
            115_916L),
        new ReportDrawingResponse(
            "/api/v1/drawing-assets/3448/file", "/api/v1/drawing-assets/3448/file"),
        new ReportChildExpressionResponse(
            List.of("ANGRY"),
            null,
            List.of(
                new ReportUtteranceResponse(698L, "이거 달 아니고 피자인데", "STT", false),
                new ReportUtteranceResponse(700L, "아 피자는 빨간색이니까 빨간색으로 그렸어", "STT", false))),
        // 운영 report 54 는 검토를 통과한 관찰 특징이 없어 빈 목록이다.
        List.of(),
        new ReportActivityFactsResponse(
            List.of("달", "달", "달", "정원", "잔디"),
            null,
            null,
            null,
            false,
            List.of("아이의 그림 활동은 약 10분간 진행되었습니다.")),
        new ReportConversationSummaryResponse(3, 2, 0, "아이와의 대화에서 피자에 대한 흥미로운 이야기가 있었습니다."),
        List.of(),
        List.of("본 리포트는 선택된 표현 데이터를 바탕으로 한 관찰 기록이며, 아동의 발달 상태를 단정하지 않습니다."),
        ReportExpertReviewResponse.notRequested(),
        LocalDateTime.of(2026, 8, 3, 7, 53, 39, 646_437_000));
  }
}
