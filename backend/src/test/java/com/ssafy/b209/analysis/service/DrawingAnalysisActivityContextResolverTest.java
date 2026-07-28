package com.ssafy.b209.analysis.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.mock;

import com.ssafy.b209.analysis.dto.DrawingAnalysisActivityType;
import com.ssafy.b209.analysis.dto.DrawingAnalysisSubject;
import com.ssafy.b209.drawing.domain.DrawingSession;
import com.ssafy.b209.drawing.domain.DrawingType;
import com.ssafy.b209.drawing.htp.domain.HtpAssessmentStep;
import com.ssafy.b209.drawing.htp.domain.HtpDrawingSubject;
import com.ssafy.b209.drawing.htp.repository.HtpAssessmentRepository;
import com.ssafy.b209.global.exception.BusinessException;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class DrawingAnalysisActivityContextResolverTest {

  @Mock private HtpAssessmentRepository htpAssessmentRepository;

  private DrawingAnalysisActivityContextResolver resolver;

  @BeforeEach
  void setUp() {
    resolver = new DrawingAnalysisActivityContextResolver(htpAssessmentRepository);
  }

  @Test
  void resolvesHtpSubjectFromPersistedStep() {
    DrawingSession session = session(10L, "HTP");
    HtpAssessmentStep step = mock(HtpAssessmentStep.class);
    given(step.getDrawingSubject()).willReturn(HtpDrawingSubject.TREE);
    given(htpAssessmentRepository.findStepByDrawingSessionId(10L)).willReturn(Optional.of(step));

    DrawingAnalysisActivityContext context = resolver.resolve(session);

    assertThat(context.activityType()).isEqualTo(DrawingAnalysisActivityType.HTP);
    assertThat(context.drawingSubject()).isEqualTo(DrawingAnalysisSubject.TREE);
  }

  @Test
  void resolvesArtDiaryWithoutSubject() {
    DrawingAnalysisActivityContext context = resolver.resolve(session(20L, "ART_DIARY"));

    assertThat(context.activityType()).isEqualTo(DrawingAnalysisActivityType.ART_DIARY);
    assertThat(context.drawingSubject()).isNull();
  }

  @Test
  void rejectsHtpWithoutPersistedStepAndUnsupportedActivity() {
    DrawingSession htp = session(10L, "HTP");
    given(htpAssessmentRepository.findStepByDrawingSessionId(10L)).willReturn(Optional.empty());

    assertThatThrownBy(() -> resolver.resolve(htp)).isInstanceOf(BusinessException.class);
    assertThatThrownBy(() -> resolver.resolve(session(30L, "FREE_DRAWING")))
        .isInstanceOf(BusinessException.class);
  }

  private DrawingSession session(Long id, String typeCode) {
    DrawingSession session = mock(DrawingSession.class);
    DrawingType type = mock(DrawingType.class);
    if ("HTP".equals(typeCode)) {
      given(session.getId()).willReturn(id);
    }
    given(session.getDrawingType()).willReturn(type);
    given(type.getCode()).willReturn(typeCode);
    return session;
  }
}
