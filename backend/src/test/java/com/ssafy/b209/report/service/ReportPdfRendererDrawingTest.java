package com.ssafy.b209.report.service;

import static org.assertj.core.api.Assertions.assertThat;

import com.ssafy.b209.drawing.service.DrawingAssetFileUrlFactory;
import com.ssafy.b209.report.dto.ReportChildExpressionResponse;
import com.ssafy.b209.report.dto.ReportDetailResponse;
import com.ssafy.b209.report.dto.ReportDrawingResponse;
import com.ssafy.b209.report.dto.ReportDrawingSessionResponse;
import com.ssafy.b209.report.dto.ReportExpertReviewResponse;
import com.ssafy.b209.report.dto.ReportQaPairResponse;
import com.ssafy.b209.report.dto.ReportSubjectResponse;
import java.awt.image.BufferedImage;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import javax.imageio.ImageIO;
import org.apache.pdfbox.Loader;
import org.apache.pdfbox.cos.COSName;
import org.apache.pdfbox.pdmodel.PDDocument;
import org.apache.pdfbox.pdmodel.PDResources;
import org.apache.pdfbox.text.PDFTextStripper;
import org.junit.jupiter.api.Test;

/**
 * 그림과 감정 아이콘이 실제로 문서에 실리는지, 페이지 분할이 의미 단위를 지키는지 고정한다(S15P11B209-968).
 *
 * <p>이전 렌더러는 그림을 아예 싣지 못했다 — 그림 URL 이 인증이 필요한 상대 경로였고 렌더러에 저장소 의존이 없었다(S15P11B209-957). 지금은 {@link
 * ReportAssetResolver} 로 저장소에서 직접 읽는다(966). <b>리포트에서 그림이 빠지면 보호자가 저장한 파일에 아이가 그린 것이 없다</b> — 그래서 삽입
 * 여부를 코드로 못박는다.
 */
class ReportPdfRendererDrawingTest {

  private static final long DRAWING_ASSET_ID = 3448L;
  private static final String DRAWING_URL = "/api/v1/drawing-assets/" + DRAWING_ASSET_ID + "/file";

  private final DrawingAssetFileUrlFactory fileUrlFactory = new DrawingAssetFileUrlFactory();

  @Test
  void embedsResolvedDrawingImage() throws Exception {
    byte[] pdf = renderer(asset(1200, 900)).render(reportWithDrawing());

    try (PDDocument document = Loader.loadPDF(pdf)) {
      assertThat(hasImageXObject(document)).isTrue();
    }
  }

  @Test
  void rendersWithoutDrawingWhenAssetCannotBeRead() throws Exception {
    // 그림 한 장 때문에 내보내기 전체가 실패하면 보호자는 아무것도 받지 못한다.
    byte[] pdf = renderer(null).render(reportWithDrawing());

    try (PDDocument document = Loader.loadPDF(pdf)) {
      assertThat(new PDFTextStripper().getText(document)).contains("도담 관찰 리포트");
      assertThat(hasImageXObject(document)).isFalse();
    }
  }

  @Test
  void readsEachDrawingOnceWhenTheSameUrlRepeats() {
    List<Long> requested = new ArrayList<>();
    ReportAssetResolver counting =
        assetId -> {
          requested.add(assetId);
          return Optional.of(asset(600, 400));
        };
    // 집·나무·사람이 같은 그림을 가리키는 응답도 있다. 같은 바이트를 여러 번 읽지 않는다.
    new ReportPdfRenderer(counting, fileUrlFactory).render(htpReportSharingOneDrawing());

    assertThat(requested).containsExactly(DRAWING_ASSET_ID);
  }

  @Test
  void doesNotReadImagesForUrlsThatAreNotDrawingAssetUrls() {
    List<Long> requested = new ArrayList<>();
    ReportAssetResolver counting =
        assetId -> {
          requested.add(assetId);
          return Optional.empty();
        };
    // 형식이 다른 URL 을 억지로 해석해 엉뚱한 그림을 싣는 것이 빈 자리보다 나쁘다.
    new ReportPdfRenderer(counting, fileUrlFactory)
        .render(reportWithDrawingUrl("https://cdn.example.test/other.png"));

    assertThat(requested).isEmpty();
  }

  @Test
  void embedsEmotionIconInsteadOfEmojiGlyph() throws Exception {
    // 문서 폰트에는 이모지 글리프가 없다. 감정은 PNG 아이콘으로 실려야 한다.
    byte[] pdf = renderer(null).render(reportWithEmotions(List.of("HAPPY", "CALM")));

    try (PDDocument document = Loader.loadPDF(pdf)) {
      assertThat(hasImageXObject(document)).isTrue();
      assertThat(new PDFTextStripper().getText(document)).contains("기쁨").contains("편안함");
    }
  }

  @Test
  void usesScreenLabelForEmotionWithoutIcon() throws Exception {
    // 아이콘이 없는 감정은 이름만 낸다. 앱에도 없는 그림을 서버에서 만들어 붙이지 않는다.
    byte[] pdf = renderer(null).render(reportWithEmotions(List.of("UNKNOWN")));

    try (PDDocument document = Loader.loadPDF(pdf)) {
      assertThat(new PDFTextStripper().getText(document)).contains("잘 모르겠음");
    }
  }

  @Test
  void keepsQuestionAndAnswerOnTheSamePage() throws Exception {
    // 문답이 장 경계에 걸리는 위치를 미리 알 수 없다. 앞 내용 길이를 조금씩 늘려 가며
    //   어느 위치에서도 질문과 답이 갈라지지 않는지 본다.
    for (int filler = 0; filler < 14; filler++) {
      byte[] pdf = renderer(null).render(reportWithFillerBeforeQa(filler));

      try (PDDocument document = Loader.loadPDF(pdf)) {
        int questionPage = pageContaining(document, "질문 마커");
        int answerPage = pageContaining(document, "답 마커");
        assertThat(questionPage).as("filler=%d 질문 위치", filler).isPositive();
        assertThat(answerPage).as("filler=%d 질문과 답이 같은 장", filler).isEqualTo(questionPage);
      }
    }
  }

  // ── 도구 ────────────────────────────────────────────────────────────

  /** 그림을 읽어 주는(또는 못 읽는) 렌더러다. */
  private ReportPdfRenderer renderer(ReportImageAsset asset) {
    return new ReportPdfRenderer(assetId -> Optional.ofNullable(asset), fileUrlFactory);
  }

  private ReportImageAsset asset(int width, int height) {
    return new ReportImageAsset(png(width, height), "image/png", width, height);
  }

  private byte[] png(int width, int height) {
    try {
      BufferedImage image = new BufferedImage(width, height, BufferedImage.TYPE_INT_RGB);
      ByteArrayOutputStream output = new ByteArrayOutputStream();
      ImageIO.write(image, "png", output);
      return output.toByteArray();
    } catch (IOException exception) {
      throw new IllegalStateException(exception);
    }
  }

  private boolean hasImageXObject(PDDocument document) throws IOException {
    for (int page = 0; page < document.getNumberOfPages(); page++) {
      PDResources resources = document.getPage(page).getResources();
      for (COSName name : resources.getXObjectNames()) {
        if (resources.isImageXObject(name)) return true;
      }
    }
    return false;
  }

  private int pageContaining(PDDocument document, String marker) throws IOException {
    for (int page = 1; page <= document.getNumberOfPages(); page++) {
      PDFTextStripper stripper = new PDFTextStripper();
      stripper.setStartPage(page);
      stripper.setEndPage(page);
      if (stripper.getText(document).contains(marker)) return page;
    }
    return -1;
  }

  // ── 리포트 표본 ──────────────────────────────────────────────────────

  private ReportDetailResponse reportWithDrawing() {
    return reportWithDrawingUrl(DRAWING_URL);
  }

  private ReportDetailResponse reportWithDrawingUrl(String fileUrl) {
    return base(new ReportDrawingResponse(fileUrl, fileUrl), null, List.of(), List.of(), null);
  }

  private ReportDetailResponse reportWithEmotions(List<String> emotions) {
    return base(
        null,
        new ReportChildExpressionResponse(emotions, null, List.of()),
        List.of(),
        List.of(),
        null);
  }

  /** 세 주제가 같은 그림 URL 을 가리키는 리포트다. */
  private ReportDetailResponse htpReportSharingOneDrawing() {
    List<ReportSubjectResponse> subjects =
        List.of(
            new ReportSubjectResponse(
                "HOUSE", DRAWING_URL, List.of("집을 그렸어요."), List.of(), List.of()),
            new ReportSubjectResponse(
                "TREE", DRAWING_URL, List.of("나무를 그렸어요."), List.of(), List.of()),
            new ReportSubjectResponse(
                "PERSON", DRAWING_URL, List.of("사람을 그렸어요."), List.of(), List.of()));
    return base(null, null, subjects, List.of(), "HTP");
  }

  /** 문답 앞에 안내 문장을 [filler]개 두어 문답이 놓이는 위치를 조금씩 밀어낸다. */
  private ReportDetailResponse reportWithFillerBeforeQa(int filler) {
    List<String> observations = new ArrayList<>();
    for (int index = 0; index < filler; index++) {
      observations.add(
          "아이와 함께 그림을 보며 오늘 어떤 마음이었는지 천천히 물어봐 주세요. 대답을 재촉하지 않고 기다려 주면 아이가 더 편하게 이야기합니다. ("
              + index
              + ")");
    }
    List<ReportSubjectResponse> subjects =
        List.of(
            new ReportSubjectResponse(
                "HOUSE",
                null,
                observations,
                List.of(
                    new ReportQaPairResponse(
                        "질문 마커 이 집에는 누가 살고 있어?",
                        "답 마커 우리 가족이 다 같이 살아요",
                        "ANSWERED",
                        "TEXT",
                        false,
                        true)),
                List.of()));
    return base(null, null, subjects, List.of(), null);
  }

  private ReportDetailResponse base(
      ReportDrawingResponse drawing,
      ReportChildExpressionResponse expression,
      List<ReportSubjectResponse> subjects,
      List<String> guide,
      String activityType) {
    return new ReportDetailResponse(
        901L,
        1,
        "COMPLETED",
        new ReportDrawingSessionResponse(
            100L,
            1L,
            activityType == null ? "ART_DIARY" : activityType,
            activityType == null ? "그림일기" : "집·나무·사람",
            "우리 가족",
            "CANVAS",
            LocalDateTime.of(2026, 8, 6, 10, 0),
            LocalDateTime.of(2026, 8, 6, 10, 20),
            1_200_000L),
        drawing,
        expression,
        List.of(),
        null,
        null,
        guide,
        List.of(),
        ReportExpertReviewResponse.notRequested(),
        LocalDateTime.of(2026, 8, 6, 10, 21),
        ReportDetailResponse.NON_DIAGNOSTIC_NOTICE,
        List.of(),
        List.of(),
        subjects,
        List.of(),
        null,
        List.of(),
        activityType,
        "민준");
  }
}
