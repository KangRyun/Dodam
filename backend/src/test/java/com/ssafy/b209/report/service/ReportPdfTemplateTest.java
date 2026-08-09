package com.ssafy.b209.report.service;

import static org.assertj.core.api.Assertions.assertThat;

import com.ssafy.b209.report.dto.ReportChildExpressionResponse;
import com.ssafy.b209.report.dto.ReportDetailResponse;
import com.ssafy.b209.report.dto.ReportDiaryInsightsResponse;
import com.ssafy.b209.report.dto.ReportDrawingResponse;
import com.ssafy.b209.report.dto.ReportDrawingSessionResponse;
import com.ssafy.b209.report.dto.ReportExpertReviewResponse;
import com.ssafy.b209.report.dto.ReportQaPairResponse;
import com.ssafy.b209.report.dto.ReportSubjectResponse;
import com.ssafy.b209.report.dto.ReportUtteranceResponse;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;

/**
 * 템플릿이 만드는 문서 구조를 직접 고정한다.
 *
 * <p>PDF 로 구운 뒤 글자만 뽑아 보면 "그림이 두 번 실렸다"나 "빈 인용이 한 줄 있다" 같은 것을 알 수 없다. 렌더링 전 XHTML 에서 확인한다.
 *
 * <p>여기 걸린 두 가지는 운영 리포트 145 에서 실제로 나온 흠이다.
 */
class ReportPdfTemplateTest {

  private static final String DRAWING_URL = "/api/v1/drawing-assets/3600/file";

  @Test
  void doesNotRepeatTheCoverDrawingInsideTheSubjectCard() {
    // 그림일기는 완성본 한 장이 주제 그림과 같은 파일이다. 표지에 크게 싣고 주제 카드에서 또
    //   실으면 같은 그림이 두 번 나온다 — 리포트 145 가 그런 모양이었다.
    String html = template(reportWithSameDrawingOnCoverAndSubject()).build();

    assertThat(countOf(html, "class=\"drawing\"")).isEqualTo(1);
  }

  @Test
  void keepsSubjectDrawingWhenItDiffersFromTheCoverDrawing() {
    String html = template(reportWithDifferentSubjectDrawing()).build();

    // 표지 대표 그림 + 주제 그림 두 장이다.
    assertThat(countOf(html, "class=\"drawing\"")).isEqualTo(2);
  }

  @Test
  void doesNotQuoteAnEmptyRepresentativeUtterance() {
    // 말이 비어 있는 대표 발화를 "-" 로 찍으면 아이가 그렇게 말한 것처럼 보인다.
    String html = template(reportWithUtterances(blank(), spoken("우리 동생이야"))).build();

    assertThat(countOf(html, "class=\"quote\"")).isEqualTo(1);
    assertThat(html).contains("우리 동생이야");
  }

  @Test
  void escapesTextThatWouldBreakTheDocument() {
    // 아이 발화에 <, & 가 섞이면 XHTML 파싱이 깨져 리포트 전체가 만들어지지 않는다.
    String html = template(reportWithUtterances(spoken("나 & 동생 <같이> 놀았어"))).build();

    assertThat(html).contains("나 &amp; 동생 &lt;같이&gt; 놀았어").doesNotContain("<같이>");
  }

  @Test
  void dropsRowsWithoutValueInsteadOfPrintingDash() {
    // "-" 만 있는 줄은 내용이 있는 것처럼 자리를 차지하고, 보호자는 무엇이 빠졌는지도 모른다.
    String html = template(base(null, null, List.of())).build();

    // 활동 이름(title)이 없는 표본이다. 라벨 자체가 나오지 않아야 한다.
    assertThat(html).doesNotContain("활동 이름").contains("활동 유형");
  }

  @Test
  void usesFriendlyWordingForTheInputMethodCode() {
    // CANVAS·UPLOAD 는 서버 코드다. 문서에 코드가 찍히면 보호자는 뜻을 알 수 없다.
    String html = template(base(null, null, List.of())).build();

    assertThat(html).contains("앱에서 그리기").doesNotContain("CANVAS");
  }

  @Test
  void doesNotShowTheInternalReportStatus() {
    // 생성 상태는 화면에 없고 완료된 리포트만 내보낼 수 있어 언제나 같은 값이다.
    String html = template(base(null, null, List.of())).build();

    assertThat(html).doesNotContain("생성 상태").doesNotContain("COMPLETED");
  }

  @Test
  void groupsRepeatedSkippedQuestionsIntoOneLine() {
    // 대화가 안 풀린 활동에서는 같은 질문이 반복되고 모두 건너뛴 채 남는다.
    String html = template(reportWithRepeatedSkippedQuestion()).build();

    assertThat(countOf(html, "오늘 뭐 그렸어?")).isEqualTo(1);
    assertThat(html).contains("이 질문은 건너뛰었어요 (3번)");
  }

  @Test
  void numbersGuardianStepsSoTheyReadAsThingsToDo() {
    // 점 목록은 읽을거리로, 번호 목록은 해 볼 순서로 읽힌다.
    String html = template(reportWithGuide()).build();

    assertThat(html).contains("<ol class=\"steps\">").contains("card card-guide");
  }

  @Test
  void marksSectionsWithShapeSoStructureSurvivesGrayscalePrinting() {
    // 흑백으로 인쇄하면 연한 배경이 모두 비슷한 회색이 된다. 모양이 다른 표식이 함께 있어야 한다.
    String html = template(reportWithGuide()).build();

    assertThat(html).contains("sec-drawing").contains("mark-circle");
    assertThat(html).contains("sec-guide").contains("mark-pill");
    assertThat(html).contains("sec-info").contains("mark-square");
  }

  @Test
  void v3PdfContainsEvidenceScopeAndTranscriptWithoutAudioUrl() {
    String html = template(v3Report()).build();

    assertThat(html)
        .contains("이번 기록의 자료 범위")
        .contains("그림에서 확인된 표현")
        .contains("이야기 구성 지도")
        .contains("전체 대화")
        .contains("앱에서 음성 재생 가능")
        .doesNotContain("/api/v1/conversation-messages/22/audio");
  }

  // ── 도구 ────────────────────────────────────────────────────────────

  /** 그림 URL 두 개를 모두 읽어 둔 상태로 템플릿을 만든다. */
  private ReportPdfTemplate template(ReportDetailResponse report) {
    ReportImageAsset asset = new ReportImageAsset(new byte[] {1, 2, 3}, "image/png", 800, 600);
    return new ReportPdfTemplate(
        report, Map.of(DRAWING_URL, asset, "/api/v1/drawing-assets/3601/file", asset));
  }

  private int countOf(String text, String needle) {
    int count = 0;
    for (int at = text.indexOf(needle); at >= 0; at = text.indexOf(needle, at + needle.length())) {
      count++;
    }
    return count;
  }

  private ReportUtteranceResponse blank() {
    return new ReportUtteranceResponse(null, null, "STT", false);
  }

  private ReportUtteranceResponse spoken(String text) {
    return new ReportUtteranceResponse(30L, text, "STT", false);
  }

  // ── 리포트 표본 ──────────────────────────────────────────────────────

  private ReportDetailResponse reportWithSameDrawingOnCoverAndSubject() {
    return base(DRAWING_URL, DRAWING_URL, List.of());
  }

  private ReportDetailResponse reportWithDifferentSubjectDrawing() {
    return base(DRAWING_URL, "/api/v1/drawing-assets/3601/file", List.of());
  }

  private ReportDetailResponse reportWithUtterances(ReportUtteranceResponse... utterances) {
    return base(null, null, List.of(utterances));
  }

  /** 같은 질문이 세 번 반복되고 모두 건너뛴 리포트다. */
  private ReportDetailResponse reportWithRepeatedSkippedQuestion() {
    ReportQaPairResponse skipped =
        new ReportQaPairResponse("오늘 뭐 그렸어?", null, "SKIPPED", "TEXT", false, false);
    return withSubjectAndGuide(
        new ReportSubjectResponse(
            "DRAWING", null, List.of(), List.of(skipped, skipped, skipped), List.of()),
        List.of());
  }

  /** 보호자 안내가 있는 리포트다. */
  private ReportDetailResponse reportWithGuide() {
    return withSubjectAndGuide(
        new ReportSubjectResponse(
            "DRAWING", DRAWING_URL, List.of("잔디를 그렸어요."), List.of(), List.of()),
        List.of("오늘 그린 것 중 무엇을 먼저 이야기하고 싶은지 물어봐 주세요."));
  }

  private ReportDetailResponse v3Report() {
    ReportDetailResponse base = base(null, null, List.of());
    ReportDiaryInsightsResponse insights =
        new ReportDiaryInsightsResponse(
            null,
            List.of(),
            List.of(),
            List.of(),
            List.of(),
            null,
            List.of(),
            List.of(),
            null,
            3,
            new ReportDiaryInsightsResponse.DiaryDataScopeResponse(
                "RICH", "확정된 발화와 그림 관찰을 함께 사용했어요.", 1, 0, 0, 0, 1),
            List.of(
                new ReportDiaryInsightsResponse.DiaryStoryComponentResponse(
                    "EVENT", "CONFIRMED", "친구와 공원에서 놀았어요.", List.of())),
            List.of(
                new ReportDiaryInsightsResponse.DiaryDrawingObservationResponse(
                    "두 사람이 나란히 있어요.", "HIGH", true, List.of())),
            List.of(
                new ReportDiaryInsightsResponse.DiaryTranscriptEntryResponse(
                    11L,
                    22L,
                    "누구와 함께 있었어?",
                    "친구와 있었어요.",
                    "VOICE",
                    "SUCCESS",
                    4200,
                    true,
                    "/api/v1/conversation-messages/22/audio",
                    "OPEN_INVITATION",
                    LocalDateTime.of(2026, 8, 9, 10, 15))));
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
        base.references(),
        base.activityType(),
        base.childDisplayName(),
        base.aiRawReport(),
        insights,
        base.screeningSummary());
  }

  private ReportDetailResponse withSubjectAndGuide(
      ReportSubjectResponse subject, List<String> guide) {
    ReportDetailResponse base = base(null, null, List.of());
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
        List.of(subject),
        base.parentGuides(),
        base.crisisAlert(),
        base.references(),
        base.activityType(),
        base.childDisplayName());
  }

  private ReportDetailResponse base(
      String coverUrl, String subjectUrl, List<ReportUtteranceResponse> utterances) {
    return new ReportDetailResponse(
        145L,
        1,
        "COMPLETED",
        new ReportDrawingSessionResponse(
            3400L,
            146L,
            "ART_DIARY",
            "그림 일기",
            null,
            "CANVAS",
            LocalDateTime.of(2026, 8, 5, 23, 46),
            LocalDateTime.of(2026, 8, 5, 23, 47),
            60_000L),
        coverUrl == null ? null : new ReportDrawingResponse(coverUrl, coverUrl),
        new ReportChildExpressionResponse(List.of("HAPPY"), null, utterances),
        List.of(),
        null,
        null,
        List.of(),
        List.of(),
        ReportExpertReviewResponse.notRequested(),
        LocalDateTime.of(2026, 8, 5, 23, 47),
        ReportDetailResponse.NON_DIAGNOSTIC_NOTICE,
        List.of(),
        List.of(),
        subjectUrl == null
            ? List.of()
            : List.of(
                new ReportSubjectResponse(
                    "DRAWING", subjectUrl, List.of("잔디를 그렸어요."), List.of(), List.of())),
        List.of(),
        null,
        List.of(),
        "ART_DIARY",
        null);
  }
}
