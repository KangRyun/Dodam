package com.ssafy.b209.report.service;

import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.report.dto.ReportDetailResponse;
import com.ssafy.b209.report.dto.ReportParentGuideResponse;
import com.ssafy.b209.report.dto.ReportPublicInterpretationResponse;
import com.ssafy.b209.report.exception.ReportExportErrorCode;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.apache.pdfbox.pdmodel.PDDocument;
import org.apache.pdfbox.pdmodel.PDPage;
import org.apache.pdfbox.pdmodel.PDPageContentStream;
import org.apache.pdfbox.pdmodel.common.PDRectangle;
import org.apache.pdfbox.pdmodel.font.PDType0Font;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

/**
 * 보호자에게 공개 가능한 리포트 상세 DTO를 한글 PDF 문서로 렌더링한다.
 *
 * <p>입력 DTO 자체가 보호자 안전 필드를 선별하므로 AI 내부 지표나 전문가 전용 관찰값을 별도로 조회하지 않는다.
 */
@Component
public class ReportPdfRenderer {

  private static final Logger log = LoggerFactory.getLogger(ReportPdfRenderer.class);

  private static final String FONT_RESOURCE = "/fonts/NanumSquareNeo-Regular.ttf";
  private static final float FONT_SIZE = 10.5F;
  private static final float LINE_HEIGHT = 16F;
  private static final float MARGIN = 48F;
  private static final int MAX_CHARACTERS_PER_LINE = 72;
  private static final DateTimeFormatter DATE_TIME_FORMATTER =
      DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm");

  /**
   * 보호자용 리포트 상세를 PDF 바이트로 변환한다.
   *
   * <p>렌더링 실패는 <b>종류를 가리지 않고</b> {@link ReportExportErrorCode#REPORT_EXPORT_FAILED}로 분류한다. 이전에는
   * {@code IOException}과 {@code IllegalArgumentException}만 감싸서, 그 밖의 예외가 전역 핸들러까지 올라가 {@code
   * COMMON_500_001}("서버 내부 오류가 발생했습니다.")로 응답됐다. 그 코드로는 클라이언트도 로그 독자도 <b>무엇이 실패했는지 알 수 없다</b> — 배포
   * 서버에서 PDF 다운로드가 그렇게 실패했고(S15P11B209-860) 원인 추적이 서버 로그 확보 없이는 불가능했다. 같은 실패 분류 소실이
   * S15P11B209-815에서도 리포트 생성을 전면 실패시켰다.
   *
   * @param report 보호자 권한과 안전 필드 검증을 마친 리포트
   * @return PDF 파일 바이트
   * @throws BusinessException 폰트 또는 PDF 문서를 생성할 수 없는 경우
   */
  public byte[] render(ReportDetailResponse report) {
    try (PDDocument document = new PDDocument();
        InputStream fontStream = ReportPdfRenderer.class.getResourceAsStream(FONT_RESOURCE)) {
      if (fontStream == null) {
        log.error("리포트 PDF 폰트 리소스를 찾을 수 없습니다. resource={}", FONT_RESOURCE);
        throw new BusinessException(ReportExportErrorCode.REPORT_EXPORT_FAILED);
      }
      PDType0Font font = PDType0Font.load(document, fontStream);
      writePages(document, font, buildLines(report));
      ByteArrayOutputStream output = new ByteArrayOutputStream();
      document.save(output);
      return output.toByteArray();
    } catch (BusinessException exception) {
      throw exception;
    } catch (IOException | RuntimeException exception) {
      // 근본 원인을 로그에 남긴다. 예외 타입·메시지만으로는 다음 발생 때도 같은 조사를 반복해야 한다.
      log.error(
          "리포트 PDF 렌더링에 실패했습니다. reportId={}, exceptionType={}, message={}",
          report == null ? null : report.reportId(),
          exception.getClass().getName(),
          exception.getMessage(),
          exception);
      throw new BusinessException(ReportExportErrorCode.REPORT_EXPORT_FAILED, exception);
    }
  }

  private void writePages(PDDocument document, PDType0Font font, List<String> lines)
      throws IOException {
    int lineIndex = 0;
    while (lineIndex < lines.size()) {
      PDPage page = new PDPage(PDRectangle.A4);
      document.addPage(page);
      int linesPerPage = (int) ((page.getMediaBox().getHeight() - (MARGIN * 2)) / LINE_HEIGHT);
      try (PDPageContentStream content = new PDPageContentStream(document, page)) {
        content.beginText();
        content.setFont(font, FONT_SIZE);
        content.setLeading(LINE_HEIGHT);
        content.newLineAtOffset(MARGIN, page.getMediaBox().getHeight() - MARGIN);
        for (int pageLine = 0; pageLine < linesPerPage && lineIndex < lines.size(); pageLine++) {
          content.showText(lines.get(lineIndex++));
          content.newLine();
        }
        content.endText();
      }
    }
  }

  private List<String> buildLines(ReportDetailResponse report) {
    List<String> lines = new ArrayList<>();
    add(lines, "도담 관찰 리포트");
    add(lines, "");
    add(lines, "리포트 번호: " + report.reportId());
    add(lines, "리포트 버전: " + report.reportVersion());
    add(lines, "생성 상태: " + value(report.reportStatus()));
    if (report.drawingSession() != null) {
      add(lines, "활동: " + value(report.drawingSession().drawingTypeName()));
      add(lines, "제목: " + value(report.drawingSession().title()));
      add(
          lines,
          "활동 일시: "
              + (report.drawingSession().startedAt() == null
                  ? "-"
                  : report.drawingSession().startedAt().format(DATE_TIME_FORMATTER)));
    }
    add(lines, "");
    // 875 §11 순서 1 — 표지 다음이 비진단 고지다. 경향 문장보다 먼저 나와야 한다.
    if (report.nonDiagnosticNotice() != null) {
      add(lines, report.nonDiagnosticNotice());
      add(lines, "");
    }
    // 875 §11 순서 3 — 주요 심리 경향. 경향 문장만 단독으로 싣지 않고 범위 안내와 근거를 함께 낸다(875 §3).
    if (!report.publicInterpretations().isEmpty()) {
      add(lines, "[주요 심리 경향]");
      Map<Integer, String> evidenceTexts = new LinkedHashMap<>();
      report
          .evidenceItems()
          .forEach(evidence -> evidenceTexts.put(evidence.evidenceId(), evidence.text()));
      for (ReportPublicInterpretationResponse card : report.publicInterpretations()) {
        add(lines, "• " + value(card.title()));
        add(lines, "  " + value(card.tendencyText()));
        add(lines, "  범위: " + value(card.scopeText()));
        add(lines, "  살펴볼 점: " + value(card.homeObservationGuide()));
        for (Integer evidenceRef : card.evidenceRefs()) {
          String evidenceText = evidenceTexts.get(evidenceRef);
          if (evidenceText != null) {
            add(lines, "  근거: " + evidenceText);
          }
        }
      }
      add(lines, "");
    }
    add(lines, "[아이의 표현]");
    if (report.childExpression() != null) {
      add(lines, "선택 감정: " + String.join(", ", report.childExpression().selectedEmotions()));
      add(lines, "표현: " + value(report.childExpression().expressedEmotionText()));
      report
          .childExpression()
          .representativeUtterances()
          .forEach(utterance -> add(lines, "대표 발화: " + value(utterance.text())));
    }
    // 화면에 실리는 공개 데이터는 PDF 에도 실린다(계약 S15P11B209-875 §11 — 화면엔 있고 PDF엔 없는 데이터 금지).
    //   여기 담기는 것은 이미 보호자에게 열린 항목뿐이라 별도 노출 판정을 다시 하지 않는다.
    if (report.observedFeatures() != null && !report.observedFeatures().isEmpty()) {
      add(lines, "");
      add(lines, "[이런 모습이 보였어요]");
      report
          .observedFeatures()
          .forEach(
              feature -> {
                add(lines, "• " + value(feature.title()));
                add(lines, "  " + value(feature.description()));
                if (feature.evidenceSummary() != null && !feature.evidenceSummary().isBlank()) {
                  add(lines, "  근거: " + feature.evidenceSummary());
                }
              });
    }
    add(lines, "");
    add(lines, "[활동 기록]");
    if (report.activityFacts() != null) {
      // 값의 출처가 VLM 관찰 서술로 바뀌었다(S15P11B209-912). 라벨도 화면과 같은 표현을 쓴다.
      add(lines, "그린 것: " + String.join(", ", report.activityFacts().detectedObjects()));
      add(lines, "그리기 시간(초): " + value(report.activityFacts().drawingDurationSec()));
      add(lines, "멈춤 횟수: " + value(report.activityFacts().pauseCount()));
      add(lines, "지우기 횟수: " + value(report.activityFacts().eraseCount()));
      report.activityFacts().notes().forEach(note -> add(lines, "참고: " + note));
    }
    add(lines, "");
    add(lines, "[대화 요약]");
    if (report.conversationSummary() != null) {
      add(lines, value(report.conversationSummary().summary()));
    }
    add(lines, "");
    add(lines, "[보호자 대화 안내]");
    report.guardianConversationGuide().forEach(guide -> add(lines, "• " + guide));
    add(lines, "");
    // 875 §11 순서 8~10 — 유형별 보호자 가이드.
    for (ReportParentGuideResponse guide : report.parentGuides()) {
      add(lines, "[" + value(guide.guideType()) + "]");
      guide.items().forEach(item -> add(lines, "• " + item));
      add(lines, "");
    }
    // 위기 안내는 인쇄물이 제3자에게 노출될 수 있어 본문에 싣지 않는다. 필요 여부만 남긴다.
    if (report.crisisAlert() != null) {
      add(lines, "[안전 안내]");
      add(lines, "보호자 화면에서 안전 안내를 확인해 주세요.");
      add(lines, "");
    }
    add(lines, "[주의 사항]");
    report.limitations().forEach(limitation -> add(lines, "• " + limitation));
    if (!report.references().isEmpty()) {
      add(lines, "");
      add(lines, "[참고 자료]");
      report
          .references()
          .forEach(
              reference ->
                  add(
                      lines,
                      "• "
                          + value(reference.title())
                          + (reference.url() == null ? "" : " (" + reference.url() + ")")));
    }
    return lines;
  }

  private void add(List<String> lines, String text) {
    String safeText = text == null ? "" : text.replaceAll("\\p{Cntrl}", " ");
    if (safeText.isEmpty()) {
      lines.add("");
      return;
    }
    for (int start = 0; start < safeText.length(); start += MAX_CHARACTERS_PER_LINE) {
      lines.add(
          safeText.substring(start, Math.min(start + MAX_CHARACTERS_PER_LINE, safeText.length())));
    }
  }

  private String value(Object value) {
    return value == null || value.toString().isBlank() ? "-" : value.toString();
  }
}
