package com.ssafy.b209.report.service;

import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.report.dto.ReportDetailResponse;
import com.ssafy.b209.report.dto.ReportEvidenceItemResponse;
import com.ssafy.b209.report.dto.ReportParentGuideResponse;
import com.ssafy.b209.report.dto.ReportPublicInterpretationResponse;
import com.ssafy.b209.report.dto.ReportSubjectResponse;
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
import org.apache.pdfbox.pdmodel.font.PDType0Font;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

/**
 * 보호자에게 공개 가능한 리포트 상세 DTO를 화면과 같은 서식의 한글 PDF로 렌더링한다.
 *
 * <p>입력 DTO 자체가 보호자 안전 필드를 선별하므로 AI 내부 지표나 전문가 전용 관찰값을 별도로 조회하지 않는다.
 *
 * <p>예전에는 모든 내용을 한 가지 크기의 줄글로 찍어, 화면의 표지·카드·감정 칩·라벨 구분이 사라진 목록만 남았다. 지금은 {@link ReportPdfWriter}가 앱
 * 디자인 토큰과 같은 색·계층으로 카드를 그린다. 담는 데이터와 섹션 순서는 계약(S15P11B209-875 §11)을 그대로 지킨다 — 화면엔 있고 PDF엔 없는 데이터를
 * 만들지 않는다.
 *
 * <p>그림 이미지는 싣지 않는다. 그림 URL은 인증이 필요한 상대 경로이고 이 구성 요소는 저장소 의존이 없다(S15P11B209-957).
 */
@Component
public class ReportPdfRenderer {

  private static final Logger log = LoggerFactory.getLogger(ReportPdfRenderer.class);

  private static final String REGULAR_FONT = "/fonts/NanumSquareNeo-Regular.ttf";
  private static final String BOLD_FONT = "/fonts/NanumSquareNeo-Bold.ttf";
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
    try (PDDocument document = new PDDocument()) {
      PDType0Font regular = loadFont(document, REGULAR_FONT);
      PDType0Font bold = loadFont(document, BOLD_FONT);
      try (ReportPdfWriter writer = new ReportPdfWriter(document, regular, bold)) {
        writeReport(writer, report);
        writer.finish();
      }
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

  private PDType0Font loadFont(PDDocument document, String resource) throws IOException {
    try (InputStream fontStream = ReportPdfRenderer.class.getResourceAsStream(resource)) {
      if (fontStream == null) {
        log.error("리포트 PDF 폰트 리소스를 찾을 수 없습니다. resource={}", resource);
        throw new BusinessException(ReportExportErrorCode.REPORT_EXPORT_FAILED);
      }
      return PDType0Font.load(document, fontStream);
    }
  }

  /** 화면(875 §11)과 같은 순서로 섹션을 쌓는다. 비어 있는 섹션은 그리지 않는다 — 오류가 아니다. */
  private void writeReport(ReportPdfWriter writer, ReportDetailResponse report) throws IOException {
    writer.cover("도담 관찰 리포트", coverMeta(report));
    if (report.nonDiagnosticNotice() != null && !report.nonDiagnosticNotice().isBlank()) {
      writer.notice(report.nonDiagnosticNotice());
    }
    writer.section("활동 정보", activityInfoRows(report));
    writer.section("주요 심리 경향", interpretationRows(report));
    writer.section("주제별 관찰", subjectRows(report));
    writer.section("아이의 표현", expressionRows(report));
    writer.section("이런 모습이 보였어요", observedFeatureRows(report));
    writer.section("활동 기록", activityFactRows(report));
    writer.section("대화 요약", conversationRows(report));
    writer.section("보호자 대화 안내", bulletRows(report.guardianConversationGuide()));
    for (ReportParentGuideResponse guide : report.parentGuides()) {
      writer.section(guideTitle(guide.guideType()), bulletRows(guide.items()));
    }
    // 위기 안내는 인쇄물이 제3자에게 노출될 수 있어 본문에 싣지 않는다. 확인 경로만 남긴다.
    if (report.crisisAlert() != null) {
      writer.section("안전 안내", List.of(new ReportPdfRow.Text("보호자 화면에서 안전 안내를 확인해 주세요.")));
    }
    writer.section("주의 사항", bulletRows(report.limitations()));
    writer.section("참고 자료", referenceRows(report));
  }

  private List<String> coverMeta(ReportDetailResponse report) {
    List<String> meta = new ArrayList<>();
    meta.add("리포트 " + value(report.reportId()) + " · 버전 " + report.reportVersion());
    if (report.drawingSession() != null && report.drawingSession().startedAt() != null) {
      meta.add("활동 일시 " + report.drawingSession().startedAt().format(DATE_TIME_FORMATTER));
    }
    return meta;
  }

  private List<ReportPdfRow> activityInfoRows(ReportDetailResponse report) {
    if (report.drawingSession() == null) return List.of();
    List<ReportPdfRow> rows = new ArrayList<>();
    rows.add(new ReportPdfRow.KeyValue("활동", value(report.drawingSession().drawingTypeName())));
    rows.add(new ReportPdfRow.KeyValue("제목", value(report.drawingSession().title())));
    rows.add(new ReportPdfRow.KeyValue("입력 방식", value(report.drawingSession().inputMethod())));
    rows.add(new ReportPdfRow.KeyValue("생성 상태", value(report.reportStatus())));
    return rows;
  }

  private List<ReportPdfRow> interpretationRows(ReportDetailResponse report) {
    if (report.publicInterpretations().isEmpty()) return List.of();
    Map<Integer, String> evidenceTexts = new LinkedHashMap<>();
    for (ReportEvidenceItemResponse evidence : report.evidenceItems()) {
      evidenceTexts.put(evidence.evidenceId(), evidence.text());
    }
    List<ReportPdfRow> rows = new ArrayList<>();
    for (ReportPublicInterpretationResponse card : report.publicInterpretations()) {
      rows.add(new ReportPdfRow.Subtitle(value(card.title())));
      rows.add(new ReportPdfRow.Text(value(card.tendencyText())));
      // 경향 문장만 단독으로 싣지 않는다(875 §3). 범위와 살펴볼 점을 함께 낸다.
      rows.add(new ReportPdfRow.Caption("범위 " + value(card.scopeText())));
      rows.add(new ReportPdfRow.Caption("살펴볼 점 " + value(card.homeObservationGuide())));
      for (Integer evidenceRef : card.evidenceRefs()) {
        String evidenceText = evidenceTexts.get(evidenceRef);
        if (evidenceText != null) rows.add(new ReportPdfRow.Caption("근거 " + evidenceText));
      }
    }
    return rows;
  }

  private List<ReportPdfRow> subjectRows(ReportDetailResponse report) {
    if (report.subjectReports().isEmpty()) return List.of();
    List<ReportPdfRow> rows = new ArrayList<>();
    for (ReportSubjectResponse subject : report.subjectReports()) {
      rows.add(new ReportPdfRow.Subtitle(subjectTitle(subject.subjectType())));
      subject
          .visionObservations()
          .forEach(observation -> rows.add(new ReportPdfRow.Bullet(value(observation))));
      subject
          .qaPairs()
          .forEach(
              pair -> {
                rows.add(new ReportPdfRow.Text("Q " + value(pair.question())));
                rows.add(new ReportPdfRow.Caption("A " + value(pair.answer())));
              });
    }
    return rows;
  }

  private List<ReportPdfRow> expressionRows(ReportDetailResponse report) {
    if (report.childExpression() == null) return List.of();
    List<ReportPdfRow> rows = new ArrayList<>();
    if (!report.childExpression().selectedEmotions().isEmpty()) {
      rows.add(new ReportPdfRow.Chips(report.childExpression().selectedEmotions()));
    }
    if (report.childExpression().expressedEmotionText() != null
        && !report.childExpression().expressedEmotionText().isBlank()) {
      rows.add(new ReportPdfRow.Text(report.childExpression().expressedEmotionText()));
    }
    report
        .childExpression()
        .representativeUtterances()
        .forEach(utterance -> rows.add(new ReportPdfRow.Bullet(value(utterance.text()))));
    return rows;
  }

  private List<ReportPdfRow> observedFeatureRows(ReportDetailResponse report) {
    if (report.observedFeatures() == null || report.observedFeatures().isEmpty()) return List.of();
    List<ReportPdfRow> rows = new ArrayList<>();
    report
        .observedFeatures()
        .forEach(
            feature -> {
              rows.add(new ReportPdfRow.Subtitle(value(feature.title())));
              rows.add(new ReportPdfRow.Text(value(feature.description())));
              if (feature.evidenceSummary() != null && !feature.evidenceSummary().isBlank()) {
                rows.add(new ReportPdfRow.Caption("근거 " + feature.evidenceSummary()));
              }
            });
    return rows;
  }

  private List<ReportPdfRow> activityFactRows(ReportDetailResponse report) {
    if (report.activityFacts() == null) return List.of();
    List<ReportPdfRow> rows = new ArrayList<>();
    if (!report.activityFacts().detectedObjects().isEmpty()) {
      rows.add(new ReportPdfRow.Chips(report.activityFacts().detectedObjects()));
    }
    // 값의 출처가 VLM 관찰 서술로 바뀌었다(S15P11B209-912). 라벨도 화면과 같은 표현을 쓴다.
    rows.add(
        new ReportPdfRow.KeyValue(
            "그린 시간", durationText(report.activityFacts().drawingDurationSec())));
    rows.add(new ReportPdfRow.KeyValue("멈춤 횟수", countText(report.activityFacts().pauseCount())));
    rows.add(new ReportPdfRow.KeyValue("지우기 횟수", countText(report.activityFacts().eraseCount())));
    report.activityFacts().notes().forEach(note -> rows.add(new ReportPdfRow.Caption(note)));
    return rows;
  }

  private List<ReportPdfRow> conversationRows(ReportDetailResponse report) {
    if (report.conversationSummary() == null
        || report.conversationSummary().summary() == null
        || report.conversationSummary().summary().isBlank()) {
      return List.of();
    }
    return List.of(new ReportPdfRow.Text(report.conversationSummary().summary()));
  }

  private List<ReportPdfRow> referenceRows(ReportDetailResponse report) {
    if (report.references().isEmpty()) return List.of();
    List<ReportPdfRow> rows = new ArrayList<>();
    report
        .references()
        .forEach(
            reference -> {
              rows.add(new ReportPdfRow.Bullet(value(reference.title())));
              if (reference.url() != null && !reference.url().isBlank()) {
                rows.add(new ReportPdfRow.Caption(reference.url()));
              }
            });
    return rows;
  }

  private List<ReportPdfRow> bulletRows(List<String> items) {
    if (items == null || items.isEmpty()) return List.of();
    List<ReportPdfRow> rows = new ArrayList<>();
    items.forEach(item -> rows.add(new ReportPdfRow.Bullet(value(item))));
    return rows;
  }

  private String subjectTitle(String subjectType) {
    return switch (subjectType == null ? "" : subjectType) {
      case "HOUSE" -> "집";
      case "TREE" -> "나무";
      case "PERSON" -> "사람";
      default -> "그림";
    };
  }

  private String guideTitle(String guideType) {
    return switch (guideType == null ? "" : guideType) {
      case "DRAWING_CONVERSATION" -> "그림으로 대화하기";
      case "DAILY_PARENTING" -> "일상에서 해볼 것";
      case "HOME_OBSERVATION" -> "집에서 살펴볼 점";
      default -> value(guideType);
    };
  }

  private String durationText(Integer durationSec) {
    if (durationSec == null || durationSec <= 0) return "-";
    int minutes = durationSec / 60;
    return minutes > 0 ? minutes + "분" : durationSec + "초";
  }

  private String countText(Integer count) {
    return count == null ? "-" : count + "회";
  }

  private String value(Object value) {
    return value == null || value.toString().isBlank() ? "-" : value.toString();
  }
}
