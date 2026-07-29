package com.ssafy.b209.drawing.htp.controller;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.verify;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.ssafy.b209.analysis.domain.DrawingAnalysisState;
import com.ssafy.b209.drawing.domain.DrawingEmotionCode;
import com.ssafy.b209.drawing.domain.DrawingInputMethod;
import com.ssafy.b209.drawing.domain.DrawingSessionStatus;
import com.ssafy.b209.drawing.domain.DrawingStage;
import com.ssafy.b209.drawing.dto.request.SaveDrawingReflectionRequest;
import com.ssafy.b209.drawing.dto.response.DrawingReflectionResponse;
import com.ssafy.b209.drawing.htp.domain.HtpAssessmentStatus;
import com.ssafy.b209.drawing.htp.domain.HtpDrawingSubject;
import com.ssafy.b209.drawing.htp.dto.HtpAssessmentResponse;
import com.ssafy.b209.drawing.htp.dto.HtpAssessmentStepResponse;
import com.ssafy.b209.drawing.htp.dto.HtpCompletionResponse;
import com.ssafy.b209.drawing.htp.dto.StartHtpAssessmentRequest;
import com.ssafy.b209.drawing.htp.service.HtpAssessmentService;
import com.ssafy.b209.report.domain.ReportStatus;
import java.time.Instant;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

@WebMvcTest(HtpAssessmentController.class)
@Import(com.ssafy.b209.global.exception.GlobalExceptionHandler.class)
class HtpAssessmentControllerTest {

  private static final String KEY = "htp-request-key";
  private static final String START_REQUEST =
      """
      {
        "childId": 1,
        "inputMethod": "CANVAS",
        "clientStartedAt": "2026-07-28T10:00:00+09:00"
      }
      """;

  @Autowired private MockMvc mockMvc;
  @MockitoBean private HtpAssessmentService htpAssessmentService;

  @Test
  void startsHtpAssessmentAndReturnsHouseSessionLocation() throws Exception {
    given(htpAssessmentService.start(eq(KEY), any(StartHtpAssessmentRequest.class)))
        .willReturn(response(HtpDrawingSubject.HOUSE, 1, 100L, false));

    mockMvc
        .perform(
            post("/api/v1/htp-assessments")
                .header("Idempotency-Key", KEY)
                .contentType(MediaType.APPLICATION_JSON)
                .content(START_REQUEST))
        .andExpect(status().isCreated())
        .andExpect(header().string("Location", "/api/v1/htp-assessments/200"))
        .andExpect(jsonPath("$.code").value("COMMON_201"))
        .andExpect(jsonPath("$.data.currentStep.drawingSubject").value("HOUSE"))
        .andExpect(jsonPath("$.data.currentStep.drawingSessionId").value(100));
  }

  @Test
  void returnsCurrentHtpStep() throws Exception {
    given(htpAssessmentService.get(200L))
        .willReturn(response(HtpDrawingSubject.TREE, 2, 101L, false));

    mockMvc
        .perform(get("/api/v1/htp-assessments/200"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.currentStep.stepOrder").value(2))
        .andExpect(jsonPath("$.data.currentStep.drawingSubject").value("TREE"));
  }

  @Test
  void completesCurrentStepAndReturnsNextSubject() throws Exception {
    given(htpAssessmentService.nextStep(200L, KEY, DrawingInputMethod.UPLOAD))
        .willReturn(response(HtpDrawingSubject.PERSON, 3, 102L, false));

    mockMvc
        .perform(
            post("/api/v1/htp-assessments/200/steps/next")
                .header("Idempotency-Key", KEY)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"inputMethod\":\"UPLOAD\"}"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.currentStep.drawingSubject").value("PERSON"));

    verify(htpAssessmentService).nextStep(200L, KEY, DrawingInputMethod.UPLOAD);
  }

  @Test
  void abandonsHtpAssessment() throws Exception {
    HtpAssessmentResponse abandoned =
        new HtpAssessmentResponse(
            200L,
            HtpAssessmentStatus.ABANDONED,
            Instant.parse("2026-07-29T01:00:00Z"),
            new HtpAssessmentStepResponse(
                1,
                HtpDrawingSubject.HOUSE,
                100L,
                DrawingSessionStatus.DELETED,
                DrawingStage.DRAWING),
            false);
    given(htpAssessmentService.abandon(200L, KEY)).willReturn(abandoned);

    mockMvc
        .perform(post("/api/v1/htp-assessments/200/abandon").header("Idempotency-Key", KEY))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.status").value("ABANDONED"));
  }

  @Test
  void acceptsSingleAggregateReportGeneration() throws Exception {
    given(htpAssessmentService.complete(200L, KEY))
        .willReturn(
            new HtpCompletionResponse(
                200L,
                HtpAssessmentStatus.ANALYZING,
                900L,
                DrawingAnalysisState.PENDING,
                901L,
                ReportStatus.GENERATING));

    mockMvc
        .perform(post("/api/v1/htp-assessments/200/complete").header("Idempotency-Key", KEY))
        .andExpect(status().isAccepted())
        .andExpect(jsonPath("$.data.status").value("ANALYZING"))
        .andExpect(jsonPath("$.data.analysisId").value(900))
        .andExpect(jsonPath("$.data.reportId").value(901));
  }

  @Test
  void savesOneActivityReflectionForPersonStep() throws Exception {
    given(htpAssessmentService.saveReflection(eq(200L), any(SaveDrawingReflectionRequest.class)))
        .willReturn(
            new DrawingReflectionResponse(
                102L, DrawingStage.REFLECTION, List.of(DrawingEmotionCode.HAPPY), false));

    mockMvc
        .perform(
            put("/api/v1/htp-assessments/200/reflection")
                .contentType(MediaType.APPLICATION_JSON)
                .content(
                    """
                    {
                      "selectedEmotions": ["HAPPY"],
                      "skipped": false
                    }
                    """))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.drawingSessionId").value(102))
        .andExpect(jsonPath("$.data.selectedEmotions[0]").value("HAPPY"));
  }

  private HtpAssessmentResponse response(
      HtpDrawingSubject subject, int order, Long sessionId, boolean allStepsCompleted) {
    return new HtpAssessmentResponse(
        200L,
        HtpAssessmentStatus.IN_PROGRESS,
        Instant.parse("2026-07-29T01:00:00Z"),
        new HtpAssessmentStepResponse(
            order, subject, sessionId, DrawingSessionStatus.IN_PROGRESS, DrawingStage.DRAWING),
        allStepsCompleted);
  }
}
