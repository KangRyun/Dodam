package com.ssafy.b209.report.service;

import static org.assertj.core.api.Assertions.assertThat;

import com.openhtmltopdf.outputdevice.helper.BaseRendererBuilder;
import com.openhtmltopdf.pdfboxout.PdfRendererBuilder;
import com.openhtmltopdf.util.XRLog;
import java.awt.image.BufferedImage;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.util.Base64;
import java.util.logging.Level;
import javax.imageio.ImageIO;
import org.apache.pdfbox.Loader;
import org.apache.pdfbox.cos.COSName;
import org.apache.pdfbox.pdmodel.PDDocument;
import org.apache.pdfbox.pdmodel.PDResources;
import org.apache.pdfbox.text.PDFTextStripper;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;

/**
 * openhtmltopdf 로 리포트 PDF 를 그릴 수 있는지 검증한다(S15P11B209-967).
 *
 * <p>이 테스트는 <b>기술 검증</b>이다. 운영 렌더러를 바꾸지 않고, 전환(S15P11B209-968) 전에 우리 환경에서 되는 것과 안 되는 것을 코드로 고정한다.
 * 확인 항목은 한글 Regular/Bold 임베드, PNG 삽입, A4 여백, 쪽번호, 카드 단위 {@code page-break-inside: avoid}, 한 장을 넘는
 * 카드의 분할, 긴 한글 문장 줄바꿈, 여러 장 생성 시간이다.
 *
 * <p>⚠️ 확인하지 못한 것: Docker/Jenkins 환경 동일 출력. 이 테스트는 로컬 JVM 에서만 돌았다. 폰트를 리소스에서 직접 읽고 이미지를 data URI 로
 * 넣어 OS 폰트·파일 경로에 의존하지 않으므로 동일할 것으로 보이지만, CI 에서 한 번 돌려 확인해야 한다.
 */
class ReportPdfHtmlSpikeTest {

  private static final String FONT_FAMILY = "NanumSquareNeo";
  private static final String LONG_SENTENCE =
      "아이와 함께 그림을 보며 오늘 어떤 마음이었는지 천천히 물어봐 주세요. 대답을 재촉하지 않고 기다려 주면 아이가 더 편하게 자기 이야기를 들려줍니다.";

  @BeforeAll
  static void quietRendererLog() {
    // openhtmltopdf 는 기본으로 INFO 로그를 대량으로 찍는다. 테스트 출력만 조용히 한다.
    XRLog.setLevel(XRLog.CSS_PARSE, Level.WARNING);
    XRLog.setLevel(XRLog.LAYOUT, Level.WARNING);
  }

  @Test
  void embedsKoreanRegularAndBoldFonts() throws Exception {
    byte[] pdf = render(document(card("아이의 표현", "동생이랑 놀아서 좋았어요", false)));

    try (PDDocument document = Loader.loadPDF(pdf)) {
      String text = new PDFTextStripper().getText(document);
      // 폰트를 못 실으면 한글이 빠지거나 물음표로 나온다.
      assertThat(text).contains("아이의 표현").contains("동생이랑 놀아서 좋았어요");
    }
  }

  @Test
  void embedsPngImage() throws Exception {
    byte[] pdf = render(document(imageCard(png(600, 400))));

    try (PDDocument document = Loader.loadPDF(pdf)) {
      assertThat(hasImageXObject(document)).isTrue();
    }
  }

  @Test
  void keepsACardTogetherInsteadOfSplittingIt() throws Exception {
    // 첫 장을 거의 채운 뒤 카드를 하나 더 둔다. 카드가 잘리면 앞뒤 줄이 다른 장에 흩어진다.
    StringBuilder body = new StringBuilder();
    for (int index = 0; index < 12; index++) {
      body.append(card("채우기 " + index, LONG_SENTENCE, false));
    }
    body.append(card("함께 유지", "첫 줄 마커 START " + LONG_SENTENCE + " 끝 줄 마커 END", true));

    byte[] pdf = render(document(body.toString()));

    try (PDDocument document = Loader.loadPDF(pdf)) {
      assertThat(document.getNumberOfPages()).isGreaterThan(1);
      int startPage = pageContaining(document, "START");
      int endPage = pageContaining(document, "END");
      assertThat(startPage).isPositive();
      // 같은 카드의 첫 줄과 끝 줄이 같은 장에 있어야 한다.
      assertThat(endPage).isEqualTo(startPage);
    }
  }

  @Test
  void splitsACardThatIsTallerThanOnePage() throws Exception {
    StringBuilder tall = new StringBuilder();
    for (int index = 0; index < 40; index++) {
      tall.append("<p>").append(index).append(" ").append(LONG_SENTENCE).append("</p>");
    }
    // 한 장을 넘는 카드는 keep-together 를 걸어도 나뉘어야 한다. 안 나뉘면 내용이 사라진다.
    byte[] pdf = render(document(rawCard("아주 긴 카드", tall.toString(), true)));

    try (PDDocument document = Loader.loadPDF(pdf)) {
      assertThat(document.getNumberOfPages()).isGreaterThan(1);
      String text = new PDFTextStripper().getText(document);
      assertThat(text).contains("0 아이와").contains("39 아이와");
    }
  }

  @Test
  void printsPageNumberOnEveryPage() throws Exception {
    StringBuilder body = new StringBuilder();
    for (int index = 0; index < 20; index++) {
      body.append(card("섹션 " + index, LONG_SENTENCE, false));
    }

    byte[] pdf = render(document(body.toString()));

    try (PDDocument document = Loader.loadPDF(pdf)) {
      int pages = document.getNumberOfPages();
      assertThat(pages).isGreaterThan(2);
      for (int page = 1; page <= pages; page++) {
        assertThat(pageText(document, page)).as("%d 쪽 번호", page).contains(page + " / " + pages);
      }
    }
  }

  @Test
  void rendersTenPagesInReasonableTime() throws Exception {
    StringBuilder body = new StringBuilder();
    for (int index = 0; index < 60; index++) {
      body.append(card("섹션 " + index, LONG_SENTENCE, false));
    }
    body.append(imageCard(png(1200, 900)));

    long startedAt = System.nanoTime();
    byte[] pdf = render(document(body.toString()));
    long elapsedMs = (System.nanoTime() - startedAt) / 1_000_000;

    try (PDDocument document = Loader.loadPDF(pdf)) {
      assertThat(document.getNumberOfPages()).isGreaterThanOrEqualTo(5);
    }
    // 요청 경로에서 동기로 만들 수 있는 범위인지 본다. 넉넉한 상한이며 실측은 로그로 남긴다.
    System.out.println("openhtmltopdf 렌더링 " + elapsedMs + "ms, " + pdf.length + "bytes");
    assertThat(elapsedMs).isLessThan(15_000);
  }

  // ── 샘플 문서 ────────────────────────────────────────────────────────

  /**
   * PDF 전용 XHTML 이다.
   *
   * <p>openhtmltopdf 는 브라우저가 아니라 flex·grid 를 쓰지 않는다. 쪽번호는 {@code position: fixed} 요소가 모든 장에 반복되는
   * 성질과 {@code counter(page)} 를 함께 쓴다.
   */
  private String document(String body) {
    return """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml">
        <head><meta charset="UTF-8" /><style>
          @page { size: A4; margin: 15mm 14mm 18mm; }
          body { font-family: '%s'; font-size: 10.5pt; color: #27313A; line-height: 1.55; }
          .card { border: 1px solid #DDE2DC; border-radius: 10px; padding: 10px 12px;
                  margin-bottom: 10px; }
          .keep { page-break-inside: avoid; }
          .card h2 { font-size: 12pt; font-weight: bold; margin: 0 0 6px 0;
                     border-left: 4px solid #8F83DD; padding-left: 8px; }
          .card p { margin: 0 0 4px 0; }
          #footer { position: fixed; bottom: -12mm; left: 0; right: 0; text-align: center;
                    font-size: 8pt; color: #68737D; }
          #footer::after { content: counter(page) " / " counter(pages); }
          img { display: block; width: 100%%; }
        </style></head>
        <body><div id="footer"></div>%s</body>
        </html>
        """
        .formatted(FONT_FAMILY, body);
  }

  private String card(String title, String text, boolean keepTogether) {
    return rawCard(title, "<p>" + text + "</p>", keepTogether);
  }

  private String rawCard(String title, String innerHtml, boolean keepTogether) {
    return "<div class=\"card%s\"><h2>%s</h2>%s</div>"
        .formatted(keepTogether ? " keep" : "", title, innerHtml);
  }

  private String imageCard(byte[] image) {
    return """
        <div class="card keep"><h2>그림</h2>
        <img src="data:image/png;base64,%s" />
        </div>"""
        .formatted(Base64.getEncoder().encodeToString(image));
  }

  // ── 렌더링·검사 도구 ──────────────────────────────────────────────────

  private byte[] render(String html) throws IOException {
    ByteArrayOutputStream output = new ByteArrayOutputStream();
    PdfRendererBuilder builder = new PdfRendererBuilder();
    builder.useFastMode();
    useFont(builder, "/fonts/NanumSquareNeo-Regular.ttf", 400);
    useFont(builder, "/fonts/NanumSquareNeo-Bold.ttf", 700);
    builder.withHtmlContent(html, null);
    builder.toStream(output);
    builder.run();
    return output.toByteArray();
  }

  private void useFont(PdfRendererBuilder builder, String resource, int weight) {
    builder.useFont(
        () -> {
          InputStream stream = ReportPdfHtmlSpikeTest.class.getResourceAsStream(resource);
          if (stream == null) {
            throw new IllegalStateException("폰트 리소스를 찾을 수 없습니다: " + resource);
          }
          return stream;
        },
        FONT_FAMILY,
        weight,
        BaseRendererBuilder.FontStyle.NORMAL,
        true);
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
      if (pageText(document, page).contains(marker)) return page;
    }
    return -1;
  }

  private String pageText(PDDocument document, int page) throws IOException {
    PDFTextStripper stripper = new PDFTextStripper();
    stripper.setStartPage(page);
    stripper.setEndPage(page);
    return stripper.getText(document);
  }

  private byte[] png(int width, int height) throws IOException {
    BufferedImage image = new BufferedImage(width, height, BufferedImage.TYPE_INT_RGB);
    ByteArrayOutputStream output = new ByteArrayOutputStream();
    ImageIO.write(image, "png", output);
    return output.toByteArray();
  }
}
