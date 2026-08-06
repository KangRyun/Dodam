package com.ssafy.b209.conversation.controller;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.ssafy.b209.auth.exception.AuthErrorCode;
import com.ssafy.b209.conversation.dto.TtsGenerateRequest;
import com.ssafy.b209.conversation.dto.TtsGenerateResponse;
import com.ssafy.b209.conversation.dto.TtsToneProfile;
import com.ssafy.b209.conversation.exception.ConversationMessageStatusErrorCode;
import com.ssafy.b209.conversation.service.GuardianUserResolver;
import com.ssafy.b209.conversation.service.QuestionTtsService;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.global.exception.GlobalExceptionHandler;
import com.ssafy.b209.global.response.ApiResponse;
import java.math.BigDecimal;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.ArgumentCaptor;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

/** 질문 음성 생성 Controller가 인증을 위임하고 요청 검증 실패와 도메인 오류를 올바른 상태로 처리하는지 확인한다. */
@ExtendWith(MockitoExtension.class)
class QuestionTtsControllerTest {
  private static final String AUDIO_URL = "/api/v1/conversation-messages/803/audio";

  @Mock private GuardianUserResolver guardianResolver;
  @Mock private QuestionTtsService questionTtsService;

  private QuestionTtsController controller;
  private MockMvc mockMvc;

  @BeforeEach
  void setUp() {
    controller = new QuestionTtsController(guardianResolver, questionTtsService);
    mockMvc =
        MockMvcBuilders.standaloneSetup(controller)
            .setControllerAdvice(new GlobalExceptionHandler())
            .build();
  }

  @Test
  void delegatesAndReturnsOkBody() {
    when(guardianResolver.resolve("Bearer token", null)).thenReturn(10L);
    TtsGenerateResponse response = new TtsGenerateResponse(AUDIO_URL, null, 1040L, "무엇이 보이니?");
    when(questionTtsService.generate(eq(10L), eq(803L), any(TtsGenerateRequest.class)))
        .thenReturn(response);

    ResponseEntity<ApiResponse<TtsGenerateResponse>> result =
        controller.generate(
            803L, "Bearer token", null, new TtsGenerateRequest("CHILD_FRIENDLY_01", speed()));

    assertThat(result.getStatusCode()).isEqualTo(HttpStatus.OK);
    assertThat(result.getBody()).isNotNull();
    assertThat(result.getBody().data()).isEqualTo(response);
  }

  @Test
  void propagatesNotFoundFailure() {
    when(guardianResolver.resolve(null, "10")).thenReturn(10L);
    when(questionTtsService.generate(eq(10L), eq(803L), any(TtsGenerateRequest.class)))
        .thenThrow(
            new BusinessException(
                ConversationMessageStatusErrorCode.CONVERSATION_MESSAGE_NOT_FOUND));

    assertThatThrownBy(
            () ->
                controller.generate(
                    803L, null, "10", new TtsGenerateRequest("CHILD_FRIENDLY_01", speed())))
        .isInstanceOf(BusinessException.class)
        .extracting("errorCode")
        .isEqualTo(ConversationMessageStatusErrorCode.CONVERSATION_MESSAGE_NOT_FOUND);
  }

  @Test
  void doesNotCallServiceWhenAuthenticationFails() {
    when(guardianResolver.resolve(null, null))
        .thenThrow(new BusinessException(AuthErrorCode.AUTHENTICATION_REQUIRED));

    assertThatThrownBy(
            () ->
                controller.generate(
                    803L, null, null, new TtsGenerateRequest("CHILD_FRIENDLY_01", speed())))
        .isInstanceOf(BusinessException.class);

    verifyNoInteractions(questionTtsService);
  }

  @Test
  void returnsOkAtSpeedBoundaries() throws Exception {
    when(guardianResolver.resolve(any(), any())).thenReturn(10L);
    when(questionTtsService.generate(any(), any(), any()))
        .thenReturn(new TtsGenerateResponse(AUDIO_URL, null, 1040L, "무엇이 보이니?"));

    mockMvc
        .perform(json("803", "{\"voice\":\"CHILD_FRIENDLY_01\",\"speed\":0.8}"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.success").value(true))
        .andExpect(jsonPath("$.data.audioUrl").value(AUDIO_URL));
    ArgumentCaptor<TtsGenerateRequest> requestCaptor =
        ArgumentCaptor.forClass(TtsGenerateRequest.class);
    verify(questionTtsService).generate(eq(10L), eq(803L), requestCaptor.capture());
    assertThat(requestCaptor.getValue().toneProfile())
        .isEqualTo(TtsToneProfile.CHARACTER_DEFAULT_V1);

    mockMvc
        .perform(json("803", "{\"voice\":\"CHILD_FRIENDLY_01\",\"speed\":1.2}"))
        .andExpect(status().isOk());
  }

  @Test
  void rejectsSpeedBelowRange() throws Exception {
    mockMvc
        .perform(json("803", "{\"voice\":\"CHILD_FRIENDLY_01\",\"speed\":0.7}"))
        .andExpect(status().isBadRequest());
  }

  @Test
  void rejectsSpeedAboveRange() throws Exception {
    mockMvc
        .perform(json("803", "{\"voice\":\"CHILD_FRIENDLY_01\",\"speed\":1.3}"))
        .andExpect(status().isBadRequest());
  }

  @Test
  void rejectsInvalidVoiceFormat() throws Exception {
    mockMvc
        .perform(json("803", "{\"voice\":\"child friendly\",\"speed\":1.0}"))
        .andExpect(status().isBadRequest());
  }

  @Test
  void rejectsMissingFields() throws Exception {
    mockMvc.perform(json("803", "{}")).andExpect(status().isBadRequest());
  }

  private org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder json(
      String messageId, String body) {
    return post("/api/v1/conversation-messages/{messageId}/tts", messageId)
        .contentType(org.springframework.http.MediaType.APPLICATION_JSON)
        .content(body);
  }

  private BigDecimal speed() {
    return new BigDecimal("0.95");
  }
}
