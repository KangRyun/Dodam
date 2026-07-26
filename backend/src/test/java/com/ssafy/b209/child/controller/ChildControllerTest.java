package com.ssafy.b209.child.controller;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.BDDMockito.given;
import static org.mockito.BDDMockito.willThrow;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.ssafy.b209.child.domain.ChildProfileStatus;
import com.ssafy.b209.child.domain.ChildTutorialStatus;
import com.ssafy.b209.child.domain.GuardianRelationshipType;
import com.ssafy.b209.child.domain.QuestionDifficulty;
import com.ssafy.b209.child.domain.ResponseMode;
import com.ssafy.b209.child.dto.request.DeleteChildRequest;
import com.ssafy.b209.child.dto.response.ChildDetailResponse;
import com.ssafy.b209.child.dto.response.ChildRegistrationResponse;
import com.ssafy.b209.child.dto.response.ChildSummaryResponse;
import com.ssafy.b209.child.exception.ChildErrorCode;
import com.ssafy.b209.child.service.ChildDeletionService;
import com.ssafy.b209.child.service.ChildQueryService;
import com.ssafy.b209.child.service.ChildRegistrationService;
import com.ssafy.b209.child.service.ChildUpdateService;
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
import org.springframework.http.MediaType;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

@WebMvcTest(ChildController.class)
@Import(com.ssafy.b209.global.exception.GlobalExceptionHandler.class)
class ChildControllerTest {

  @Autowired private MockMvc mockMvc;
  @MockitoBean private ChildQueryService childQueryService;
  @MockitoBean private ChildRegistrationService childRegistrationService;
  @MockitoBean private ChildUpdateService childUpdateService;
  @MockitoBean private ChildDeletionService childDeletionService;
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

  @Test
  void registersAChildAndReturnsTheCreatedResourceLocation() throws Exception {
    given(guardianResolver.resolve("Bearer access-token", "10")).willReturn(10L);
    given(childRegistrationService.register(eq(10L), any())).willReturn(registrationResponse());

    mockMvc
        .perform(
            post("/api/v1/children")
                .header("Authorization", "Bearer access-token")
                .header("X-Guardian-User-Id", "10")
                .contentType(MediaType.APPLICATION_JSON)
                .content(registrationRequestJson()))
        .andExpect(status().isCreated())
        .andExpect(header().string("Location", "/api/v1/children/3"))
        .andExpect(jsonPath("$.success").value(true))
        .andExpect(jsonPath("$.code").value("COMMON_201"))
        .andExpect(jsonPath("$.data.childId").value(3))
        .andExpect(jsonPath("$.data.age").value(7))
        .andExpect(jsonPath("$.data.relationshipType").value("MOTHER"))
        .andExpect(jsonPath("$.data.responseModes[0]").value("VOICE"))
        .andExpect(jsonPath("$.data.tutorialStatus").value("NOT_STARTED"))
        .andExpect(jsonPath("$.data.profileStatus").value("ACTIVE"));
  }

  @Test
  void rejectsARegistrationMissingRequiredFieldsBeforeCallingTheService() throws Exception {
    mockMvc
        .perform(
            post("/api/v1/children")
                .header("Authorization", "Bearer access-token")
                .header("X-Guardian-User-Id", "10")
                .contentType(MediaType.APPLICATION_JSON)
                .content(
                    """
                    {
                      "nickname": "",
                      "relationshipType": "MOTHER",
                      "questionDifficulty": "LOWER_ELEMENTARY",
                      "responseModes": ["VOICE"]
                    }
                    """))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.code").value("COMMON_400_001"));
  }

  @Test
  void surfacesTheAgeOutOfRangeErrorFromTheService() throws Exception {
    given(guardianResolver.resolve("Bearer access-token", "10")).willReturn(10L);
    given(childRegistrationService.register(eq(10L), any()))
        .willThrow(new BusinessException(ChildErrorCode.CHILD_AGE_OUT_OF_RANGE));

    mockMvc
        .perform(
            post("/api/v1/children")
                .header("Authorization", "Bearer access-token")
                .header("X-Guardian-User-Id", "10")
                .contentType(MediaType.APPLICATION_JSON)
                .content(registrationRequestJson()))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.code").value("CHILD_400_001"));
  }

  @Test
  void returnsUnauthorizedWhenRegisteringWithoutAuthentication() throws Exception {
    given(guardianResolver.resolve(null, null))
        .willThrow(new BusinessException(ConversationStartErrorCode.UNAUTHORIZED));

    mockMvc
        .perform(
            post("/api/v1/children")
                .contentType(MediaType.APPLICATION_JSON)
                .content(registrationRequestJson()))
        .andExpect(status().isUnauthorized())
        .andExpect(jsonPath("$.code").value("UNAUTHORIZED"));
  }

  @Test
  void returnsTheConnectedChildrenListInTheCommonResponse() throws Exception {
    given(guardianResolver.resolve("Bearer access-token", "10")).willReturn(10L);
    given(childQueryService.getChildren(10L))
        .willReturn(
            List.of(
                new ChildSummaryResponse(
                    3L,
                    "별이",
                    LocalDate.of(2019, 3, 15),
                    7,
                    null,
                    "MONGLE",
                    QuestionDifficulty.LOWER_ELEMENTARY,
                    ChildTutorialStatus.NOT_STARTED,
                    ChildProfileStatus.ACTIVE,
                    "MOTHER",
                    new ChildSummaryResponse.RecentActivity(
                        Instant.parse("2026-07-20T08:15:00Z"), 12L))));

    mockMvc
        .perform(
            get("/api/v1/children")
                .header("Authorization", "Bearer access-token")
                .header("X-Guardian-User-Id", "10"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.code").value("COMMON_200"))
        .andExpect(jsonPath("$.data[0].childId").value(3))
        .andExpect(jsonPath("$.data[0].nickname").value("별이"))
        .andExpect(jsonPath("$.data[0].age").value(7))
        .andExpect(jsonPath("$.data[0].preferredCharacter").value("MONGLE"))
        .andExpect(jsonPath("$.data[0].relationshipType").value("MOTHER"))
        .andExpect(
            jsonPath("$.data[0].recentActivity.lastActivityAt").value("2026-07-20T08:15:00Z"))
        .andExpect(jsonPath("$.data[0].recentActivity.totalActivityCount").value(12));
  }

  @Test
  void returnsAnEmptyChildrenListWhenNoneAreConnected() throws Exception {
    given(guardianResolver.resolve("Bearer access-token", "10")).willReturn(10L);
    given(childQueryService.getChildren(10L)).willReturn(List.of());

    mockMvc
        .perform(
            get("/api/v1/children")
                .header("Authorization", "Bearer access-token")
                .header("X-Guardian-User-Id", "10"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data").isArray())
        .andExpect(jsonPath("$.data").isEmpty());
  }

  @Test
  void updatesAConnectedChildAndReturnsTheLatestDetail() throws Exception {
    given(guardianResolver.resolve("Bearer access-token", "10")).willReturn(10L);
    given(childUpdateService.update(eq(10L), eq(3L), any())).willReturn(response());

    mockMvc
        .perform(
            patch("/api/v1/children/3")
                .header("Authorization", "Bearer access-token")
                .header("X-Guardian-User-Id", "10")
                .contentType(MediaType.APPLICATION_JSON)
                .content(
                    """
                    {
                      "nickname": "새별이",
                      "questionDifficulty": "UPPER_ELEMENTARY",
                      "responseModes": ["EMOJI", "VOICE"]
                    }
                    """))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.code").value("COMMON_200"))
        .andExpect(jsonPath("$.data.childId").value(3));
  }

  @Test
  void rejectsAnInvalidChildProfileUpdateBeforeCallingTheService() throws Exception {
    mockMvc
        .perform(
            patch("/api/v1/children/3")
                .header("Authorization", "Bearer access-token")
                .header("X-Guardian-User-Id", "10")
                .contentType(MediaType.APPLICATION_JSON)
                .content(
                    """
                    {
                      "nickname": " ",
                      "responseModes": []
                    }
                    """))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.code").value("COMMON_400_001"));
  }

  @Test
  void deletesAChildAfterExplicitConfirmation() throws Exception {
    given(guardianResolver.resolve("Bearer access-token", "10")).willReturn(10L);

    mockMvc
        .perform(
            delete("/api/v1/children/3")
                .header("Authorization", "Bearer access-token")
                .header("X-Guardian-User-Id", "10")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"confirmation\":\"DELETE\"}"))
        .andExpect(status().isNoContent());

    verify(childDeletionService).delete(10L, 3L, new DeleteChildRequest("DELETE"));
  }

  @Test
  void rejectsChildDeletionWithoutConfirmation() throws Exception {
    given(guardianResolver.resolve("Bearer access-token", "10")).willReturn(10L);
    willThrow(new BusinessException(ChildErrorCode.CHILD_DELETION_CONFIRMATION_MISMATCH))
        .given(childDeletionService)
        .delete(10L, 3L, new DeleteChildRequest(""));

    mockMvc
        .perform(
            delete("/api/v1/children/3")
                .header("Authorization", "Bearer access-token")
                .header("X-Guardian-User-Id", "10")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"confirmation\":\"\"}"))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.code").value("CHILD_400_002"));
  }

  @Test
  void treatsMissingDeletionBodyAsConfirmationError() throws Exception {
    given(guardianResolver.resolve("Bearer access-token", "10")).willReturn(10L);
    willThrow(new BusinessException(ChildErrorCode.CHILD_DELETION_CONFIRMATION_MISMATCH))
        .given(childDeletionService)
        .delete(10L, 3L, null);

    mockMvc
        .perform(
            delete("/api/v1/children/3")
                .header("Authorization", "Bearer access-token")
                .header("X-Guardian-User-Id", "10"))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.code").value("CHILD_400_002"));
  }

  @Test
  void rejectsUnsupportedCascadeQueryBeforeDeleting() throws Exception {
    mockMvc
        .perform(
            delete("/api/v1/children/3")
                .queryParam("cascade", "true")
                .header("Authorization", "Bearer access-token")
                .header("X-Guardian-User-Id", "10")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"confirmation\":\"DELETE\"}"))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.code").value("COMMON_400_001"));

    verify(childDeletionService, never()).delete(any(), any(), any());
  }

  private String registrationRequestJson() {
    return """
        {
          "nickname": "별이",
          "birthDate": "2019-03-15",
          "relationshipType": "MOTHER",
          "preferredCharacter": "MONGLE",
          "questionDifficulty": "LOWER_ELEMENTARY",
          "responseModes": ["VOICE", "EMOJI"]
        }
        """;
  }

  private ChildRegistrationResponse registrationResponse() {
    return new ChildRegistrationResponse(
        3L,
        "별이",
        LocalDate.of(2019, 3, 15),
        7,
        GuardianRelationshipType.MOTHER,
        "MONGLE",
        QuestionDifficulty.LOWER_ELEMENTARY,
        List.of(ResponseMode.VOICE, ResponseMode.EMOJI),
        ChildTutorialStatus.NOT_STARTED,
        ChildProfileStatus.ACTIVE,
        Instant.parse("2026-07-23T02:30:00Z"));
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
