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
    String representativeUtterance) {}
