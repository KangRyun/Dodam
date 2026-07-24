package com.ssafy.b209.infrastructure.ai.drawing;

import com.ssafy.b209.analysis.dto.DrawingAnalysisClientCommand;
import com.ssafy.b209.infrastructure.ai.drawing.contract.AiDrawingAnalysisResponse;
import jakarta.validation.Validator;
import java.math.BigDecimal;
import java.util.List;
import java.util.Map;
import java.util.Objects;

/**
 * 외부 AI 서버를 호출하지 않고 정본 계약 형태의 결정적 개발용 결과를 제공한다.
 *
 * <p>실제 이미지 내용이나 심리 해석 결과를 가장하지 않으며, 사용하지 않은 입력과 Mock 경고를 명시한다.
 */
public final class MockDrawingAnalysisClient implements DrawingAnalysisClient {

  private final Validator validator;

  MockDrawingAnalysisClient(Validator validator) {
    this.validator = Objects.requireNonNull(validator);
  }

  /**
   * 검증된 그림 분석 명령으로 정규화 객체 탐지를 포함한 Mock 결과를 생성한다.
   *
   * @param command 저장된 분석과 이미지 Metadata를 포함한 호출 명령
   * @return 누락 입력 사유를 포함한 부분 성공 결과
   * @throws DrawingAnalysisClientException 요청 계약이 유효하지 않은 경우
   */
  @Override
  public AiDrawingAnalysisResponse analyze(DrawingAnalysisClientCommand command) {
    if (command == null || !validator.validate(command).isEmpty()) {
      throw new DrawingAnalysisClientException(DrawingAnalysisClientException.Type.REQUEST_FAILED);
    }
    AiDrawingAnalysisResponse.ModelRef objectDetection =
        new AiDrawingAnalysisResponse.ModelRef("mock-drawing-detector", "1.0");
    return new AiDrawingAnalysisResponse(
        command.analysisId(),
        AiDrawingAnalysisResponse.AnalysisStatus.PARTIAL_SUCCESS,
        new AiDrawingAnalysisResponse.ModelInfo(objectDetection, null, null, null),
        List.of(
            detection("HOUSE", "집", "0.95", "0.10", "0.10", "0.40", "0.45", 0),
            detection("TREE", "나무", "0.91", "0.60", "0.15", "0.25", "0.60", 1)),
        Map.of(),
        Map.of(),
        null,
        null,
        List.of(),
        List.of(
            new AiDrawingAnalysisResponse.UnusedInput(
                "BEHAVIOR", "BEHAVIOR_SUMMARY_ABSENT", null, true)),
        List.of("MOCK_ANALYSIS_RESULT"),
        0L);
  }

  private static AiDrawingAnalysisResponse.DetectedObject detection(
      String code,
      String name,
      String confidence,
      String x,
      String y,
      String width,
      String height,
      int order) {
    BigDecimal widthValue = new BigDecimal(width);
    BigDecimal heightValue = new BigDecimal(height);
    return new AiDrawingAnalysisResponse.DetectedObject(
        code,
        name,
        new BigDecimal(confidence),
        new AiDrawingAnalysisResponse.BoundingBox(
            new BigDecimal(x), new BigDecimal(y), widthValue, heightValue),
        widthValue.multiply(heightValue),
        order);
  }
}
