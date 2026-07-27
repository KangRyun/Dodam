package com.ssafy.b209.global.response;

import static org.assertj.core.api.Assertions.assertThat;

import com.ssafy.b209.analysis.exception.DrawingAnalysisErrorCode;
import com.ssafy.b209.auth.exception.AuthErrorCode;
import com.ssafy.b209.child.exception.ChildErrorCode;
import com.ssafy.b209.community.exception.CommunityErrorCode;
import com.ssafy.b209.community.exception.CommunityPostDetailErrorCode;
import com.ssafy.b209.consent.exception.ConsentErrorCode;
import com.ssafy.b209.conversation.exception.ConversationEndErrorCode;
import com.ssafy.b209.conversation.exception.ConversationErrorCode;
import com.ssafy.b209.conversation.exception.ConversationMessageAudioErrorCode;
import com.ssafy.b209.conversation.exception.ConversationMessageListErrorCode;
import com.ssafy.b209.conversation.exception.ConversationMessageStatusErrorCode;
import com.ssafy.b209.conversation.exception.ConversationStartErrorCode;
import com.ssafy.b209.conversation.exception.OptionAnswerErrorCode;
import com.ssafy.b209.conversation.exception.QuestionTtsErrorCode;
import com.ssafy.b209.conversation.exception.SttProcessingErrorCode;
import com.ssafy.b209.conversation.exception.VoiceAnswerErrorCode;
import com.ssafy.b209.drawing.exception.DrawingErrorCode;
import com.ssafy.b209.infrastructure.ai.image.AiImageAccessErrorCode;
import com.ssafy.b209.notification.exception.NotificationErrorCode;
import com.ssafy.b209.report.exception.MockObservationReportErrorCode;
import com.ssafy.b209.storage.audio.AudioStorageErrorCode;
import com.ssafy.b209.storage.image.ImageStorageErrorCode;
import com.ssafy.b209.user.exception.UserErrorCode;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Collectors;
import org.junit.jupiter.api.Test;

class ErrorCodeContractTest {

  private static final Pattern CODE_PATTERN = Pattern.compile("^[A-Z][A-Z0-9_]*$");
  private static final Pattern STRUCTURED_CODE_PATTERN = Pattern.compile("^.+_(\\d{3})_(\\d{3})$");

  @Test
  void duplicateCodesKeepTheSameHttpStatusAndMessage() {
    Map<String, List<ErrorCode>> duplicateCodes =
        allErrorCodes().stream()
            .collect(Collectors.groupingBy(ErrorCode::getCode))
            .entrySet()
            .stream()
            .filter(entry -> entry.getValue().size() > 1)
            .collect(Collectors.toMap(Map.Entry::getKey, Map.Entry::getValue));

    duplicateCodes.forEach(
        (code, definitions) -> {
          assertThat(definitions)
              .as("%s의 HTTP Status는 모든 정의에서 같아야 한다.", code)
              .extracting(ErrorCode::getHttpStatus)
              .containsOnly(definitions.getFirst().getHttpStatus());
          assertThat(definitions)
              .as("%s의 메시지는 모든 정의에서 같아야 한다.", code)
              .extracting(ErrorCode::getMessage)
              .containsOnly(definitions.getFirst().getMessage());
        });
  }

  @Test
  void codesAndMessagesFollowThePublicContract() {
    allErrorCodes()
        .forEach(
            errorCode -> {
              assertThat(errorCode.getCode()).matches(CODE_PATTERN);
              assertThat(errorCode.getMessage()).isNotBlank();

              Matcher matcher = STRUCTURED_CODE_PATTERN.matcher(errorCode.getCode());
              if (matcher.matches()) {
                assertThat(Integer.parseInt(matcher.group(1)))
                    .as("%s의 HTTP 숫자 구간", errorCode.getCode())
                    .isEqualTo(errorCode.getHttpStatus().value());
              }
            });
  }

  private List<ErrorCode> allErrorCodes() {
    List<ErrorCode> errorCodes = new ArrayList<>();
    Collections.addAll(errorCodes, CommonErrorCode.values());
    Collections.addAll(errorCodes, AuthErrorCode.values());
    Collections.addAll(errorCodes, UserErrorCode.values());
    Collections.addAll(errorCodes, ChildErrorCode.values());
    Collections.addAll(errorCodes, ConsentErrorCode.values());
    Collections.addAll(errorCodes, DrawingErrorCode.values());
    Collections.addAll(errorCodes, DrawingAnalysisErrorCode.values());
    Collections.addAll(errorCodes, ConversationStartErrorCode.values());
    Collections.addAll(errorCodes, ConversationErrorCode.values());
    Collections.addAll(errorCodes, ConversationEndErrorCode.values());
    Collections.addAll(errorCodes, ConversationMessageListErrorCode.values());
    Collections.addAll(errorCodes, ConversationMessageStatusErrorCode.values());
    Collections.addAll(errorCodes, ConversationMessageAudioErrorCode.values());
    Collections.addAll(errorCodes, OptionAnswerErrorCode.values());
    Collections.addAll(errorCodes, VoiceAnswerErrorCode.values());
    Collections.addAll(errorCodes, SttProcessingErrorCode.values());
    Collections.addAll(errorCodes, QuestionTtsErrorCode.values());
    Collections.addAll(errorCodes, CommunityErrorCode.values());
    Collections.addAll(errorCodes, CommunityPostDetailErrorCode.values());
    Collections.addAll(errorCodes, NotificationErrorCode.values());
    Collections.addAll(errorCodes, MockObservationReportErrorCode.values());
    Collections.addAll(errorCodes, ImageStorageErrorCode.values());
    Collections.addAll(errorCodes, AudioStorageErrorCode.values());
    Collections.addAll(errorCodes, AiImageAccessErrorCode.values());
    return List.copyOf(errorCodes);
  }
}
