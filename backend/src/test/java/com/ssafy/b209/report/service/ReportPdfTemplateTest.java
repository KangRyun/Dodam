package com.ssafy.b209.report.service;

import static org.assertj.core.api.Assertions.assertThat;

import com.ssafy.b209.report.dto.ReportChildExpressionResponse;
import com.ssafy.b209.report.dto.ReportDetailResponse;
import com.ssafy.b209.report.dto.ReportDrawingResponse;
import com.ssafy.b209.report.dto.ReportDrawingSessionResponse;
import com.ssafy.b209.report.dto.ReportExpertReviewResponse;
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
