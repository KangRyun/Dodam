package com.ssafy.b209.report.service;

import java.io.IOException;
import java.io.InputStream;
import java.util.Base64;
import java.util.Locale;
import java.util.Optional;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * 리포트 PDF 에 실을 감정 아이콘과 표시명이다.
 *
 * <p>PDF 에는 <b>컬러 이모지를 쓸 수 없다</b>. 문서 폰트(NanumSquareNeo)에는 이모지 글리프가 없어 아이가 고른 감정을 이모지로 찍으면 빈칸이나 두부
 * 문자로 나온다. 그래서 앱이 감정 선택 화면에서 쓰는 것과 <b>같은 PNG 자산</b>을 서버 리소스로 함께 두고 그것을 싣는다(ADR-0003).
 *
 * <p>표시명은 보호자 리포트 화면과 같은 문구를 쓴다({@code report_screen.dart} 의 {@code _emotionLabel}). 두 곳이 다르면 같은
 * 감정이 화면과 저장한 파일에서 다른 이름으로 읽힌다.
 *
 * <p>{@code UNKNOWN}·{@code UNSURE}("잘 모르겠음")에는 아이콘이 없다. 앱에도 없는 그림을 서버에서 만들어 붙이지 않는다 — 아이콘 없이 이름만
 * 낸다.
 */
enum ReportPdfEmotionIcon {
  JOY("기쁨", "/images/emotions/dodam_emotion_joy.png", "HAPPY", "JOY"),
  SAD("슬픔", "/images/emotions/dodam_emotion_sad.png", "SAD"),
  ANGRY("화남", "/images/emotions/dodam_emotion_angry.png", "ANGRY"),
  SCARED("무서움", "/images/emotions/dodam_emotion_anxious.png", "SCARED"),
  CALM("편안함", "/images/emotions/dodam_emotion_calm.png", "CALM");

  private static final Logger log = LoggerFactory.getLogger(ReportPdfEmotionIcon.class);

  /** 아이콘이 없는 감정의 표시명이다. */
  private static final String UNKNOWN_LABEL = "잘 모르겠음";

  private final String label;
  private final String resource;
  private final String[] codes;

  /** 리소스를 읽어 만든 data URI 다. 못 읽었으면 빈 문자열이라 다시 읽지 않는다. */
  private volatile String dataUri;

  ReportPdfEmotionIcon(String label, String resource, String... codes) {
    this.label = label;
    this.resource = resource;
    this.codes = codes;
  }

  /**
   * 감정 코드에 맞는 아이콘을 찾는다.
   *
   * @param code 감정 코드이며 {@code null}·미등록 코드면 빈 값
   * @return 아이콘, 없으면 {@link Optional#empty()}
   */
  static Optional<ReportPdfEmotionIcon> of(String code) {
    if (code == null || code.isBlank()) return Optional.empty();
    String normalized = code.trim().toUpperCase(Locale.ROOT);
    for (ReportPdfEmotionIcon icon : values()) {
      for (String candidate : icon.codes) {
        if (candidate.equals(normalized)) return Optional.of(icon);
      }
    }
    return Optional.empty();
  }

  /**
   * 감정 코드를 보호자 화면과 같은 표시명으로 바꾼다.
   *
   * <p>모르는 코드는 코드 그대로 낸다. 감정 코드가 늘어났을 때 화면에는 나오는 항목이 PDF 에서 사라지는 것보다, 낯선 글자라도 남는 편이 낫다.
   *
   * @param code 감정 코드
   * @return 표시명
   */
  static String labelOf(String code) {
    Optional<ReportPdfEmotionIcon> icon = of(code);
    if (icon.isPresent()) return icon.get().label;
    if (code == null || code.isBlank()) return UNKNOWN_LABEL;
    String normalized = code.trim().toUpperCase(Locale.ROOT);
    return switch (normalized) {
      case "UNKNOWN", "UNSURE" -> UNKNOWN_LABEL;
      default -> code;
    };
  }

  String label() {
    return label;
  }

  /**
   * 아이콘을 {@code <img src>} 에 넣을 data URI 로 만든다.
   *
   * <p>리소스를 못 읽으면 빈 값을 준다. 아이콘 한 개 때문에 리포트 내보내기가 실패하면 보호자는 아무것도 받지 못한다.
   *
   * @return data URI, 못 읽었으면 {@link Optional#empty()}
   */
  Optional<String> dataUri() {
    String cached = dataUri;
    if (cached == null) {
      cached = load();
      dataUri = cached;
    }
    return cached.isEmpty() ? Optional.empty() : Optional.of(cached);
  }

  private String load() {
    try (InputStream stream = ReportPdfEmotionIcon.class.getResourceAsStream(resource)) {
      if (stream == null) {
        log.warn("감정 아이콘 리소스를 찾을 수 없습니다. resource={}", resource);
        return "";
      }
      return "data:image/png;base64," + Base64.getEncoder().encodeToString(stream.readAllBytes());
    } catch (IOException exception) {
      log.warn("감정 아이콘을 읽지 못했습니다. resource={}", resource, exception);
      return "";
    }
  }
}
