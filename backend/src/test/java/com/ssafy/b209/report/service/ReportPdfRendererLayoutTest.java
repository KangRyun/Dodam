package com.ssafy.b209.report.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;

import com.ssafy.b209.report.dto.ReportActivityFactsResponse;
import com.ssafy.b209.report.dto.ReportChildExpressionResponse;
import com.ssafy.b209.report.dto.ReportConversationSummaryResponse;
import com.ssafy.b209.report.dto.ReportDetailResponse;
import com.ssafy.b209.report.dto.ReportDrawingSessionResponse;
import com.ssafy.b209.report.dto.ReportEvidenceItemResponse;
import com.ssafy.b209.report.dto.ReportExpertReviewResponse;
import com.ssafy.b209.report.dto.ReportObservedFeatureResponse;
import com.ssafy.b209.report.dto.ReportParentGuideResponse;
import com.ssafy.b209.report.dto.ReportPublicInterpretationResponse;
import com.ssafy.b209.report.dto.ReportQaPairResponse;
import com.ssafy.b209.report.dto.ReportReferenceResponse;
import com.ssafy.b209.report.dto.ReportSubjectResponse;
import com.ssafy.b209.report.dto.ReportUtteranceResponse;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;
import org.apache.pdfbox.Loader;
import org.apache.pdfbox.pdmodel.PDDocument;
import org.apache.pdfbox.text.PDFTextStripper;
import org.junit.jupiter.api.Test;

/**
 * 화면과 같은 서식으로 렌더링하는지 고정한다(S15P11B209-957).
 *
 * <p>이전 렌더러는 모든 내용을 한 가지 크기의 줄글로 찍어 화면의 섹션 구분이 사라졌다. 여기서는 섹션 제목과 화면 라벨이 실제로 실리는지, 긴 리포트가 여러 장으로
 * 나뉘는지, 폰트가 못 그리는 글자 때문에 내보내기 전체가 실패하지 않는지를 본다.
 */
class ReportPdfRendererLayoutTest {

  private final ReportPdfRenderer renderer = new ReportPdfRenderer();

  @Test
  void writesScreenSectionTitlesAndLabels() throws Exception {
    byte[] pdf = renderer.render(fullReport());

    try (PDDocument document = Loader.loadPDF(pdf)) {
      String text = new PDFTextStripper().getText(document);
      assertThat(text)
          .contains("도담 관찰 리포트")
          .contains("활동 정보")
          .contains("주요 심리 경향")
          .contains("아이의 표현")
          .contains("이런 모습이 보였어요")
          .contains("활동 기록")
          .contains("대화 요약")
          .contains("보호자 대화 안내")
          .contains("주의 사항")
          .contains("참고 자료")
          // 화면과 같은 라벨·표현을 쓴다.
          .contains("그린 시간")
          .contains("9분")
          .contains("멈춤 횟수")
          .contains("2회")
          // HTP 주제는 코드가 아니라 이름으로 낸다.
          .contains("나무")
          // 가이드 유형도 화면 문구로 낸다.
          .contains("그림으로 대화하기");
      // 표지 다음에 비진단 고지가 온다(875 §11).
      assertThat(text.indexOf("진단이 아닌 관찰 참고 자료"))
          .isGreaterThan(text.indexOf("도담 관찰 리포트"))
          .isLessThan(text.indexOf("주요 심리 경향"));
    }
  }

  @Test
  void paginatesLongReportsAndNumbersEveryPage() throws Exception {
    byte[] pdf = renderer.render(longReport());

    try (PDDocument document = Loader.loadPDF(pdf)) {
      assertThat(document.getNumberOfPages()).isGreaterThan(1);
      String text = new PDFTextStripper().getText(document);
      assertThat(text).contains("1 / " + document.getNumberOfPages());
      // 한 장에 못 들어간 카드는 다음 장에 이어 붙는다.
      assertThat(text).contains("(이어서)");
    }
  }

  @Test
  void keepsRenderingWhenTextHasGlyphsTheFontCannotDraw() throws Exception {
    // 아이 발화나 AI 문장에 이모지가 섞여도 내보내기 전체가 실패하면 안 된다.
    ReportDetailResponse report =
        reportWith(
            new ReportChildExpressionResponse(
                List.of("HAPPY"),
                "오늘 진짜 재밌었어 🎉🎨",
                List.of(new ReportUtteranceResponse(30L, "이거 봐 😀 내 그림이야", "STT", false))));

    byte[] pdf = renderer.render(report);

    try (PDDocument document = Loader.loadPDF(pdf)) {
      String text = new PDFTextStripper().getText(document);
      assertThat(text).contains("오늘 진짜 재밌었어").contains("내 그림이야");
    }
  }

  @Test
  void rendersReportWithoutOptionalSections() {
    assertThatCode(
            () ->
                renderer.render(
                    new ReportDetailResponse(
                        70L,
                        1,
                        "COMPLETED",
                        null,
                        null,
                        null,
                        List.of(),
                        null,
                        null,
                        List.of(),
                        List.of(),
                        ReportExpertReviewResponse.notRequested(),
                        LocalDateTime.of(2026, 8, 5, 12, 0))))
        .doesNotThrowAnyException();
  }

  private ReportDetailResponse fullReport() {
    return new ReportDetailResponse(
        134L,
        1,
        "COMPLETED",
        session(),
        null,
        new ReportChildExpressionResponse(
            List.of("SAD", "CALM"),
            "동생이랑 놀아서 좋았어요",
            List.of(new ReportUtteranceResponse(30L, "우리 동생이야", "STT", false))),
        List.of(new ReportObservedFeatureResponse("친구를 함께 그렸어요", "사람 둘을 나란히 그렸어요.", "그림에서 확인했어요.")),
        facts(List.of("사람", "집")),
        new ReportConversationSummaryResponse(4, 4, 0, "편안하게 대화했어요."),
        List.of("어떤 부분이 좋아?"),
        List.of("이 리포트는 진단 자료가 아닙니다."),
        ReportExpertReviewResponse.notRequested(),
        LocalDateTime.of(2026, 8, 5, 12, 28),
        "이 리포트는 진단이 아닌 관찰 참고 자료입니다.",
        List.of(
            new ReportPublicInterpretationResponse(
                "RELATIONSHIP",
                "가족과의 연결",
                "가족에게 의지하려는 경향이 보일 수 있습니다.",
                "이 관찰은 이번 활동 한 번에 한정됩니다.",
                "집에서 가족과 함께 있는 시간을 살펴봐 주세요.",
                List.of(1))),
        List.of(new ReportEvidenceItemResponse(1, "DRAWING", "집을 가운데 크게 그렸어요.")),
        List.of(
            new ReportSubjectResponse(
                "TREE",
                null,
                List.of("나무를 화면 왼쪽에 그렸어요."),
                List.of(
                    new ReportQaPairResponse(
                        "이 나무는 어떤 나무야?", "큰 나무야", "ANSWERED", "VOICE", false, true)),
                List.of(0))),
        List.of(
            new ReportParentGuideResponse("DRAWING_CONVERSATION", List.of("그림을 함께 보며 이야기해 보세요."))),
        null,
        List.of(new ReportReferenceResponse("아동 미술 관찰 안내", "https://example.test/guide")));
  }

  /** 카드 하나가 한 장을 넘도록 문장을 길게 채운 리포트다. */
  private ReportDetailResponse longReport() {
    List<String> guide = new ArrayList<>();
    for (int index = 0; index < 60; index++) {
      guide.add(
          "아이와 함께 그림을 보며 오늘 어떤 마음이었는지 천천히 물어봐 주세요. 대답을 재촉하지 않고 기다려 주면 아이가 더 편하게 이야기합니다. ("
              + index
              + ")");
    }
    ReportDetailResponse base = fullReport();
    return new ReportDetailResponse(
        base.reportId(),
        base.reportVersion(),
        base.reportStatus(),
        base.drawingSession(),
        base.drawing(),
        base.childExpression(),
        base.observedFeatures(),
        base.activityFacts(),
        base.conversationSummary(),
        guide,
        base.limitations(),
        base.expertReview(),
        base.createdAt(),
        base.nonDiagnosticNotice(),
        base.publicInterpretations(),
        base.evidenceItems(),
        base.subjectReports(),
        base.parentGuides(),
        base.crisisAlert(),
        base.references());
  }

  private ReportDetailResponse reportWith(ReportChildExpressionResponse expression) {
    ReportDetailResponse base = fullReport();
    return new ReportDetailResponse(
        base.reportId(),
        base.reportVersion(),
        base.reportStatus(),
        base.drawingSession(),
        base.drawing(),
        expression,
        base.observedFeatures(),
        base.activityFacts(),
        base.conversationSummary(),
        base.guardianConversationGuide(),
        base.limitations(),
        base.expertReview(),
        base.createdAt(),
        base.nonDiagnosticNotice(),
        base.publicInterpretations(),
        base.evidenceItems(),
        base.subjectReports(),
        base.parentGuides(),
        base.crisisAlert(),
        base.references());
  }

  private ReportDrawingSessionResponse session() {
    return new ReportDrawingSessionResponse(
        100L,
        1L,
        "ART_DIARY",
        "그림일기",
        "우리 가족",
        "CANVAS",
        LocalDateTime.of(2026, 8, 5, 12, 28),
        LocalDateTime.of(2026, 8, 5, 12, 51),
        1_380_000L);
  }

  private ReportActivityFactsResponse facts(List<String> objects) {
    // 875 확장 이전 형태 생성자다. 초 단위 값은 밀리초에서 유도된다(560초 = 9분).
    return new ReportActivityFactsResponse(objects, 560_000L, 2, 1, false, List.of("필압 정보 없음"));
  }
}
