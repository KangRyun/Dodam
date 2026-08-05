package com.ssafy.b209.conversation.dto;

import com.ssafy.b209.conversation.domain.QuestionPurpose;
import com.ssafy.b209.conversation.domain.ResponseMode;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

/**
 * FastAPI 목표 계약의 성공 응답 DTO다.
 *
 * <p>아이가 되묻기에 말로 그만하겠다고 답한 사실은 <b>두 필드로 나뉘어</b> 전달된다. 어느 쪽이든 AI는 끝내지 않는다 —
 * 턴 제어는 AI 소유가 아니라는 786 원칙은 그대로이고, 두 값 모두 "아이가 확인해 줬다"는 관찰 보고다. 나뉘는 기준은 <b>누가 그 종료를
 * 실행할 수 있느냐</b>이다.
 *
 * <ul>
 *   <li>{@code conversationEndConfirmed} — 대화만 끝낸다(S15P11B209-947·955). 세션 상태의 주인이 BE라 BE가 직접
 *       {@code CHILD_REQUEST}로 끝내고 {@link com.ssafy.b209.conversation.exception.ConversationErrorCode#CONVERSATION_ALREADY_COMPLETED}로
 *       알린다.
 *   <li>{@code confirmedStopTarget} — 그림 활동까지 끝낸다(S15P11B209-951). 회고 저장·다음 단계는 FE가 쥐고 있어 BE가 대신할 수
 *       없으므로, 신호만 실어 보내고 실행은 FE가 한다.
 * </ul>
 *
 * <p>두 값이 한 응답에 함께 올 수 있다. 그때는 {@code conversationEndConfirmed}가 먼저 처리되어 질문이 저장되지 않는다 — 아이가 답할
 * 질문이 아니기 때문이다.
 */
public record AiQuestionResponse(
    String questionText,
    String questionPurpose,
    List<QuestionOption> options,
    DetectedObject targetObject,
    boolean fallbackUsed,
    SafetyResult safetyResult,
    String modelName,
    String modelVersion,
    String promptVersion,
    int processingTimeMs,
    boolean conversationEndConfirmed,
    String confirmedStopTarget) {

  /** 아이가 되묻기에 말로 그만하겠다고 확인한 대상이다(S15P11B209-951). */
  private static final Set<String> STOP_TARGETS = Set.of("CONVERSATION", "ACTIVITY");

  /**
   * 종료 확인 신호가 없는 기존 응답을 생성한다.
   *
   * <p>947·951 이전 형태를 그대로 쓰는 호출부(테스트·구 목 클라이언트)를 위한 것이다.
   */
  public AiQuestionResponse(
      String questionText,
      String questionPurpose,
      List<QuestionOption> options,
      DetectedObject targetObject,
      boolean fallbackUsed,
      SafetyResult safetyResult,
      String modelName,
      String modelVersion,
      String promptVersion,
      int processingTimeMs) {
    this(
        questionText,
        questionPurpose,
        options,
        targetObject,
        fallbackUsed,
        safetyResult,
        modelName,
        modelVersion,
        promptVersion,
        processingTimeMs,
        false,
        null);
  }

  /** 대화 종료 확인만 싣는 응답을 생성한다(S15P11B209-947·955 형태). */
  public AiQuestionResponse(
      String questionText,
      String questionPurpose,
      List<QuestionOption> options,
      DetectedObject targetObject,
      boolean fallbackUsed,
      SafetyResult safetyResult,
      String modelName,
      String modelVersion,
      String promptVersion,
      int processingTimeMs,
      boolean conversationEndConfirmed) {
    this(
        questionText,
        questionPurpose,
        options,
        targetObject,
        fallbackUsed,
        safetyResult,
        modelName,
        modelVersion,
        promptVersion,
        processingTimeMs,
        conversationEndConfirmed,
        null);
  }

  /** 활동 종료 대상만 싣는 응답을 생성한다(S15P11B209-951 형태). */
  public AiQuestionResponse(
      String questionText,
      String questionPurpose,
      List<QuestionOption> options,
      DetectedObject targetObject,
      boolean fallbackUsed,
      SafetyResult safetyResult,
      String modelName,
      String modelVersion,
      String promptVersion,
      int processingTimeMs,
      String confirmedStopTarget) {
    this(
        questionText,
        questionPurpose,
        options,
        targetObject,
        fallbackUsed,
        safetyResult,
        modelName,
        modelVersion,
        promptVersion,
        processingTimeMs,
        false,
        confirmedStopTarget);
  }

  public boolean isContractValidFor(Set<ResponseMode> allowedResponseModes) {
    if (isBlank(questionText)
        || isBlank(questionPurpose)
        || isBlank(modelName)
        || isBlank(modelVersion)
        || isBlank(promptVersion)
        || processingTimeMs < 0
        || safetyResult == null
        || !"PASSED".equals(safetyResult.status())
        || isBlank(safetyResult.ruleVersion())
        || safetyResult.blockReasonCode() != null
        || !isQuestionPurpose(questionPurpose)) {
      return false;
    }
    if (targetObject != null && !isDetectedObjectValid(targetObject)) {
      return false;
    }
    if (confirmedStopTarget != null && !STOP_TARGETS.contains(confirmedStopTarget)) {
      // 모르는 종료 대상으로 대화를 끝내지 않는다. 계약 위반으로 보고 폴백 질문으로 간다.
      return false;
    }
    boolean optionAllowed = allowedResponseModes.contains(ResponseMode.OPTION);
    if (!optionAllowed) {
      return options == null;
    }
    if (confirmedStopTarget != null) {
      // 종료 확인 응답은 질문이 아니라 맺음말이라 고를 것이 없다(S15P11B209-951).
      return options == null;
    }
    return options != null && !options.isEmpty() && optionsAreValid(options);
  }

  private boolean isQuestionPurpose(String value) {
    try {
      QuestionPurpose.valueOf(value);
      return true;
    } catch (IllegalArgumentException exception) {
      return false;
    }
  }

  private boolean optionsAreValid(List<QuestionOption> values) {
    Set<String> codes = new HashSet<>();
    for (QuestionOption option : values) {
      if (option == null
          || isBlank(option.code())
          || isBlank(option.label())
          || !codes.add(option.code())) {
        return false;
      }
    }
    return true;
  }

  private boolean isDetectedObjectValid(DetectedObject value) {
    return !isBlank(value.objectCode())
        && value.confidence() >= 0
        && value.confidence() <= 1
        && value.boundingBox() != null
        && value.boundingBox().isNormalized();
  }

  private boolean isBlank(String value) {
    return value == null || value.isBlank();
  }
}
