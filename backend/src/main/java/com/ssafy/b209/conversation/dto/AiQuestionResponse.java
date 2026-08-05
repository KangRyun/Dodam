package com.ssafy.b209.conversation.dto;

import com.ssafy.b209.conversation.domain.QuestionPurpose;
import com.ssafy.b209.conversation.domain.ResponseMode;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

/**
 * FastAPI 목표 계약의 성공 응답 DTO다.
 *
 * <p>{@code conversationEndConfirmed}는 "아이가 대화를 그만하겠다고 확인해 줬다"는 사실만 전한다. 턴 제어는 AI 소유가 아니므로
 * (S15P11B209-786) 세션을 끝내는 것은 BE다. 이 값이 {@code true}인 응답도 {@code questionText}는 여전히 되묻기 문장이라, 이 필드를
 * 읽지 않으면 되묻기 질문이 한 번 더 저장되던 이전 동작이 그대로 유지된다.
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
    boolean conversationEndConfirmed) {

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
    boolean optionAllowed = allowedResponseModes.contains(ResponseMode.OPTION);
    if (!optionAllowed) {
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
