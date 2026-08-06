package com.ssafy.b209.report.service;

import com.ssafy.b209.report.dto.ReportActivityFactsResponse;
import com.ssafy.b209.report.dto.ReportDetailResponse;
import com.ssafy.b209.report.dto.ReportEvidenceItemResponse;
import com.ssafy.b209.report.dto.ReportObservedFeatureResponse;
import com.ssafy.b209.report.dto.ReportParentGuideResponse;
import com.ssafy.b209.report.dto.ReportPublicInterpretationResponse;
import com.ssafy.b209.report.dto.ReportQaPairResponse;
import com.ssafy.b209.report.dto.ReportReferenceResponse;
import com.ssafy.b209.report.dto.ReportSubjectResponse;
import com.ssafy.b209.report.dto.ReportUtteranceResponse;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.Base64;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Objects;
import java.util.Optional;

/**
 * 보호자용 리포트를 PDF 전용 XHTML 문서로 옮긴다.
 *
 * <p>담는 데이터와 섹션 순서는 계약(S15P11B209-875 §11)을 그대로 지킨다 — 화면엔 있고 PDF엔 없는 데이터를 만들지 않는다. 반대로 표지의 "한눈에
 * 보기"는 본문에 이미 있는 값을 요약해 앞에 세운 것이라 새 데이터가 아니다.
 *
 * <h2>왜 HTML 인가</h2>
 *
 * <p>이전 렌더러는 PDFBox 로 좌표를 직접 계산했다. 그래서 카드가 장 경계에서 잘리는 것을 막으려면 남은 높이를 매번 손으로 재야 했고, 표지·요약 배치를 바꿀 때마다
 * 계산이 따라 붙었다. HTML/CSS 로 옮기면 "이 카드는 쪼개지 말 것"을 {@code page-break-inside: avoid} 한 줄로 말할 수
 * 있다(ADR-0003).
 *
 * <h2>openhtmltopdf 제약</h2>
 *
 * <ul>
 *   <li><b>브라우저가 아니다</b> — flex·grid 를 쓰지 않는다. 나란히 놓을 것은 표로 짠다
 *   <li><b>이모지 글리프가 없다</b> — 감정은 {@link ReportPdfEmotionIcon} 의 PNG 로 싣는다
 *   <li><b>이미지는 data URI</b> — 서버가 자기 인증 URL 을 HTTP 로 다시 부르지 않는다(S15P11B209-966)
 * </ul>
 *
 * <h2>페이지 분할 단위</h2>
 *
 * <p>{@code .keep} 을 붙인 묶음은 장 경계에서 쪼개지지 않는다. 붙이는 자리는 <b>의미가 끊기면 읽을 수 없는 단위</b>다 — 섹션 제목과 첫 카드, 카드
 * 하나, 질문과 답, 라벨과 값, 그림과 설명. 반대로 카드 <i>목록</i> 전체에는 붙이지 않는다. 붙이면 목록이 길어질 때 통째로 다음 장으로 밀려 앞 장이 비어 버린다.
 */
final class ReportPdfTemplate {

  /** 임베드한 폰트 이름이다. {@link ReportPdfRenderer} 가 같은 이름으로 등록한다. */
  static final String FONT_FAMILY = "NanumSquareNeo";

  /** 건너뛴 문답 상태다 (875 §6). */
  private static final String SKIPPED_STATE = "SKIPPED";

  /** 집·나무·사람 활동 코드다. <b>사람이 읽는 표시명이 아니라 코드로만 분기한다.</b> */
  private static final String HTP_ACTIVITY_CODE = "HTP";

  /** A4 폭에서 좌우 여백을 뺀 본문 폭이다(210 - 14 * 2). 그림 배치 크기를 여기에 맞춘다. */
  private static final double CONTENT_WIDTH_MM = 182;

  /**
   * 표지 대표 그림의 높이 상한이다.
   *
   * <p>제목·고지·요약과 <b>한 장에 함께</b> 들어가야 한다. 넘치면 그림이 다음 장으로 밀리고, 표지 뒤에서 장을 넘기므로 그림만 있는 장이 하나 생긴다. 요약
   * 문장이 길어질 여지까지 보고 여유를 둔 값이다(요약 3줄 기준).
   */
  private static final double COVER_IMAGE_MAX_HEIGHT_MM = 54;

  /** 주제별 그림의 높이 상한이다. 관찰 서술과 문답이 같은 카드에 이어진다. */
  private static final double SUBJECT_IMAGE_MAX_HEIGHT_MM = 80;

  /** 표지에 세 장을 나란히 놓을 때 한 칸의 폭이다(본문 폭 182 을 셋으로 나누고 사이 여백을 뺀 값). */
  private static final double STRIP_IMAGE_WIDTH_MM = 56;

  private static final double STRIP_IMAGE_MAX_HEIGHT_MM = 42;

  /** 화면 표지의 안내 캐릭터다. 앱 자산({@code assets/characters})과 같은 파일을 서버에도 둔다. */
  private static final String MASCOT_RESOURCE = "/images/mascot/report_mascot_intro.png";

  private static final double MASCOT_WIDTH_MM = 34;

  /** 마스코트 원본 비율(480 x 560)이다. 앱의 {@code ReportMascotImage} 와 같은 값이다. */
  private static final double MASCOT_ASPECT_RATIO = 560.0 / 480.0;

  private static final DateTimeFormatter DATE_TIME_FORMATTER =
      DateTimeFormatter.ofPattern("yyyy년 M월 d일 HH:mm");

  private final ReportDetailResponse report;

  /** 그림 URL 로 찾는, 이미 읽어 둔 이미지다. 없는 URL 은 그림 없이 그린다. */
  private final Map<String, ReportImageAsset> images;

  ReportPdfTemplate(ReportDetailResponse report, Map<String, ReportImageAsset> images) {
    this.report = report;
    this.images = images;
  }

  /**
   * 리포트를 PDF 렌더러에 넘길 XHTML 문서로 만든다.
   *
   * @return 완결된 XHTML 문서
   */
  String build() {
    return """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml">
        <head><meta charset="UTF-8" /><title>%s</title><style>%s</style></head>
        <body>%s%s</body>
        </html>
        """
        .formatted(escape(documentTitle()), css(), cover(), body());
  }

  private String documentTitle() {
    return isHtpActivity() ? "도담 관찰 리포트 - 집·나무·사람" : "도담 관찰 리포트";
  }

  // ── 표지 겸 요약 ──────────────────────────────────────────────────────

  /**
   * 첫 장에 제목·비진단 고지·요약·대표 그림을 함께 싣는다.
   *
   * <p>제목만 있는 표지는 첫 장을 거의 비운다. 반대로 표지를 없애고 곧바로 본문을 시작하면 문서가 어디서 시작하는지 알기 어렵고, 무엇보다 <b>비진단 고지가 본문
   * 사이에 섞인다</b>. 계약 §11 은 고지를 표지 다음에 두라고 정한다 — 보호자가 첫 장에서 "이건 진단이 아니다"를 먼저 읽어야 한다.
   *
   * <p>표지 뒤에는 반드시 장을 넘긴다. 표지 아래에 본문 첫 카드가 걸치면 요약과 본문이 한 덩어리로 읽힌다.
   */
  private String cover() {
    StringBuilder cover = new StringBuilder();
    cover.append("<div class=\"cover\">");
    // 제목 묶음과 마스코트를 나란히 둔다. flex 가 없으니 표로 짠다.
    cover.append("<table class=\"cover-head keep\"><tr><td class=\"cover-copy\">");
    cover.append("<div class=\"brand\">도담</div>");
    cover.append("<h1>도담 관찰 리포트</h1>");
    cover.append("<div class=\"cover-sub\">").append(escape(coverHeadline())).append("</div>");
    cover.append("<p class=\"cover-lead\">").append(escape(coverLead())).append("</p>");
    cover.append(coverMeta());
    cover.append("</td>").append(coverMascot()).append("</tr></table>");
    if (has(report.nonDiagnosticNotice())) {
      cover.append("<div class=\"notice keep\">").append(escape(report.nonDiagnosticNotice()));
      cover.append("</div>");
    }
    cover.append(coverSummary());
    cover.append(coverDrawing());
    cover.append("</div>");
    return cover.toString();
  }

  /**
   * 표지 문구는 보호자 화면의 표지 카드와 같은 것을 쓴다({@code report_screen.dart} 의 {@code _ReportHero}).
   *
   * <p>화면은 "함께 돌아보자"고 말을 걸고 PDF 는 사무적인 제목만 낸다면, 같은 리포트가 두 인격으로 읽힌다. 집·나무·사람은 검사 이름·결과 표현을 쓰지
   * 않는다(CLAUDE.md 5절).
   */
  private String coverHeadline() {
    return isHtpActivity() ? "집·나무·사람, 세 그림 이야기" : "그림 속 이야기를 함께 돌아볼까요?";
  }

  private String coverLead() {
    return isHtpActivity()
        ? "집과 나무와 사람을 그리면서 아이가 들려준 이야기를 모았어요."
        : "돌아보기 친구가 아이의 그림과 이야기를 차근차근 정리했어요.";
  }

  /**
   * 화면 표지에 있는 안내 캐릭터를 표지에 함께 둔다.
   *
   * <p>장식이다. 못 읽으면 칸 자체를 만들지 않아 제목 묶음이 폭을 다 쓴다 — 빈 칸이 남는 것보다 낫다.
   */
  private String coverMascot() {
    Optional<String> mascot = ReportPdfResource.pngDataUri(MASCOT_RESOURCE);
    if (mascot.isEmpty()) return "";
    return String.format(
        Locale.ROOT,
        "<td class=\"cover-mascot\"><img style=\"width:%.1fmm;height:%.1fmm\" src=\"%s\" /></td>",
        MASCOT_WIDTH_MM,
        MASCOT_WIDTH_MM * MASCOT_ASPECT_RATIO,
        mascot.get());
  }

  /** 표지 정보를 라벨·값 표로 낸다. 라벨과 값은 같은 행이라 갈라지지 않는다. */
  private String coverMeta() {
    List<String[]> rows = new ArrayList<>();
    if (has(report.childDisplayName())) {
      rows.add(new String[] {"아이", report.childDisplayName()});
    }
    if (report.drawingSession() != null) {
      rows.add(new String[] {"활동", value(report.drawingSession().drawingTypeName())});
      if (has(report.drawingSession().title())) {
        rows.add(new String[] {"제목", report.drawingSession().title()});
      }
      if (report.drawingSession().startedAt() != null) {
        rows.add(
            new String[] {
              "활동 일시", report.drawingSession().startedAt().format(DATE_TIME_FORMATTER)
            });
      }
    }
    rows.add(new String[] {"리포트", value(report.reportId()) + " · 버전 " + report.reportVersion()});
    return keyValueTable(rows, "kv cover-meta");
  }

  /**
   * 본문에 있는 값을 요약해 앞에 세운다.
   *
   * <p>새 데이터를 만들지 않는다 — 감정은 "아이의 표현", 수치는 "활동 기록", 문장은 "대화 요약"에 각각 원문이 있다. 요약이 없으면 보호자는 열 장 넘는 문서를
   * 끝까지 읽어야 이번 활동이 어땠는지 알 수 있다.
   */
  private String coverSummary() {
    List<String> parts = new ArrayList<>();
    String chips = emotionChips();
    if (!chips.isEmpty()) {
      parts.add("<div class=\"summary-label\">아이가 고른 마음</div>" + chips);
    }
    String stats = summaryStats();
    if (!stats.isEmpty()) {
      parts.add(stats);
    }
    if (report.conversationSummary() != null && has(report.conversationSummary().summary())) {
      parts.add(
          "<div class=\"summary-label\">이번 활동 요약</div><p class=\"summary-text\">%s</p>"
              .formatted(escape(report.conversationSummary().summary())));
    }
    if (parts.isEmpty()) return "";
    return "<div class=\"summary keep\"><div class=\"summary-title\">한눈에 보기</div>%s</div>"
        .formatted(String.join("", parts));
  }

  /** 활동 수치를 가로로 나란히 낸다. 집계하지 못한 값은 칸 자체를 만들지 않는다. */
  private String summaryStats() {
    List<String[]> cells = new ArrayList<>();
    ReportActivityFactsResponse facts = report.activityFacts();
    if (facts != null) {
      if (facts.drawingDurationSec() != null && facts.drawingDurationSec() > 0) {
        cells.add(new String[] {"그린 시간", durationText(facts.drawingDurationSec())});
      }
      if (facts.pauseCount() != null) {
        cells.add(new String[] {"멈춤", countText(facts.pauseCount())});
      }
      if (facts.eraseCount() != null) {
        cells.add(new String[] {"지우기", countText(facts.eraseCount())});
      }
    }
    if (report.conversationSummary() != null) {
      if (report.conversationSummary().questionCount() != null) {
        cells.add(new String[] {"질문", countText(report.conversationSummary().questionCount())});
      }
      if (report.conversationSummary().answeredCount() != null) {
        cells.add(new String[] {"대답", countText(report.conversationSummary().answeredCount())});
      }
    }
    if (cells.isEmpty()) return "";
    StringBuilder values = new StringBuilder();
    StringBuilder labels = new StringBuilder();
    for (String[] cell : cells) {
      values.append("<td class=\"stat-value\">").append(escape(cell[1])).append("</td>");
      labels.append("<td class=\"stat-label\">").append(escape(cell[0])).append("</td>");
    }
    // 값과 라벨을 같은 표에 두면 열 폭이 함께 맞고, 표는 행 단위로만 나뉘어 값과 라벨이 흩어지지 않는다.
    return "<table class=\"stat keep\"><tr>%s</tr><tr>%s</tr></table>".formatted(values, labels);
  }

  /**
   * 아이가 그린 것을 표지에 싣는다.
   *
   * <p>집·나무·사람 활동은 <b>대표 한 장을 고르지 않는다</b>. 한 장만 올리면 그 그림이 대표처럼 읽히고, 나머지 두 장은 뒤에 묻힌다. 세 장을 같은 크기로
   * 나란히 두고, 각 그림을 관찰 서술과 함께 보는 것은 본문 주제 카드에서 한다.
   */
  private String coverDrawing() {
    if (isHtpActivity()) return coverSubjectStrip();
    return image(heroDrawingUrl(), COVER_IMAGE_MAX_HEIGHT_MM, "아이가 그린 그림");
  }

  /**
   * 표지에 크게 실은 그림의 URL 이다. 없으면 {@code null}.
   *
   * <p>주제 카드가 <b>같은 그림을 또 싣지 않도록</b> 판단 기준으로도 쓴다. 그림일기·자유 그림은 완성본 한 장이 주제 그림과 같은 파일이라, 그대로 두면 표지와
   * 본문에 똑같은 그림이 두 번 나온다.
   *
   * <p>집·나무·사람은 이 값을 쓰지 않는다 — 표지는 작은 세 장을 나란히 보여 주는 자리이고, 주제 카드의 확대 그림은 관찰 서술과 함께 읽는 자리라 역할이 다르다.
   */
  private String heroDrawingUrl() {
    if (isHtpActivity() || report.drawing() == null) return null;
    return report.drawing().finalImageUrl();
  }

  /** 주제 그림을 계약 순서(집→나무→사람)대로 나란히 놓는다. 읽어 두지 못한 그림은 칸을 만들지 않는다. */
  private String coverSubjectStrip() {
    StringBuilder cells = new StringBuilder();
    int count = 0;
    for (ReportSubjectResponse subject : nullSafe(report.subjectReports())) {
      ReportImageAsset asset = subject.imageUrl() == null ? null : images.get(subject.imageUrl());
      if (asset == null) continue;
      count++;
      cells
          .append("<td>")
          .append(sizedImage(asset, STRIP_IMAGE_WIDTH_MM, STRIP_IMAGE_MAX_HEIGHT_MM))
          .append("<div class=\"figure-caption\">")
          .append(escape(subjectTitle(subject.subjectType())))
          .append("</div></td>");
    }
    if (count == 0) return "";
    return "<div class=\"summary-label\">이번에 그린 그림</div><table class=\"strip keep\"><tr>%s</tr></table>"
        .formatted(cells);
  }

  // ── 본문 ────────────────────────────────────────────────────────────

  /** 화면(875 §11)과 같은 순서로 섹션을 쌓는다. 비어 있는 섹션은 그리지 않는다 — 오류가 아니다. */
  private String body() {
    StringBuilder body = new StringBuilder();
    boolean htp = isHtpActivity();
    if (htp) {
      // 집·나무·사람은 화면과 같은 제목·순서를 쓴다(S15P11B209-960/961). CLAUDE.md 5절 —
      //   집·나무·사람 그리기를 '검사'로 표현하지 않는다. 화면만 바꾸고 PDF 를 두면 보호자가
      //   저장해 남기는 쪽에만 검사 투가 남는다.
      section(body, "한눈에 보는 이번 활동", activityInfoCards());
      section(body, "집·나무·사람, 하나씩 살펴봐요", htpSubjectCards());
      section(body, "아이의 표현과 대화 요약", expressionCards());
      section(body, "대화 요약", conversationCards());
      section(body, "이런 모습이 보였어요", observedFeatureCards());
      section(body, "함께 살펴보면 좋을 이야기", interpretationCards());
      section(body, "그리는 동안 있었던 일", activityFactCards());
    } else {
      section(body, "활동 정보", activityInfoCards());
      section(body, "주요 심리 경향", interpretationCards());
      section(body, "주제별 관찰", subjectCards());
      section(body, "아이의 표현", expressionCards());
      section(body, "이런 모습이 보였어요", observedFeatureCards());
      section(body, "활동 기록", activityFactCards());
      section(body, "대화 요약", conversationCards());
    }
    section(body, "보호자 대화 안내", bulletCards(report.guardianConversationGuide()));
    for (ReportParentGuideResponse guide : nullSafe(report.parentGuides())) {
      section(body, guideTitle(guide.guideType()), bulletCards(guide.items()));
    }
    // 위기 안내는 인쇄물이 제3자에게 노출될 수 있어 본문에 싣지 않는다. 확인 경로만 남긴다.
    if (report.crisisAlert() != null) {
      section(body, "안전 안내", List.of(card("보호자 화면에서 안전 안내를 확인해 주세요.")));
    }
    section(body, "주의 사항", bulletCards(report.limitations()));
    section(body, "참고 자료", referenceCards());
    return body.toString();
  }

  /**
   * 섹션 하나를 쌓는다.
   *
   * <p>제목과 첫 카드를 한 묶음으로 묶는다. 제목만 장 끝에 남으면 다음 장 첫 카드가 무슨 섹션인지 알 수 없다. 나머지 카드는 각자 쪼개지지 않을 뿐, 어느 장에
   * 놓이든 상관없다.
   */
  private void section(StringBuilder body, String title, List<String> cards) {
    if (cards.isEmpty()) return;
    body.append("<div class=\"section\"><div class=\"keep\">");
    body.append("<h2 class=\"section-title\">").append(escape(title)).append("</h2>");
    body.append(cards.get(0)).append("</div>");
    for (int index = 1; index < cards.size(); index++) {
      body.append(cards.get(index));
    }
    body.append("</div>");
  }

  private List<String> activityInfoCards() {
    if (report.drawingSession() == null) return List.of();
    List<String[]> rows = new ArrayList<>();
    rows.add(new String[] {"활동", value(report.drawingSession().drawingTypeName())});
    rows.add(new String[] {"제목", value(report.drawingSession().title())});
    rows.add(new String[] {"입력 방식", value(report.drawingSession().inputMethod())});
    rows.add(new String[] {"생성 상태", value(report.reportStatus())});
    return List.of(card(keyValueTable(rows, "kv")));
  }

  private List<String> interpretationCards() {
    if (nullSafe(report.publicInterpretations()).isEmpty()) return List.of();
    Map<Integer, String> evidenceTexts = new LinkedHashMap<>();
    for (ReportEvidenceItemResponse evidence : nullSafe(report.evidenceItems())) {
      evidenceTexts.put(evidence.evidenceId(), evidence.text());
    }
    List<String> cards = new ArrayList<>();
    for (ReportPublicInterpretationResponse interpretation : report.publicInterpretations()) {
      StringBuilder content = new StringBuilder();
      content.append(cardTitle(value(interpretation.title())));
      content.append("<p>").append(escape(value(interpretation.tendencyText()))).append("</p>");
      // 경향 문장만 단독으로 싣지 않는다(875 §3). 범위와 살펴볼 점을 함께 낸다.
      List<String[]> notes = new ArrayList<>();
      notes.add(new String[] {"범위", value(interpretation.scopeText())});
      notes.add(new String[] {"살펴볼 점", value(interpretation.homeObservationGuide())});
      for (Integer evidenceRef : nullSafe(interpretation.evidenceRefs())) {
        String evidenceText = evidenceTexts.get(evidenceRef);
        if (evidenceText != null) notes.add(new String[] {"근거", evidenceText});
      }
      content.append(keyValueTable(notes, "kv note"));
      cards.add(card(content.toString()));
    }
    return cards;
  }

  /**
   * 주제 묶음 앞에 읽는 법을 먼저 둔다.
   *
   * <p>안내문이 없으면 관찰 문장이 곧바로 평가처럼 읽힌다. 문구는 앱 화면과 같은 것을 쓴다.
   */
  private List<String> htpSubjectCards() {
    List<String> cards = subjectCards();
    if (cards.isEmpty()) {
      // 안내문만 남은 빈 섹션을 그리지 않는다(875 §10).
      return List.of();
    }
    List<String> withGuide = new ArrayList<>();
    withGuide.add(
        card(
            "<p class=\"lead\">세 가지를 그리는 동안 아이가 무엇을 그렸고 어떤 이야기를 들려줬는지 모았어요."
                + " 잘 그렸는지 가리거나 결과를 매기는 자리가 아니라, 아이와 함께 다시 펼쳐 볼 이야깃거리예요.</p>"));
    withGuide.addAll(cards);
    return withGuide;
  }

  private List<String> subjectCards() {
    if (nullSafe(report.subjectReports()).isEmpty()) return List.of();
    List<String> cards = new ArrayList<>();
    for (ReportSubjectResponse subject : report.subjectReports()) {
      StringBuilder content = new StringBuilder();
      content.append(cardTitle(subjectTitle(subject.subjectType())));
      // 표지에 이미 크게 실은 그림이면 다시 싣지 않는다.
      if (!Objects.equals(subject.imageUrl(), heroDrawingUrl())) {
        content.append(image(subject.imageUrl(), SUBJECT_IMAGE_MAX_HEIGHT_MM, null));
      }
      content.append(bulletList(subject.visionObservations()));
      for (ReportQaPairResponse pair : nullSafe(subject.qaPairs())) {
        content.append(qaPair(pair));
      }
      cards.add(card(content.toString()));
    }
    return cards;
  }

  /** 질문과 답을 한 묶음으로 낸다. 갈라지면 답이 어느 질문의 답인지 알 수 없다. */
  private String qaPair(ReportQaPairResponse pair) {
    StringBuilder qa = new StringBuilder("<div class=\"qa keep\">");
    qa.append("<p class=\"q\">").append(escape(value(pair.question()))).append("</p>");
    // 건너뛴 질문을 "-" 로 두면 답을 못 읽은 것인지 안 한 것인지 구분되지 않는다.
    //   화면과 같은 문구를 쓴다(875 §6).
    if (SKIPPED_STATE.equals(pair.state()) || pair.answer() == null) {
      qa.append("<p class=\"a skipped\">이 질문은 건너뛰었어요</p>");
    } else {
      qa.append("<p class=\"a\">").append(escape(pair.answer())).append("</p>");
      // 미확정 음성은 발화를 지우지 않고 확인 요청만 덧붙인다(875 §6-1).
      if (pair.sttNeedsConfirmation()) {
        qa.append("<p class=\"caption\">음성 인식 내용을 확인해 주세요</p>");
      }
    }
    return qa.append("</div>").toString();
  }

  private List<String> expressionCards() {
    if (report.childExpression() == null) return List.of();
    StringBuilder content = new StringBuilder();
    content.append(emotionChips());
    if (has(report.childExpression().expressedEmotionText())) {
      content.append("<p>").append(escape(report.childExpression().expressedEmotionText()));
      content.append("</p>");
    }
    List<ReportUtteranceResponse> utterances =
        nullSafe(report.childExpression().representativeUtterances());
    for (ReportUtteranceResponse utterance : utterances) {
      // 말이 비어 있는 대표 발화는 인용하지 않는다. "-" 로 찍으면 아이가 그렇게 말한 것처럼
      //   보이고, 실제 리포트에서 빈 인용 한 줄이 그렇게 나왔다(리포트 145).
      if (!has(utterance.text())) continue;
      content.append("<p class=\"quote\">").append(escape(utterance.text())).append("</p>");
    }
    return content.isEmpty() ? List.of() : List.of(card(content.toString()));
  }

  /** 아이가 고른 감정을 아이콘과 이름으로 낸다. 아이콘이 없는 감정은 이름만 낸다. */
  private String emotionChips() {
    if (report.childExpression() == null) return "";
    List<String> emotions = nullSafe(report.childExpression().selectedEmotions());
    if (emotions.isEmpty()) return "";
    StringBuilder chips = new StringBuilder("<div class=\"chips\">");
    for (String emotion : emotions) {
      chips.append("<span class=\"chip emotion\">");
      Optional<String> icon =
          ReportPdfEmotionIcon.of(emotion).flatMap(ReportPdfEmotionIcon::dataUri);
      if (icon.isPresent()) {
        chips.append("<img class=\"emotion-icon\" src=\"").append(icon.get()).append("\" />");
      }
      chips.append(escape(ReportPdfEmotionIcon.labelOf(emotion))).append("</span>");
    }
    return chips.append("</div>").toString();
  }

  private List<String> observedFeatureCards() {
    List<String> cards = new ArrayList<>();
    for (ReportObservedFeatureResponse feature : nullSafe(report.observedFeatures())) {
      StringBuilder content = new StringBuilder();
      content.append(cardTitle(value(feature.title())));
      content.append("<p>").append(escape(value(feature.description()))).append("</p>");
      if (has(feature.evidenceSummary())) {
        // 배열 하나를 List.of 에 그대로 주면 요소가 낱개로 펼쳐진다. 행 하나임을 못박는다.
        content.append(
            keyValueTable(
                List.<String[]>of(new String[] {"근거", feature.evidenceSummary()}), "kv note"));
      }
      cards.add(card(content.toString()));
    }
    return cards;
  }

  private List<String> activityFactCards() {
    if (report.activityFacts() == null) return List.of();
    StringBuilder content = new StringBuilder();
    content.append(chipList(report.activityFacts().detectedObjects()));
    // 값의 출처가 VLM 관찰 서술로 바뀌었다(S15P11B209-912). 라벨도 화면과 같은 표현을 쓴다.
    List<String[]> rows = new ArrayList<>();
    rows.add(new String[] {"그린 시간", durationText(report.activityFacts().drawingDurationSec())});
    rows.add(new String[] {"멈춤 횟수", countText(report.activityFacts().pauseCount())});
    rows.add(new String[] {"지우기 횟수", countText(report.activityFacts().eraseCount())});
    content.append(keyValueTable(rows, "kv"));
    for (String note : nullSafe(report.activityFacts().notes())) {
      content.append("<p class=\"caption\">").append(escape(note)).append("</p>");
    }
    return List.of(card(content.toString()));
  }

  private List<String> conversationCards() {
    if (report.conversationSummary() == null || !has(report.conversationSummary().summary())) {
      return List.of();
    }
    return List.of(card("<p>" + escape(report.conversationSummary().summary()) + "</p>"));
  }

  private List<String> referenceCards() {
    if (nullSafe(report.references()).isEmpty()) return List.of();
    StringBuilder content = new StringBuilder("<ul class=\"bullets\">");
    for (ReportReferenceResponse reference : report.references()) {
      content.append("<li>").append(escape(value(reference.title())));
      if (has(reference.url())) {
        content
            .append("<span class=\"caption url\">")
            .append(escape(reference.url()))
            .append("</span>");
      }
      content.append("</li>");
    }
    return List.of(card(content.append("</ul>").toString()));
  }

  private List<String> bulletCards(List<String> items) {
    List<String> values = nullSafe(items);
    return values.isEmpty() ? List.of() : List.of(card(bulletList(values)));
  }

  // ── 조각 ────────────────────────────────────────────────────────────

  /** 카드 하나다. 카드는 장 경계에서 쪼개지지 않는다 — 한 장보다 긴 카드만 예외로 나뉜다. */
  private String card(String innerHtml) {
    return "<div class=\"card keep\">" + innerHtml + "</div>";
  }

  private String cardTitle(String title) {
    return "<h3 class=\"card-title\">" + escape(title) + "</h3>";
  }

  private String bulletList(List<String> items) {
    List<String> values = nullSafe(items);
    if (values.isEmpty()) return "";
    StringBuilder list = new StringBuilder("<ul class=\"bullets\">");
    for (String item : values) {
      list.append("<li>").append(escape(value(item))).append("</li>");
    }
    return list.append("</ul>").toString();
  }

  private String chipList(List<String> items) {
    List<String> values = nullSafe(items);
    if (values.isEmpty()) return "";
    StringBuilder chips = new StringBuilder("<div class=\"chips\">");
    for (String item : values) {
      chips.append("<span class=\"chip\">").append(escape(item)).append("</span>");
    }
    return chips.append("</div>").toString();
  }

  /** 라벨과 값을 한 행에 둔다. 표는 행 단위로만 나뉘어 라벨만 장 끝에 남지 않는다. */
  private String keyValueTable(List<String[]> rows, String className) {
    if (rows.isEmpty()) return "";
    StringBuilder table = new StringBuilder("<table class=\"").append(className).append("\">");
    for (String[] row : rows) {
      table.append("<tr><th>").append(escape(row[0])).append("</th>");
      table.append("<td>").append(escape(value(row[1]))).append("</td></tr>");
    }
    return table.append("</table>").toString();
  }

  /**
   * 그림을 종이 폭에 맞춰 배치한다. 읽어 두지 못한 그림은 자리도 만들지 않는다.
   *
   * <p>크기를 지정하지 않으면 openhtmltopdf 가 픽셀을 그대로 포인트로 읽어 그림이 종이를 넘는다. 원본 비율로 폭·높이를 계산해 <b>둘 다</b> 지정한다 —
   * 한쪽만 주면 비율이 어긋나 찌그러진다.
   *
   * @param fileUrl 리포트 응답의 그림 URL 이며 {@code null} 이면 빈 문자열
   * @param maxHeightMm 배치 높이 상한
   * @param caption 그림 아래 설명이며 없으면 {@code null}
   */
  private String image(String fileUrl, double maxHeightMm, String caption) {
    ReportImageAsset asset = fileUrl == null ? null : images.get(fileUrl);
    if (asset == null) return "";
    // 그림과 설명은 한 묶음이다. 설명만 다음 장에 남으면 무엇에 대한 설명인지 알 수 없다.
    StringBuilder figure = new StringBuilder("<div class=\"figure keep\">");
    figure.append(sizedImage(asset, CONTENT_WIDTH_MM, maxHeightMm));
    if (has(caption)) {
      figure.append("<div class=\"figure-caption\">").append(escape(caption)).append("</div>");
    }
    return figure.append("</div>").toString();
  }

  /** 원본 비율을 지키면서 주어진 상한 안에 들어가는 크기로 그림 태그를 만든다. */
  private String sizedImage(ReportImageAsset asset, double maxWidthMm, double maxHeightMm) {
    double widthMm = maxWidthMm;
    double heightMm = widthMm * asset.aspectRatio();
    if (heightMm > maxHeightMm) {
      heightMm = maxHeightMm;
      widthMm = heightMm / asset.aspectRatio();
    }
    // 소수점 구분자가 로케일에 따라 쉼표가 되면 CSS 가 깨진다. 자리 표기를 고정한다.
    return String.format(
        Locale.ROOT,
        "<img class=\"drawing\" style=\"width:%.1fmm;height:%.1fmm\" src=\"data:%s;base64,%s\" />",
        widthMm,
        heightMm,
        asset.mimeType(),
        Base64.getEncoder().encodeToString(asset.bytes()));
  }

  // ── 문구 ────────────────────────────────────────────────────────────

  /**
   * 집·나무·사람 활동인지 판정한다.
   *
   * <p>앱과 <b>같은 기준</b>을 쓴다({@code report_dtos.dart} {@code isHtpActivity}) — 계약 §2 의 최상위 {@code
   * activityType}이 정본이고, 그 필드가 없는 구형 응답은 세션의 활동 코드로 판정한다. 두 곳이 다른 기준을 쓰면 같은 리포트가 화면과 PDF 에서 다른 서식으로
   * 나온다.
   *
   * <p><b>코드값으로만 판정한다.</b> 표시명은 사람이 읽는 문구라 바뀔 수 있고, 문구로 분기하면 이름을 다듬는 순간 서식이 조용히 무너진다.
   */
  private boolean isHtpActivity() {
    if (HTP_ACTIVITY_CODE.equalsIgnoreCase(report.activityType())) {
      return true;
    }
    return report.drawingSession() != null
        && HTP_ACTIVITY_CODE.equalsIgnoreCase(report.drawingSession().drawingTypeCode());
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

  private boolean has(String text) {
    return text != null && !text.isBlank();
  }

  private <T> List<T> nullSafe(List<T> items) {
    return items == null ? List.of() : items;
  }

  /**
   * 문자열을 XHTML 본문에 넣을 수 있게 바꾼다.
   *
   * <p>아이 발화·AI 문장에 {@code <}·{@code &} 가 섞이면 XHTML 파싱이 깨져 <b>리포트 전체가 만들어지지 않는다</b>. 데이터가 문서 구조를 바꿀
   * 수 없게 여기서 한 번에 막는다.
   */
  private String escape(String text) {
    if (text == null) return "";
    StringBuilder escaped = new StringBuilder(text.length());
    for (int index = 0; index < text.length(); index++) {
      char character = text.charAt(index);
      switch (character) {
        case '&' -> escaped.append("&amp;");
        case '<' -> escaped.append("&lt;");
        case '>' -> escaped.append("&gt;");
        case '"' -> escaped.append("&quot;");
        case '\'' -> escaped.append("&#39;");
        default -> escaped.append(character);
      }
    }
    return escaped.toString();
  }

  // ── 스타일 ──────────────────────────────────────────────────────────

  /**
   * 문서 전용 서식이다. 화면 디자인을 옮겨 오지 않는다.
   *
   * <p>화면은 카드마다 색을 채워 손으로 넘기며 보기 좋게 만든 것이다. 그대로 종이에 옮기면 색 면이 넓어 인쇄가 지저분해지고, 카드 안에 카드가 겹쳐 층이 깊어진다.
   * 종이에서는 <b>흰 바탕에 얇은 선</b>으로 층을 나누고, 색은 섹션 제목의 세로선과 강조 몇 군데에만 쓴다.
   *
   * <p>색은 앱 디자인 토큰({@code AppColors})의 값을 그대로 쓴다 — 같은 서비스의 문서라는 것이 색에서 보여야 한다.
   *
   * <p>쪽번호는 <b>페이지 여백 박스</b>({@code @bottom-center})로 낸다. {@code position: fixed} 로 여백에 밀어 넣는 방법은
   * 쓰지 않는다 — 글자가 PDF 에는 남아 텍스트 추출로는 확인되지만 <b>본문 박스에 클립되어 보이지 않는다</b>. 967 스파이크가 그 상태로 통과했고, 968 에서
   * 페이지를 이미지로 그려 보고서야 드러났다.
   */
  private String css() {
    return """
        @page { size: A4; margin: 15mm 14mm 18mm;
                @bottom-center { content: counter(page) " / " counter(pages);
                                 font-family: '%s'; font-size: 8pt; color: #68737D; } }
        body { font-family: '%s'; font-size: 10pt; color: #27313A; line-height: 1.6; }
        p { margin: 0 0 4px 0; }
        .cover { page-break-after: always; }
        .cover-head { width: 100%%; }
        .cover-copy { vertical-align: top; }
        .cover-mascot { width: 36mm; vertical-align: top; text-align: right; }
        .brand { font-size: 9pt; letter-spacing: 2px; color: #5F9E73; margin-bottom: 4mm; }
        h1 { font-size: 22pt; font-weight: bold; margin: 0; }
        .cover-sub { font-size: 13pt; font-weight: bold; color: #27313A; margin-top: 3mm; }
        .cover-lead { color: #68737D; margin-top: 1.5mm; }
        .cover-meta { margin-top: 5mm; }
        .cover-meta th, .cover-meta td { padding: 2px 0; }

        .notice { margin-top: 6mm; border: 1px solid #DDE2DC; border-left: 3px solid #5F9E73;
                  background-color: #F6F7F2; padding: 3mm 4mm; font-size: 9pt; color: #68737D; }

        .summary { margin-top: 6mm; border-top: 1px solid #DDE2DC; padding-top: 4mm; }
        .summary-title { font-size: 12pt; font-weight: bold; margin-bottom: 3mm; }
        .summary-label { font-size: 9pt; color: #68737D; margin: 3mm 0 1.5mm 0; }
        .summary-text { font-size: 10pt; }
        .stat { width: 100%%; margin: 3mm 0; }
        .stat td { text-align: center; }
        .stat-value { font-size: 13pt; font-weight: bold; }
        .stat-label { font-size: 8.5pt; color: #68737D; }

        .section { margin-bottom: 7mm; }
        .section-title { font-size: 13pt; font-weight: bold; margin: 0 0 3mm 0;
                         border-left: 3px solid #5F9E73; padding-left: 3mm; }
        .card { border: 1px solid #DDE2DC; border-radius: 6px; padding: 3.5mm 4mm;
                margin-bottom: 3mm; }
        .card-title { font-size: 11pt; font-weight: bold; margin: 0 0 2mm 0; }
        .lead { color: #68737D; }
        .keep { page-break-inside: avoid; }

        .kv { width: 100%%; }
        .kv th { width: 26mm; text-align: left; font-weight: normal; color: #68737D;
                 vertical-align: top; padding: 1px 3mm 1px 0; }
        .kv td { vertical-align: top; padding: 1px 0; }
        .note { font-size: 9pt; margin-top: 2mm; }
        .note th { width: 20mm; }
        .caption { font-size: 9pt; color: #68737D; }
        .url { display: block; }

        .bullets { margin: 0; padding-left: 5mm; }
        .bullets li { margin-bottom: 1.5mm; }

        .chips { margin-bottom: 2mm; }
        .chip { display: inline-block; border: 1px solid #DDE2DC; border-radius: 10px;
                padding: 1mm 2.5mm; margin: 0 1.5mm 1.5mm 0; font-size: 9pt; }
        .emotion { background-color: #F6F7F2; }
        .emotion-icon { width: 5mm; height: 5mm; margin-right: 1mm; vertical-align: middle; }

        .qa { margin-top: 2.5mm; }
        .q { font-weight: bold; }
        .a { color: #27313A; }
        .skipped { color: #68737D; }
        .quote { border-left: 2px solid #DDE2DC; padding-left: 3mm; color: #27313A;
                 margin-bottom: 2mm; }

        .figure { margin: 2mm 0 3mm 0; text-align: center; }
        .drawing { display: block; border: 1px solid #DDE2DC; border-radius: 4px;
                   margin-left: auto; margin-right: auto; }
        .figure-caption { font-size: 8.5pt; color: #68737D; margin-top: 1.5mm;
                          text-align: center; }
        .strip { width: 100%%; margin: 1.5mm 0 3mm 0; }
        .strip td { width: 33%%; vertical-align: top; padding: 0 1.5mm; }
        """
        .formatted(FONT_FAMILY, FONT_FAMILY);
  }
}
