package com.ssafy.b209.report.service;

import java.awt.Color;
import java.io.IOException;
import java.util.ArrayList;
import java.util.List;
import org.apache.pdfbox.pdmodel.PDDocument;
import org.apache.pdfbox.pdmodel.PDPage;
import org.apache.pdfbox.pdmodel.PDPageContentStream;
import org.apache.pdfbox.pdmodel.PDPageContentStream.AppendMode;
import org.apache.pdfbox.pdmodel.common.PDRectangle;
import org.apache.pdfbox.pdmodel.font.PDType0Font;

/**
 * 리포트 PDF 의 표지·카드·칩·페이지 번호를 그리는 배치기다.
 *
 * <p>화면과 같은 색과 계층으로 종이를 채운다. 색·간격은 앱 디자인 토큰({@code app_colors.dart})에서 가져와, 보호자가 화면에서 본 리포트와 인쇄물이
 * 같은 문서로 읽히게 한다.
 *
 * <p>줄바꿈은 글자 수가 아니라 실제 글자 폭으로 계산한다. 예전에는 72자마다 끊어 한글이 낱말 중간에서 잘렸다.
 */
final class ReportPdfWriter implements AutoCloseable {

  // 앱 디자인 토큰과 같은 색이다.
  private static final Color INK = new Color(0x27, 0x31, 0x3A);
  private static final Color INK_MUTED = new Color(0x68, 0x73, 0x7D);
  private static final Color CANVAS = new Color(0xFF, 0xFC, 0xF5);
  private static final Color SURFACE = Color.WHITE;
  private static final Color SURFACE_SOFT = new Color(0xF6, 0xF7, 0xF2);
  private static final Color OUTLINE = new Color(0xDD, 0xE2, 0xDC);
  private static final Color BRAND = new Color(0xF2, 0xD7, 0x65);
  private static final Color BRAND_SOFT = new Color(0xFC, 0xF4, 0xCE);

  private static final float MARGIN = 40F;
  private static final float CARD_PADDING = 14F;
  private static final float CARD_GAP = 12F;
  private static final float CORNER = 10F;

  private static final float TITLE_SIZE = 20F;
  private static final float SECTION_SIZE = 12.5F;
  private static final float BODY_SIZE = 10.5F;
  private static final float CAPTION_SIZE = 9F;
  private static final float BODY_LEADING = 15F;
  private static final float CAPTION_LEADING = 13F;
  private static final float CHIP_HEIGHT = 18F;
  private static final float CHIP_GAP = 6F;
  private static final float BULLET_INDENT = 12F;

  /** 카드가 이만큼도 못 들어가면 다음 장에서 시작한다. 제목만 남기고 넘기지 않는다. */
  private static final float MIN_CARD_SPACE = 70F;

  private final PDDocument document;
  private final PDType0Font regular;
  private final PDType0Font bold;

  private PDPage page;
  private PDPageContentStream content;
  private float cursorY;
  private boolean closed;

  ReportPdfWriter(PDDocument document, PDType0Font regular, PDType0Font bold) throws IOException {
    this.document = document;
    this.regular = regular;
    this.bold = bold;
    newPage();
  }

  /** 표지 띠다. 제목과 리포트 번호·활동 정보를 담는다. */
  void cover(String title, List<String> metaLines) throws IOException {
    float contentWidth = contentWidth();
    List<String> meta = new ArrayList<>();
    for (String line : metaLines) {
      meta.addAll(wrap(line, regular, CAPTION_SIZE, contentWidth - CARD_PADDING * 2));
    }
    float height = CARD_PADDING * 2 + TITLE_SIZE + 6 + meta.size() * CAPTION_LEADING;
    fillRoundedRect(MARGIN, cursorY - height, contentWidth, height, BRAND);
    float textY = cursorY - CARD_PADDING - TITLE_SIZE;
    drawText(title, bold, TITLE_SIZE, MARGIN + CARD_PADDING, textY, INK);
    float metaY = textY - 6;
    for (String line : meta) {
      metaY -= CAPTION_LEADING;
      drawText(line, regular, CAPTION_SIZE, MARGIN + CARD_PADDING, metaY, INK);
    }
    cursorY -= height + CARD_GAP;
  }

  /** 비진단 고지다. 본문 카드보다 옅게 두어 안내로 읽히게 한다. */
  void notice(String text) throws IOException {
    float contentWidth = contentWidth();
    List<String> lines = wrap(text, regular, CAPTION_SIZE, contentWidth - CARD_PADDING * 2);
    float height = CARD_PADDING * 2 + lines.size() * CAPTION_LEADING;
    ensureSpace(height);
    fillRoundedRect(MARGIN, cursorY - height, contentWidth, height, BRAND_SOFT);
    float textY = cursorY - CARD_PADDING;
    for (String line : lines) {
      textY -= CAPTION_LEADING;
      drawText(line, regular, CAPTION_SIZE, MARGIN + CARD_PADDING, textY, INK);
    }
    cursorY -= height + CARD_GAP;
  }

  /**
   * 섹션 카드 하나를 그린다.
   *
   * <p>한 장에 다 못 들어가면 들어가는 만큼만 담고 다음 장에 `(이어서)` 카드로 잇는다. 카드 배경을 먼저 그려야 하므로 담을 줄을 미리 세어 높이를 정한다.
   */
  void section(String title, List<ReportPdfRow> rows) throws IOException {
    if (rows.isEmpty()) return;
    List<Line> lines = layout(rows);
    String currentTitle = title;
    int index = 0;
    while (index < lines.size()) {
      if (remainingSpace() < MIN_CARD_SPACE) newPage();
      float headerHeight = CARD_PADDING + SECTION_SIZE + 8;
      float available = remainingSpace() - headerHeight - CARD_PADDING;
      int taken = 0;
      float used = 0;
      while (index + taken < lines.size()
          && used + lines.get(index + taken).height() <= available) {
        used += lines.get(index + taken).height();
        taken++;
      }
      // 한 줄도 못 담을 만큼 남았으면 새 장에서 다시 잰다. 그렇지 않으면 빈 카드가 쌓인다.
      if (taken == 0) {
        newPage();
        continue;
      }
      float height = headerHeight + used + CARD_PADDING;
      fillRoundedRect(MARGIN, cursorY - height, contentWidth(), height, SURFACE);
      strokeRoundedRect(MARGIN, cursorY - height, contentWidth(), height, OUTLINE);
      float y = cursorY - CARD_PADDING - SECTION_SIZE;
      drawText(currentTitle, bold, SECTION_SIZE, MARGIN + CARD_PADDING, y, INK);
      y -= 8;
      for (int offset = 0; offset < taken; offset++) {
        Line line = lines.get(index + offset);
        y -= line.height();
        drawLine(line, y);
      }
      cursorY -= height + CARD_GAP;
      index += taken;
      if (index < lines.size()) {
        currentTitle = title + " (이어서)";
        newPage();
      }
    }
  }

  /** 페이지 번호를 뒤에서 한 번에 붙인다. 전체 장수는 다 그린 뒤에야 알 수 있다. */
  void finish() throws IOException {
    closed = true;
    content.close();
    int total = document.getNumberOfPages();
    for (int index = 0; index < total; index++) {
      PDPage target = document.getPage(index);
      try (PDPageContentStream footer =
          new PDPageContentStream(document, target, AppendMode.APPEND, true, true)) {
        String label = (index + 1) + " / " + total;
        float width = textWidth(label, regular, CAPTION_SIZE);
        footer.beginText();
        footer.setFont(regular, CAPTION_SIZE);
        footer.setNonStrokingColor(INK_MUTED);
        footer.newLineAtOffset((target.getMediaBox().getWidth() - width) / 2, MARGIN / 2);
        footer.showText(label);
        footer.endText();
      }
    }
  }

  @Override
  public void close() throws IOException {
    // 렌더링이 예외로 끊겼을 때 열린 스트림을 닫는다. finish() 가 이미 닫았으면 할 일이 없다.
    if (!closed) {
      closed = true;
      content.close();
    }
  }

  private void drawLine(Line line, float y) throws IOException {
    switch (line.kind()) {
      case BODY ->
          drawText(line.text(), regular, BODY_SIZE, MARGIN + CARD_PADDING + line.indent(), y, INK);
      case SUBTITLE ->
          drawText(line.text(), bold, BODY_SIZE, MARGIN + CARD_PADDING + line.indent(), y, INK);
      case CAPTION ->
          drawText(
              line.text(),
              regular,
              CAPTION_SIZE,
              MARGIN + CARD_PADDING + line.indent(),
              y,
              INK_MUTED);
      case KEY_VALUE -> {
        drawText(line.text(), regular, BODY_SIZE, MARGIN + CARD_PADDING, y, INK_MUTED);
        drawText(line.value(), regular, BODY_SIZE, MARGIN + CARD_PADDING + 110, y, INK);
      }
      case CHIPS -> drawChips(line.chips(), y);
    }
  }

  private void drawChips(List<String> labels, float baselineY) throws IOException {
    float x = MARGIN + CARD_PADDING;
    float limit = MARGIN + contentWidth() - CARD_PADDING;
    for (String label : labels) {
      float textWidth = textWidth(label, regular, BODY_SIZE);
      float chipWidth = textWidth + 16;
      if (x + chipWidth > limit) break;
      fillRoundedRect(x, baselineY - 4, chipWidth, CHIP_HEIGHT, BRAND_SOFT, CHIP_HEIGHT / 2);
      drawText(label, regular, BODY_SIZE, x + 8, baselineY, INK);
      x += chipWidth + CHIP_GAP;
    }
  }

  /** 줄 종류별 높이와 줄바꿈을 미리 확정한다. 카드 배경 높이를 알아야 하기 때문이다. */
  private List<Line> layout(List<ReportPdfRow> rows) throws IOException {
    float bodyWidth = contentWidth() - CARD_PADDING * 2;
    List<Line> lines = new ArrayList<>();
    for (ReportPdfRow row : rows) {
      switch (row) {
        case ReportPdfRow.Text text -> {
          for (String line : wrap(text.value(), regular, BODY_SIZE, bodyWidth)) {
            lines.add(Line.body(line, 0));
          }
        }
        case ReportPdfRow.Subtitle subtitle -> {
          for (String line : wrap(subtitle.value(), bold, BODY_SIZE, bodyWidth)) {
            lines.add(new Line(Kind.SUBTITLE, line, null, List.of(), 0, BODY_LEADING));
          }
        }
        case ReportPdfRow.Bullet bullet -> {
          List<String> wrapped =
              wrap(bullet.value(), regular, BODY_SIZE, bodyWidth - BULLET_INDENT);
          for (int index = 0; index < wrapped.size(); index++) {
            String text = index == 0 ? "• " + wrapped.get(index) : wrapped.get(index);
            lines.add(Line.body(text, index == 0 ? 0 : BULLET_INDENT));
          }
        }
        case ReportPdfRow.Caption caption -> {
          for (String line :
              wrap(caption.value(), regular, CAPTION_SIZE, bodyWidth - BULLET_INDENT)) {
            lines.add(
                new Line(Kind.CAPTION, line, null, List.of(), BULLET_INDENT, CAPTION_LEADING));
          }
        }
        case ReportPdfRow.KeyValue keyValue ->
            lines.add(
                new Line(
                    Kind.KEY_VALUE,
                    keyValue.label(),
                    keyValue.value(),
                    List.of(),
                    0,
                    BODY_LEADING));
        case ReportPdfRow.Chips chips -> {
          if (!chips.labels().isEmpty()) {
            lines.add(
                new Line(
                    Kind.CHIPS, null, null, chips.labels(), 0, CHIP_HEIGHT + BODY_LEADING - 10));
          }
        }
      }
    }
    return lines;
  }

  private void newPage() throws IOException {
    if (content != null) content.close();
    page = new PDPage(PDRectangle.A4);
    document.addPage(page);
    content = new PDPageContentStream(document, page);
    content.setNonStrokingColor(CANVAS);
    content.addRect(0, 0, page.getMediaBox().getWidth(), page.getMediaBox().getHeight());
    content.fill();
    cursorY = page.getMediaBox().getHeight() - MARGIN;
  }

  private void ensureSpace(float height) throws IOException {
    if (remainingSpace() < height) newPage();
  }

  private float remainingSpace() {
    return cursorY - MARGIN;
  }

  private float contentWidth() {
    return page.getMediaBox().getWidth() - MARGIN * 2;
  }

  private void fillRoundedRect(float x, float y, float width, float height, Color color)
      throws IOException {
    fillRoundedRect(x, y, width, height, color, CORNER);
  }

  private void fillRoundedRect(
      float x, float y, float width, float height, Color color, float corner) throws IOException {
    content.setNonStrokingColor(color);
    roundedPath(x, y, width, height, Math.min(corner, Math.min(width, height) / 2));
    content.fill();
  }

  private void strokeRoundedRect(float x, float y, float width, float height, Color color)
      throws IOException {
    content.setStrokingColor(color);
    content.setLineWidth(0.8F);
    roundedPath(x, y, width, height, Math.min(CORNER, Math.min(width, height) / 2));
    content.stroke();
  }

  /** 둥근 사각형이다. PDFBox 에는 없어 베지어 네 개로 모서리를 만든다. */
  private void roundedPath(float x, float y, float width, float height, float radius)
      throws IOException {
    float control = radius * 0.4477F;
    content.moveTo(x + radius, y);
    content.lineTo(x + width - radius, y);
    content.curveTo(x + width - control, y, x + width, y + control, x + width, y + radius);
    content.lineTo(x + width, y + height - radius);
    content.curveTo(
        x + width,
        y + height - control,
        x + width - control,
        y + height,
        x + width - radius,
        y + height);
    content.lineTo(x + radius, y + height);
    content.curveTo(x + control, y + height, x, y + height - control, x, y + height - radius);
    content.lineTo(x, y + radius);
    content.curveTo(x, y + control, x + control, y, x + radius, y);
    content.closePath();
  }

  private void drawText(String text, PDType0Font font, float size, float x, float y, Color color)
      throws IOException {
    String safe = encodable(text, font);
    if (safe.isEmpty()) return;
    content.beginText();
    content.setFont(font, size);
    content.setNonStrokingColor(color);
    content.newLineAtOffset(x, y);
    content.showText(safe);
    content.endText();
  }

  /** 폭에 맞춰 줄을 나눈다. 빈칸이 있으면 낱말 경계에서 끊고, 없으면(한글 문장) 글자에서 끊는다. */
  private List<String> wrap(String text, PDType0Font font, float size, float maxWidth)
      throws IOException {
    String safe = encodable(text, font);
    List<String> lines = new ArrayList<>();
    if (safe.isEmpty()) return lines;
    StringBuilder line = new StringBuilder();
    int lastSpace = -1;
    for (int index = 0; index < safe.length(); index++) {
      line.append(safe.charAt(index));
      if (safe.charAt(index) == ' ') lastSpace = line.length() - 1;
      if (textWidth(line.toString(), font, size) <= maxWidth) continue;
      if (lastSpace > 0) {
        lines.add(line.substring(0, lastSpace));
        String rest = line.substring(lastSpace + 1);
        line.setLength(0);
        line.append(rest);
      } else {
        lines.add(line.substring(0, Math.max(1, line.length() - 1)));
        char overflow = safe.charAt(index);
        line.setLength(0);
        line.append(overflow);
      }
      lastSpace = -1;
    }
    if (!line.isEmpty()) lines.add(line.toString());
    return lines;
  }

  private float textWidth(String text, PDType0Font font, float size) throws IOException {
    return font.getStringWidth(text) / 1000 * size;
  }

  /**
   * 폰트가 그릴 수 있는 글자만 남긴다.
   *
   * <p>제어문자와 이모지는 {@code showText} 에서 예외를 던진다. AI 문장이나 아이 발화에 이모지가 하나 섞이면 리포트 내보내기 전체가 실패하므로, 못 그리는
   * 글자는 조용히 버리고 나머지를 살린다.
   */
  private String encodable(String text, PDType0Font font) {
    if (text == null) return "";
    String cleaned = text.replaceAll("\\p{Cntrl}", " ").trim();
    StringBuilder builder = new StringBuilder(cleaned.length());
    int index = 0;
    while (index < cleaned.length()) {
      int codePoint = cleaned.codePointAt(index);
      String glyph = new String(Character.toChars(codePoint));
      index += Character.charCount(codePoint);
      try {
        font.getStringWidth(glyph);
        builder.append(glyph);
      } catch (IOException | IllegalArgumentException ignored) {
        // 이 폰트로 그릴 수 없는 글자다. 문장 전체를 잃는 대신 이 글자만 버린다.
      }
    }
    return builder.toString();
  }

  private enum Kind {
    BODY,
    SUBTITLE,
    CAPTION,
    KEY_VALUE,
    CHIPS
  }

  private record Line(
      Kind kind, String text, String value, List<String> chips, float indent, float height) {
    static Line body(String text, float indent) {
      return new Line(Kind.BODY, text, null, List.of(), indent, BODY_LEADING);
    }
  }
}
