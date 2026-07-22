package com.ssafy.b209.child.controller;

import static org.mockito.BDDMockito.given;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.ssafy.b209.child.domain.ChildProfileStatus;
import com.ssafy.b209.child.domain.ChildTutorialStatus;
import com.ssafy.b209.child.domain.QuestionDifficulty;
import com.ssafy.b209.child.dto.response.ChildDetailResponse;
import com.ssafy.b209.child.exception.ChildErrorCode;
import com.ssafy.b209.child.service.ChildQueryService;
import com.ssafy.b209.conversation.exception.ConversationStartErrorCode;
import com.ssafy.b209.conversation.service.TemporaryGuardianResolver;
import com.ssafy.b209.global.exception.BusinessException;
import java.time.Instant;
import java.time.LocalDate;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.context.annotation.Import;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

@WebMvcTest(ChildController.class)
@Import(com.ssafy.b209.global.exception.GlobalExceptionHandler.class)
class ChildControllerTest {

  @Autowired private MockMvc mockMvc;
  @MockitoBean private ChildQueryService childQueryService;
  @MockitoBean private TemporaryGuardianResolver guardianResolver;

  @Test
  void returnsTheConnectedChildDetailInTheCommonResponse() throws Exception {
    given(guardianResolver.resolve("Bearer access-token", "10")).willReturn(10L);
    given(childQueryService.getChild(10L, 3L)).willReturn(response());

    mockMvc
        .perform(
            get("/api/v1/children/3")
                .header("Authorization", "Bearer access-token")
                .header("X-Guardian-User-Id", "10"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.success").value(true))
        .andExpect(jsonPath("$.code").value("COMMON_200"))
        .andExpect(jsonPath("$.data.childId").value(3))
        .andExpect(jsonPath("$.data.nickname").value("별이"))
        .andExpect(jsonPath("$.data.age").value(7))
        .andExpect(jsonPath("$.data.questionDifficulty").value("LOWER_ELEMENTARY"))
        .andExpect(jsonPath("$.data.responseModes[0]").value("VOICE"))
        .andExpect(jsonPath("$.data.relationshipType").value("MOTHER"));
  }

  @Test
  void rejectsANonPositiveChildIdBeforeCallingTheService() throws Exception {
    mockMvc
        .perform(
            get("/api/v1/children/0")
                .header("Authorization", "Bearer access-token")
                .header("X-Guardian-User-Id", "10"))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.code").value("COMMON_400_001"));
  }

  @Test
  void returnsUnauthorizedWhenTemporaryAuthenticationHeadersAreMissing() throws Exception {
    given(guardianResolver.resolve(null, null))
        .willThrow(new BusinessException(ConversationStartErrorCode.UNAUTHORIZED));

    mockMvc
        .perform(get("/api/v1/children/3"))
        .andExpect(status().isUnauthorized())
        .andExpect(jsonPath("$.code").value("UNAUTHORIZED"));
  }

  @Test
  void doesNotRevealWhetherAnUnqueryableChildExists() throws Exception {
    given(guardianResolver.resolve("Bearer access-token", "10")).willReturn(10L);
    given(childQueryService.getChild(10L, 99L))
        .willThrow(new BusinessException(ChildErrorCode.CHILD_NOT_FOUND));

    mockMvc
        .perform(
            get("/api/v1/children/99")
                .header("Authorization", "Bearer access-token")
                .header("X-Guardian-User-Id", "10"))
        .andExpect(status().isNotFound())
        .andExpect(jsonPath("$.code").value("CHILD_404_001"));
  }

  private ChildDetailResponse response() {
    return new ChildDetailResponse(
        3L,
        "별이",
        LocalDate.of(2019, 3, 15),
        7,
        null,
        "MONGLE",
        QuestionDifficulty.LOWER_ELEMENTARY,
        List.of("VOICE", "EMOJI"),
        ChildTutorialStatus.NOT_STARTED,
        ChildProfileStatus.ACTIVE,
        "MOTHER",
        Instant.parse("2026-07-21T02:30:00Z"),
        Instant.parse("2026-07-21T02:30:00Z"));
  }
}
