package com.ssafy.b209.report.service;

import com.ssafy.b209.report.domain.ReportInterpretationConfidence;
import com.ssafy.b209.report.dto.ObservationGenerationResult;
import com.ssafy.b209.report.safety.EvidenceCandidate;
import com.ssafy.b209.report.safety.EvidenceSourceKind;
import com.ssafy.b209.report.safety.EvidenceSourceRef;
import com.ssafy.b209.report.safety.EvidenceSourceType;
import com.ssafy.b209.report.safety.InterpretationCandidate;
import com.ssafy.b209.report.safety.InterpretationCategory;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import org.springframework.stereotype.Component;

/**
 * AI 응답의 경향 해석·근거를 안전 검증기 입력으로 옮긴다 (S15P11B209-902).
 *
 * <p>검증기({@code report.safety})는 AI DTO 를 직접 알지 않는다 — 순수 계산으로 두어 입력만 바꿔 끼울 수 있게 한 경계다. 이 어댑터가 그 경계를
 * 잇는다.
 *
 * <p>알 수 없는 enum 값은 <strong>버린다.</strong> 문자열을 그대로 통과시키면 검증기가 판정할 수 없는 값을 만나고, 예외로 던지면 항목 하나 때문에
 * 리포트 저장 전체가 실패한다. 버린 항목은 근거 풀에 없으므로 그 근거를 참조한 카드는 구조 게이트에서 자연히 탈락한다.
 *
 * <p><strong>확신 등급({@code confidence})만 예외다</strong> (S15P11B209-982). 카테고리·근거 종류는 판정에 쓰이는 값이라 해석
 * 실패가 곧 "판정할 수 없음"이지만, 등급은 판정에 쓰이지 않는 보조 표시다. 그래서 해석하지 못한 등급 때문에 카드를 버리지 않고 등급만 {@code null}로 떨어뜨린다
 * — AI 가 등급 이름을 하나 바꾸면 보호자 리포트에서 카드가 통째로 사라지는 결합은 만들지 않는다.
 */
@Component
public class InterpretationCandidateAdapter {

  /**
   * 경향 해석 카드를 검증기 입력으로 옮긴다.
   *
   * @param drafts AI 가 보낸 카드 목록
   * @return 검증 가능한 카드 목록이며 카테고리를 해석할 수 없는 카드는 제외한다. 확신 등급을 해석할 수 없는 카드는 등급만 {@code null}로 두고 남긴다
   *     (S15P11B209-982)
   */
  public List<InterpretationCandidate> toCandidates(
      List<ObservationGenerationResult.PublicInterpretationDraft> drafts) {
    List<InterpretationCandidate> candidates = new ArrayList<>();
    for (ObservationGenerationResult.PublicInterpretationDraft draft : safe(drafts)) {
      if (draft == null) {
        continue;
      }
      InterpretationCategory category = parseCategory(draft.category());
      if (category == null) {
        continue;
      }
      candidates.add(
          new InterpretationCandidate(
              category,
              draft.title(),
              draft.tendencyText(),
              draft.scopeText(),
              draft.homeObservationGuide(),
              draft.evidenceRefs(),
              // 여기서 continue 하지 않는다 — 등급은 카드의 존재 조건이 아니다(위 클래스 주석 참고).
              parseConfidence(draft.confidence())));
    }
    return candidates;
  }

  /**
   * 근거 풀을 검증기 입력으로 옮긴다.
   *
   * <p>원본 참조와 파생 목록 중 정확히 하나만 갖는 항목만 남긴다 — 배타 규칙을 지키지 않는 근거는 계수에 쓸 수 없다.
   *
   * @param drafts AI 가 보낸 근거 목록
   * @return 검증 가능한 근거 목록
   */
  public List<EvidenceCandidate> toEvidenceCandidates(
      List<ObservationGenerationResult.EvidenceItemDraft> drafts) {
    List<EvidenceCandidate> candidates = new ArrayList<>();
    for (ObservationGenerationResult.EvidenceItemDraft draft : safe(drafts)) {
      if (draft == null || draft.evidenceId() == null) {
        continue;
      }
      EvidenceSourceType sourceType = parseSourceType(draft.sourceType());
      if (sourceType == null) {
        continue;
      }
      EvidenceSourceRef sourceRef = parseRef(draft.sourceRef());
      List<EvidenceSourceRef> derivedFrom = parseRefs(draft.derivedFrom());
      boolean hasOrigin = sourceRef != null;
      boolean hasDerived = !derivedFrom.isEmpty();
      if (hasOrigin == hasDerived) {
        // 둘 다 있거나 둘 다 없으면 배타 규칙 위반이다.
        continue;
      }
      candidates.add(
          new EvidenceCandidate(
              draft.evidenceId(),
              sourceType,
              draft.text(),
              sourceRef,
              derivedFrom,
              draft.sttNeedsConfirmation(),
              null));
    }
    return candidates;
  }

  private static EvidenceSourceRef parseRef(
      ObservationGenerationResult.EvidenceSourceRefDraft ref) {
    if (ref == null || ref.id() == null || ref.id().isBlank()) {
      return null;
    }
    EvidenceSourceKind kind = parseEnum(EvidenceSourceKind.class, ref.kind());
    return kind == null ? null : new EvidenceSourceRef(kind, ref.id());
  }

  private static List<EvidenceSourceRef> parseRefs(
      List<ObservationGenerationResult.EvidenceSourceRefDraft> refs) {
    List<EvidenceSourceRef> parsed = new ArrayList<>();
    for (ObservationGenerationResult.EvidenceSourceRefDraft ref : safe(refs)) {
      EvidenceSourceRef converted = parseRef(ref);
      if (converted != null) {
        parsed.add(converted);
      }
    }
    return parsed;
  }

  private static InterpretationCategory parseCategory(String value) {
    return parseEnum(InterpretationCategory.class, value);
  }

  private static ReportInterpretationConfidence parseConfidence(String value) {
    return parseEnum(ReportInterpretationConfidence.class, value);
  }

  private static EvidenceSourceType parseSourceType(String value) {
    return parseEnum(EvidenceSourceType.class, value);
  }

  private static <E extends Enum<E>> E parseEnum(Class<E> type, String value) {
    if (value == null || value.isBlank()) {
      return null;
    }
    try {
      return Enum.valueOf(type, value.trim().toUpperCase(Locale.ROOT));
    } catch (IllegalArgumentException exception) {
      return null;
    }
  }

  private static <T> List<T> safe(List<T> value) {
    return value == null ? List.of() : value;
  }
}
