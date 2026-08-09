package com.ssafy.b209.analysis.service;

import com.ssafy.b209.analysis.dto.DrawingAnalysisActivityType;
import com.ssafy.b209.analysis.dto.DrawingAnalysisSubject;
import com.ssafy.b209.analysis.exception.DrawingAnalysisErrorCode;
import com.ssafy.b209.drawing.domain.DrawingSession;
import com.ssafy.b209.drawing.htp.repository.HtpAssessmentRepository;
import com.ssafy.b209.global.exception.BusinessException;
import java.util.Objects;
import org.springframework.stereotype.Component;

/**
 * 그림 분석 활동 유형과 HTP 주제를 클라이언트 입력이 아닌 영속화된 세션 관계에서 결정한다.
 *
 * <p>HTP 세션은 단계 테이블에 연결된 주제가 있어야 하며, 그림일기는 주제를 전달하지 않는다. 출시 계약에 없는 그림 유형은 다른 모델로 조용히 대체하지 않고 거부한다.
 */
@Component
public class DrawingAnalysisActivityContextResolver {

  private final HtpAssessmentRepository htpAssessmentRepository;

  /**
   * HTP 단계 조회 저장소를 주입받는다.
   *
   * @param htpAssessmentRepository 그림 세션과 HTP 단계 연결을 조회하는 저장소
   */
  public DrawingAnalysisActivityContextResolver(HtpAssessmentRepository htpAssessmentRepository) {
    this.htpAssessmentRepository = htpAssessmentRepository;
  }

  /**
   * 저장된 그림 세션을 AI 활동 맥락으로 변환한다.
   *
   * @param session 분석 대상 그림 세션
   * @return 검증된 활동 유형과 nullable HTP 주제
   * @throws BusinessException HTP 단계 연결이 없거나 출시 계약에 없는 유형인 경우
   */
  public DrawingAnalysisActivityContext resolve(DrawingSession session) {
    Objects.requireNonNull(session, "session must not be null");
    String typeCode = session.getDrawingType().getCode();
    if ("ART_DIARY".equals(typeCode)) {
      return new DrawingAnalysisActivityContext(DrawingAnalysisActivityType.ART_DIARY, null);
    }
    if ("HTP".equals(typeCode)) {
      DrawingAnalysisSubject subject =
          htpAssessmentRepository
              .findStepByDrawingSessionId(session.getId())
              .map(step -> DrawingAnalysisSubject.valueOf(step.getDrawingSubject().name()))
              .orElseThrow(
                  () ->
                      new BusinessException(DrawingAnalysisErrorCode.DRAWING_ANALYSIS_NOT_ALLOWED));
      return new DrawingAnalysisActivityContext(DrawingAnalysisActivityType.HTP, subject);
    }
    throw new BusinessException(DrawingAnalysisErrorCode.DRAWING_ANALYSIS_NOT_ALLOWED);
  }
}
