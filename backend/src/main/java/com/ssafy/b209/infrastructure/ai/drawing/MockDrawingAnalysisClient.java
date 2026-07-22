package com.ssafy.b209.infrastructure.ai.drawing;

import com.ssafy.b209.analysis.dto.BoundingBoxResponse;
import com.ssafy.b209.analysis.dto.DrawingAnalysisModelResponse;
import com.ssafy.b209.analysis.dto.DrawingAnalysisRequest;
import com.ssafy.b209.analysis.dto.DrawingAnalysisResponse;
import com.ssafy.b209.analysis.dto.DrawingAnalysisStatus;
import com.ssafy.b209.analysis.dto.DrawingDetectionResponse;
import jakarta.validation.Validator;
import java.math.BigDecimal;
import java.time.Clock;
import java.time.Instant;
import java.util.List;
import java.util.Objects;

/**
 * 실제 AI 서버나 DB를 호출하지 않고 후속 흐름 개발용 그림 분석 결과를 제공하는 Client다.
 *
 * <p>반환 값은 고정된 계약 Fixture이며 실제 이미지 내용, 객체 탐지 성능 또는 심리 분석 결과를 나타내지 않는다.
 */
public final class MockDrawingAnalysisClient implements DrawingAnalysisClient {

  private static final DrawingAnalysisModelResponse MODEL =
      new DrawingAnalysisModelResponse("mock-drawing-detector", "1.0");
  private static final List<DrawingDetectionResponse> DETECTIONS =
      List.of(
          detection("HOUSE", "0.95", "120.0", "80.0", "640.0", "520.0"),
          detection("TREE", "0.91", "820.0", "120.0", "380.0", "700.0"));

  private final Validator validator;
  private final Clock clock;

  MockDrawingAnalysisClient(Validator validator, Clock clock) {
    this.validator = Objects.requireNonNull(validator);
    this.clock = Objects.requireNonNull(clock);
  }

  /**
   * 기존 그림 분석 요청 계약을 받아 Mock 응답을 생성한다.
   *
   * @param request 그림 분석 요청 계약
   * @return 결정적으로 생성된 Mock 그림 분석 응답
   * @throws DrawingAnalysisClientException 요청 계약이 유효하지 않은 경우
   */
  @Override
  public DrawingAnalysisResponse analyze(DrawingAnalysisRequest request) {
    if (request == null || !validator.validate(request).isEmpty()) {
      throw new DrawingAnalysisClientException(DrawingAnalysisClientException.Type.REQUEST_FAILED);
    }
    return new DrawingAnalysisResponse(
        request.requestId(),
        DrawingAnalysisStatus.SUCCEEDED,
        MODEL,
        DETECTIONS,
        null,
        Instant.now(clock));
  }

  private static DrawingDetectionResponse detection(
      String label, String confidence, String x, String y, String width, String height) {
    return new DrawingDetectionResponse(
        label,
        new BigDecimal(confidence),
        new BoundingBoxResponse(
            new BigDecimal(x), new BigDecimal(y), new BigDecimal(width), new BigDecimal(height)));
  }
}
