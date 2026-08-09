package com.ssafy.b209.analysis.controller;

import static org.mockito.BDDMockito.given;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.ssafy.b209.analysis.domain.DrawingAnalysisScope;
import com.ssafy.b209.analysis.domain.DrawingAnalysisState;
import com.ssafy.b209.analysis.dto.AnalysisBoundingBoxResponse;
import com.ssafy.b209.analysis.dto.AnalysisDetectedObjectResponse;
import com.ssafy.b209.analysis.dto.AnalysisStatusResponse;
import com.ssafy.b209.analysis.dto.DrawingAnalysisType;
import com.ssafy.b209.analysis.service.DrawingAnalysisQueryService;
import com.ssafy.b209.global.exception.GlobalExceptionHandler;
import java.math.BigDecimal;
import java.time.Instant;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.context.annotation.Import;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

@WebMvcTest(AnalysisStatusController.class)
@Import(GlobalExceptionHandler.class)
class AnalysisStatusControllerTest {

  @Autowired private MockMvc mockMvc;
  @MockitoBean private DrawingAnalysisQueryService drawingAnalysisQueryService;

  @Test
  void returnsCanonicalAnalysisStatusResponse() throws Exception {
    given(drawingAnalysisQueryService.getAnalysisStatus(30L))
        .willReturn(
            new AnalysisStatusResponse(
                30L,
                10L,
                20L,
                DrawingAnalysisScope.FINAL,
                DrawingAnalysisType.ACTIVITY_REPORT,
                DrawingAnalysisState.SUCCESS,
                new BigDecimal("0.9500"),
                "htp-detector",
                "1.0",
                Instant.parse("2026-07-29T01:00:00Z"),
                Instant.parse("2026-07-29T01:00:03Z"),
                List.of(
                    new AnalysisDetectedObjectResponse(
                        40L,
                        "PERSON",
                        "사람",
                        new BigDecimal("0.9500"),
                        new AnalysisBoundingBoxResponse(
                            new BigDecimal("0.100000"),
                            new BigDecimal("0.200000"),
                            new BigDecimal("0.300000"),
                            new BigDecimal("0.400000")))),
                null,
                null));

    mockMvc
        .perform(get("/api/v1/analyses/{analysisId}", 30L))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.code").value("COMMON_200"))
        .andExpect(jsonPath("$.data.analysisId").value(30))
        .andExpect(jsonPath("$.data.analysisType").value("FINAL"))
        .andExpect(jsonPath("$.data.analysisTaskType").value("ACTIVITY_REPORT"))
        .andExpect(jsonPath("$.data.analysisStatus").value("SUCCESS"))
        .andExpect(jsonPath("$.data.detectedObjects[0].detectedObjectId").value(40))
        .andExpect(jsonPath("$.data.detectedObjects[0].objectCode").value("PERSON"))
        .andExpect(jsonPath("$.data.detectedObjects[0].objectName").value("사람"))
        .andExpect(jsonPath("$.data.detectedObjects[0].boundingBox.x").value(0.1))
        .andExpect(jsonPath("$.data.failureCode").isEmpty())
        .andExpect(jsonPath("$.data.message").isEmpty());
  }

  @Test
  void rejectsNonPositiveAnalysisIdentifier() throws Exception {
    mockMvc
        .perform(get("/api/v1/analyses/{analysisId}", 0L))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.code").value("COMMON_400_001"));
  }
}
