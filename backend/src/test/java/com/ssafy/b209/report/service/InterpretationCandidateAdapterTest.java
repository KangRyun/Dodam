package com.ssafy.b209.report.service;

import static org.assertj.core.api.Assertions.assertThat;

import com.ssafy.b209.report.domain.ReportInterpretationConfidence;
import com.ssafy.b209.report.dto.ObservationGenerationResult;
import com.ssafy.b209.report.safety.InterpretationCandidate;
import java.util.List;
import org.junit.jupiter.api.Test;

/**
 * AI 응답의 확신 등급이 검증기 입력으로 옮겨질 때의 규칙을 고정한다 (S15P11B209-982).
 *
 * <p>이 어댑터는 <b>해석 실패를 두 가지로 다르게 처리</b>한다. 카테고리·근거 종류는 판정에 쓰이는 값이라 해석하지 못하면 항목을 버리지만, 확신 등급은 보조
 * 표시라 등급만 버리고 카드는 남긴다. 두 규칙이 한 메서드 안에 섞여 있어 나중에 "일관성"을 이유로 등급도 버리도록 고쳐지기 쉽다 — 그러면 AI 가 등급 이름을 하나
 * 늘렸을 때 보호자 리포트에서 카드가 통째로 사라진다. 그 회귀를 여기서 막는다.
 */
class InterpretationCandidateAdapterTest {

  private final InterpretationCandidateAdapter adapter = new InterpretationCandidateAdapter();

  @Test
  void carriesKnownConfidenceGrade() {
    List<InterpretationCandidate> candidates = adapter.toCandidates(List.of(draft("WEAK")));

    assertThat(candidates).hasSize(1);
    assertThat(candidates.getFirst().confidence()).isEqualTo(ReportInterpretationConfidence.WEAK);
  }

  @Test
  void keepsCardWhenConfidenceIsAbsent() {
    // 836·837 재발 방지. 등급은 optional 이므로 없다고 카드가 사라지면 안 된다.
    List<InterpretationCandidate> candidates = adapter.toCandidates(List.of(draft(null)));

    assertThat(candidates).hasSize(1);
    assertThat(candidates.getFirst().confidence()).isNull();
    assertThat(candidates.getFirst().title()).isEqualTo("가족과의 정서적 연결");
  }

  @Test
  void keepsCardWhenConfidenceGradeIsUnknown() {
    List<InterpretationCandidate> candidates = adapter.toCandidates(List.of(draft("VERY_STRONG")));

    assertThat(candidates).hasSize(1);
    assertThat(candidates.getFirst().confidence()).isNull();
    // 부정형 — 카테고리와 달리 등급 해석 실패는 카드를 떨어뜨리는 사유가 아니다.
    assertThat(candidates.getFirst().category()).isNotNull();
  }

  @Test
  void dropsCardWhenCategoryIsUnknownEvenWithValidConfidence() {
    // 대비 축. 등급이 멀쩡해도 카테고리를 해석하지 못하면 검증기가 판정할 수 없으므로 카드를 버린다.
    List<InterpretationCandidate> candidates =
        adapter.toCandidates(
            List.of(
                new ObservationGenerationResult.PublicInterpretationDraft(
                    "PERSONALITY_TYPE",
                    "성격 유형",
                    "그런 경향이 보일 수 있습니다.",
                    "이번 활동에서 나타난 가능성입니다.",
                    "가정에서 살펴봐 주세요.",
                    List.of(1L),
                    "STRONG")));

    assertThat(candidates).isEmpty();
  }

  private static ObservationGenerationResult.PublicInterpretationDraft draft(String confidence) {
    return new ObservationGenerationResult.PublicInterpretationDraft(
        "RELATIONSHIP",
        "가족과의 정서적 연결",
        "가족에게 정서적으로 의지하려는 경향이 보일 수 있습니다.",
        "이번 그림 활동에서 나타난 가능성입니다.",
        "새로운 상황에서도 보호자의 확인을 반복해서 구하는지 살펴봐 주세요.",
        List.of(1L, 2L),
        confidence);
  }
}
