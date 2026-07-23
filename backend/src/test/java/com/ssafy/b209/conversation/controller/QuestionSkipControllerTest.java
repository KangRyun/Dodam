package com.ssafy.b209.conversation.controller;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.verify;

import com.ssafy.b209.conversation.dto.QuestionSkipRequest;
import com.ssafy.b209.conversation.dto.QuestionSkipResponse;
import com.ssafy.b209.conversation.dto.SkipReason;
import com.ssafy.b209.conversation.service.GuardianUserResolver;
import com.ssafy.b209.conversation.service.QuestionSkipService;
import com.ssafy.b209.global.response.ApiResponse;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;

/** 질문 건너뛰기 Controller가 보호자를 해석하고 Service 결과를 200 성공 응답으로 반환하는지 검증한다. */
@ExtendWith(MockitoExtension.class)
class QuestionSkipControllerTest {
  private static final long CONVERSATION_ID = 800L;
  private static final long GUARDIAN_ID = 10L;

  @Mock private GuardianUserResolver guardianResolver;
  @Mock private QuestionSkipService questionSkipService;

  private QuestionSkipController controller;

  @BeforeEach
  void setUp() {
    controller = new QuestionSkipController(guardianResolver, questionSkipService);
  }

  @Test
  void resolvesGuardianAndReturnsSkipResultAs200() {
    QuestionSkipRequest request = new QuestionSkipRequest(803L, SkipReason.CHILD_REQUEST, true);
    QuestionSkipResponse serviceResult = new QuestionSkipResponse(803L, true, 5, 10, "DRAWING");
    given(guardianResolver.resolve("Bearer token", null)).willReturn(GUARDIAN_ID);
    given(questionSkipService.skip(GUARDIAN_ID, CONVERSATION_ID, request))
        .willReturn(serviceResult);

    ResponseEntity<ApiResponse<QuestionSkipResponse>> response =
        controller.skip(CONVERSATION_ID, "Bearer token", null, request);

    verify(guardianResolver).resolve("Bearer token", null);
    verify(questionSkipService).skip(GUARDIAN_ID, CONVERSATION_ID, request);
    assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
    assertThat(response.getBody()).isNotNull();
    assertThat(response.getBody().data()).isEqualTo(serviceResult);
  }
}
