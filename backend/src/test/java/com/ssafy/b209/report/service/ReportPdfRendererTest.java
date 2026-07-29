package com.ssafy.b209.report.service;

import static org.assertj.core.api.Assertions.assertThat;

import com.ssafy.b209.report.dto.ReportActivityFactsResponse;
import com.ssafy.b209.report.dto.ReportChildExpressionResponse;
import com.ssafy.b209.report.dto.ReportConversationSummaryResponse;
import com.ssafy.b209.report.dto.ReportDetailResponse;
import com.ssafy.b209.report.dto.ReportDrawingSessionResponse;
import com.ssafy.b209.report.dto.ReportExpertReviewResponse;
import com.ssafy.b209.report.dto.ReportUtteranceResponse;
import java.time.LocalDateTime;
import java.util.List;
import org.apache.pdfbox.Loader;
import org.apache.pdfbox.pdmodel.PDDocument;
import org.apache.pdfbox.text.PDFTextStripper;
import org.junit.jupiter.api.Test;

class ReportPdfRendererTest {

  private final ReportPdfRenderer renderer = new ReportPdfRenderer();

  @Test
  void embedsReadableKoreanReportContent() throws Exception {
    byte[] pdf = renderer.render(report());

    assertThat(pdf).startsWith("%PDF".getBytes());
    try (PDDocument document = Loader.loadPDF(pdf)) {
      String text = new PDFTextStripper().getText(document);
      assertThat(text)
          .contains("도담 관찰 리포트")
          .contains("그림 일기")
          .contains("친구와 함께 있어서 행복했어")
          .contains("진단 자료가 아닙니다");
    }
  }

  private ReportDetailResponse report() {
    return new ReportDetailResponse(
        500L,
        1,
        "COMPLETED",
        new ReportDrawingSessionResponse(
            100L,
            1L,
            "ART_DIARY",
            "그림 일기",
            "친구와 놀았던 날",
            "CANVAS",
            LocalDateTime.of(2026, 7, 29, 8, 30),
            LocalDateTime.of(2026, 7, 29, 8, 40),
            600_000L),
        null,
        new ReportChildExpressionResponse(
            List.of("HAPPY"),
            "즐거웠어",
            List.of(new ReportUtteranceResponse(30L, "친구와 함께 있어서 행복했어", "STT", false))),
        new ReportActivityFactsResponse(
            List.of("사람", "나무"), 580_000L, 2, 1, false, List.of("필압 정보 없음")),
        new ReportConversationSummaryResponse(4, 4, 0, "아이는 친구와의 놀이를 이야기했습니다."),
        List.of("오늘 즐거웠던 일을 다시 물어보세요."),
        List.of("이 리포트는 진단 자료가 아닙니다."),
        ReportExpertReviewResponse.notRequested(),
        LocalDateTime.of(2026, 7, 29, 8, 41));
  }
}
