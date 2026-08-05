package com.ssafy.b209.report.safety;

import java.util.List;
import java.util.stream.Stream;

/**
 * 안전 검증에 넣는 경향 해석 카드 한 건이다(875 계약 §3 {@code publicInterpretations[]}에 대응하는 중립 입력 타입).
 *
 * <p>저장 엔티티가 아니다 — {@link EvidenceCandidate}와 같은 이유로 자기 입력 타입을 둔다. 필드명은 875 계약과 FE DTO({@code
 * report_dtos.dart} {@code ReportInterpretationDto})의 JSON 키를 그대로 따른다.
 *
 * @param category 관찰 관점 라벨이며 해석할 수 없으면 {@code null}
 * @param title 카드 제목이며 없으면 {@code null}
 * @param tendencyText 경향 문장이며 가능성 어조여야 한다
 * @param scopeText 해석 범위 안내 문장이며 비어 있으면 공개하지 않는다
 * @param homeObservationGuide 가정 관찰 안내 문장이며 비어 있으면 공개하지 않는다
 * @param evidenceRefs 이 카드가 근거로 가리키는 {@code evidenceId} 목록
 */
public record InterpretationCandidate(
    InterpretationCategory category,
    String title,
    String tendencyText,
    String scopeText,
    String homeObservationGuide,
    List<Long> evidenceRefs) {

  /**
   * 카드에 실린 사람이 읽는 문장을 모아 돌려준다.
   *
   * <p>표현 안전 필터가 검사할 대상이다. {@code category}는 코드값이라 검사 대상이 아니다.
   *
   * @return 검사 대상 문장 목록이며 {@code null} 항목은 제외한다
   */
  public List<String> reviewableTexts() {
    return Stream.of(title, tendencyText, scopeText, homeObservationGuide)
        .filter(text -> text != null && !text.isBlank())
        .toList();
  }
}
