package com.ssafy.b209.infrastructure.ai.observation;

import com.ssafy.b209.report.dto.ObservationGenerationRequest;
import com.ssafy.b209.report.dto.ObservationGenerationResult;
import com.ssafy.b209.report.dto.ObservationGenerationResult.ConversationSummaryDraft;
import com.ssafy.b209.report.dto.ObservationGenerationResult.FollowUpGuideDraft;
import com.ssafy.b209.report.dto.ObservationGenerationResult.GuardianQuestionDraft;
import com.ssafy.b209.report.dto.ObservationGenerationResult.ObservationDraft;
import com.ssafy.b209.report.dto.ObservationGenerationResult.ObservedFeatureDraft;
import jakarta.validation.Validator;
import java.math.BigDecimal;
import java.util.List;
import java.util.Objects;

/**
 * 실제 AI 서버나 DB를 호출하지 않고 후속 흐름 개발용 관찰 리포트 결과를 제공하는 Client다.
 *
 * <p>반환 값은 진단이 아닌 고정된 관찰 계약 Fixture이며 실제 아동의 심리나 발달 상태를 나타내지 않는다. 전문가 검토 전 관찰 특징은 {@code
 * EXPERT_ONLY}로만 표시한다.
 */
public final class MockAiObservationClient implements AiObservationClient {

  private static final String MODEL_NAME = "mock-observation-generator";
  private static final String MODEL_VERSION = "1.0";
  private static final BigDecimal CONFIDENCE = new BigDecimal("0.80");
  private static final String DISCLAIMER =
      "본 결과는 아동 발달 진단이 아니라 그림 활동 관찰 기록입니다. 우려되는 점이 있으면 전문가와 상담하세요.";
  private static final String LIMITATIONS =
      "본 리포트는 제한된 활동 데이터를 바탕으로 한 관찰 기록이며, 아동의 발달 상태를 단정하지 않습니다.";
  private static final String DEFAULT_UTTERANCE = "재미있었어요.";

  private final Validator validator;

  MockAiObservationClient(Validator validator) {
    this.validator = Objects.requireNonNull(validator);
  }

  /**
   * 최종 분석 요청 계약을 받아 결정적인 Mock 관찰 결과를 생성한다.
   *
   * @param request 최종 분석 관찰 생성 요청
   * @return 결정적으로 생성된 Mock 관찰 리포트 결과
   * @throws AiObservationClientException 요청 계약이 유효하지 않은 경우
   */
  @Override
  public ObservationGenerationResult generate(ObservationGenerationRequest request) {
    if (request == null
        || !"FINAL".equals(request.analysisType())
        || !validator.validate(request).isEmpty()) {
      throw new AiObservationClientException(AiObservationClientException.Type.REQUEST_FAILED);
    }
    String representative =
        request.representativeUtterance() == null || request.representativeUtterance().isBlank()
            ? DEFAULT_UTTERANCE
            : request.representativeUtterance();

    ObservationDraft observationDraft =
        new ObservationDraft(
            "AI_DRAFT",
            "아이는 그림 활동에 집중하며 자신의 생각을 표현하려 했습니다. 아래 내용은 관찰 기록이며 진단이 아닙니다.",
            "색을 다양하게 사용했고, 질문에 자기 경험을 떠올려 대답하려는 모습이 보였습니다.",
            "일부 질문에서 대답을 잠시 주저하는 모습이 관찰되었습니다. 추가 관찰이 도움이 될 수 있습니다.",
            "그림 구성과 대화 응답에서 관찰된 내용을 종합했습니다.",
            "아이의 표현을 그대로 존중하며 편안하게 이야기를 이어가 보세요.",
            "오늘 그린 그림에서 가장 마음에 드는 부분이 어디인지 물어봐 주세요.",
            false,
            DISCLAIMER,
            List.of(
                new ObservedFeatureDraft(
                    "EXPRESSION_ENGAGEMENT",
                    "표현에 대한 몰입",
                    "활동 내내 자신의 생각을 적극적으로 표현했습니다.",
                    "그림 구성과 대화 응답에서 관찰됨",
                    "EXPERT_ONLY"),
                new ObservedFeatureDraft(
                    "HESITATION_SIGNAL",
                    "응답 주저 관찰",
                    "특정 주제에서 응답을 잠시 주저하는 패턴이 관찰되었습니다.",
                    "대화 응답 흐름에서 관찰됨",
                    "EXPERT_ONLY")));

    ConversationSummaryDraft conversationSummary =
        new ConversationSummaryDraft(
            "대화에서 아이는 자신의 경험과 감정을 표현하려 했습니다.", "오늘의 그림", "즐거움", "SELECTED", representative);

    return new ObservationGenerationResult(
        request.requestId(),
        MODEL_NAME,
        MODEL_VERSION,
        CONFIDENCE,
        observationDraft,
        conversationSummary,
        List.of("활동 중 색을 여러 번 바꾸어 사용했습니다.", "질문에 답할 때 잠시 생각하는 시간을 가졌습니다."),
        List.of(
            new FollowUpGuideDraft("그림에 대해 개방형 질문으로 이야기해 보세요.", "정답을 요구하지 않는 질문이 아이의 표현을 돕습니다.")),
        List.of(
            new GuardianQuestionDraft("이 그림을 그릴 때 어떤 기분이었어?", "감정 표현 유도"),
            new GuardianQuestionDraft("여기 이 부분은 무엇을 그린 거야?", "표현 확장")),
        LIMITATIONS,
        List.of());
  }
}
