package com.ssafy.b209.infrastructure.ai;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Component;

/**
 * 부팅 완료 시 AI 연동 3종의 실제 동작 모드를 로그로 드러낸다(S15P11B209-722).
 *
 * <p>2026-07-29에 운영 서버가 {@code AI_DRAWING_ANALYSIS_MODE=mock}으로, {@code AI_TTS_MODE}는 미설정(기본값
 * mock)으로 돌고 있었는데 어디에도 그 사실이 남지 않았다. 리포트 생성만 실제 AI였고 그 입력인 탐지는 가짜여서, 보호자에게 나간 관찰 리포트가 아이 그림과 무관한
 * 근거로 만들어졌다. 조용한 mock이 이번 사고의 원인이므로 모드를 부팅 로그에 반드시 남긴다.
 *
 * <p>mock이 하나라도 있으면 WARN으로 올려 배포 로그·알림에서 눈에 걸리게 한다.
 */
@Component
public class AiIntegrationModeReporter {

  private static final Logger log = LoggerFactory.getLogger(AiIntegrationModeReporter.class);
  private static final String MOCK = "mock";

  private final String drawingAnalysisMode;
  private final String observationMode;
  private final String ttsMode;

  /**
   * 설정된 AI 연동 모드를 주입받는다.
   *
   * @param drawingAnalysisMode 그림 분석 클라이언트 모드
   * @param observationMode 관찰 리포트 생성 클라이언트 모드
   * @param ttsMode 질문 TTS 클라이언트 모드
   */
  public AiIntegrationModeReporter(
      @Value("${app.ai.drawing-analysis.mode:}") String drawingAnalysisMode,
      @Value("${app.ai.observation.mode:}") String observationMode,
      @Value("${app.ai.tts.mode:}") String ttsMode) {
    this.drawingAnalysisMode = normalize(drawingAnalysisMode);
    this.observationMode = normalize(observationMode);
    this.ttsMode = normalize(ttsMode);
  }

  /**
   * 부팅 완료 후 모드를 한 줄로 기록한다.
   *
   * <p>mock이 섞여 있으면 WARN, 전부 실제 연동이면 INFO다.
   */
  @EventListener(ApplicationReadyEvent.class)
  public void reportModes() {
    String summary =
        "AI 연동 모드 — drawingAnalysis=%s observation=%s tts=%s"
            .formatted(drawingAnalysisMode, observationMode, ttsMode);
    if (hasMock()) {
      log.warn("⚠️ {} · mock 은 실제 AI를 호출하지 않는다. 운영이라면 환경변수를 확인할 것.", summary);
      return;
    }
    log.info("{}", summary);
  }

  /**
   * mock으로 동작하는 연동이 있는지 알린다.
   *
   * @return 셋 중 하나라도 mock이면 {@code true}
   */
  public boolean hasMock() {
    return MOCK.equals(drawingAnalysisMode) || MOCK.equals(observationMode) || MOCK.equals(ttsMode);
  }

  private static String normalize(String mode) {
    return mode == null || mode.isBlank() ? "(미설정)" : mode.trim().toLowerCase();
  }
}
