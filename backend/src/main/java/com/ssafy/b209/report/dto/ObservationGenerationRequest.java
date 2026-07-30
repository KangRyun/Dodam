package com.ssafy.b209.report.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;
import jakarta.validation.constraints.PositiveOrZero;
import java.util.List;

/**
 * Spring Boot가 관찰 리포트 생성 AI에 전달하는 최종 분석 요청 계약이다.
 *
 * <p>아동 이름·생년월일 등 식별 개인정보와 이미지·음성 원문은 포함하지 않고, 관찰에 필요한 집계 수치와 비민감 맥락만 전달한다.
 *
 * @param requestId 호출 추적과 응답 연결에 사용하는 요청 식별자
 * @param analysisId 최종 분석 식별자
 * @param drawingSessionId 그림 활동 세션 식별자
 * @param analysisType 수행할 분석 유형이며 최종 분석은 {@code FINAL}
 * @param questionDifficulty 대화 시작 시점 질문 난이도 Snapshot이며 없으면 {@code null}
 * @param questionCount 실제 제시한 질문 수
 * @param answeredCount 실제 응답한 답변 수
 * @param skippedCount 건너뛴 질문 수
 * @param unrecognizedSpeechCount 음성 인식에 실패한 답변 수
 * @param selectedEmotions 아동이 선택한 감정 코드 목록
 * @param expressedEmotionText 아동이 직접 표현한 감정 문구이며 없으면 {@code null}
 * @param representativeUtterance 대표 발화이며 없으면 {@code null}
 * @param subjectSummaries 주제별 그림 서술·문답 묶음이며 HTP는 최대 3건(집·나무·사람), 그림일기는 1건 (S15P11B209-740)
 */
public record ObservationGenerationRequest(
    @NotBlank String requestId,
    @NotNull @Positive Long analysisId,
    @NotNull @Positive Long drawingSessionId,
    @NotBlank String analysisType,
    String questionDifficulty,
    @PositiveOrZero int questionCount,
    @PositiveOrZero int answeredCount,
    @PositiveOrZero int skippedCount,
    @PositiveOrZero int unrecognizedSpeechCount,
    List<String> selectedEmotions,
    String expressedEmotionText,
    String representativeUtterance,
    List<SubjectSummary> subjectSummaries) {

  /** {@code subjectSummaries}가 {@code null}로 만들어져도 빈 목록으로 정규화한다(계약: optional·기본 빈 목록). */
  public ObservationGenerationRequest {
    subjectSummaries = subjectSummaries == null ? List.of() : List.copyOf(subjectSummaries);
  }

  /**
   * 주제(집/나무/사람 또는 그림일기 단일 그림) 하나의 관찰 서술·문답 묶음이다 (S15P11B209-740).
   *
   * <p>AI 계약({@code docs/ai/ai-observation-report-contract.md})과 1:1 — 필드 변경은 양쪽 동시 반영.
   *
   * @param drawingSubject HTP 주제({@code HOUSE|TREE|PERSON})이며 그림일기는 {@code null}
   * @param drawingDescription 해당 그림의 VLM 관찰 서술이며 없으면 {@code null}
   * @param detectedObjectCodes 탐지 객체 내부 코드 목록(프롬프트 참고용)
   * @param qaPairs 해당 그림 대화에서 나눈 질문·답변 목록
   */
  public record SubjectSummary(
      String drawingSubject,
      String drawingDescription,
      List<String> detectedObjectCodes,
      List<SubjectQaPair> qaPairs) {

    public SubjectSummary {
      detectedObjectCodes =
          detectedObjectCodes == null ? List.of() : List.copyOf(detectedObjectCodes);
      qaPairs = qaPairs == null ? List.of() : List.copyOf(qaPairs);
    }
  }

  /**
   * 주제별 문답 한 쌍이다.
   *
   * <p>{@code answerText}는 아이 발화(STT 텍스트·선택 칩 라벨) — 로그·예외 메시지에 원문을 남기지 않는다(가드레일 9절).
   *
   * @param question AI가 물은 질문 텍스트
   * @param answerText 아이 답변이며 없으면 {@code null}
   * @param answerType 답변 메시지 유형(예: VOICE·OPTION·SKIPPED)이며 없으면 {@code null}
   */
  public record SubjectQaPair(String question, String answerText, String answerType) {}
}
