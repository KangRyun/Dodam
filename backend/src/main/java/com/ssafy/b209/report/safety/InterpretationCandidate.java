package com.ssafy.b209.report.safety;

import com.ssafy.b209.report.domain.ReportInterpretationConfidence;
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
 * @param confidence 근거 종류로 계산한 확신 등급이며 없으면 {@code null} (S15P11B209-982). <strong>검증기는 이 값을 읽지
 *     않는다</strong> — 판정에 쓰이지 않고 저장까지 실려 가기만 하는 통과 필드다. {@link InterpretationCategory}처럼 자기 입력
 *     enum 을 따로 두지 않고 저장용 {@link ReportInterpretationConfidence}를 그대로 쓰는 이유가 그것이다. 판정에 안 쓰는 값을 위해
 *     매핑 계층을 한 번 더 두면, 그 계층이 값을 조용히 떨어뜨렸을 때 아무 검증도 걸리지 않는다(902 에서 저장 메서드가 호출되지 않은 채 몇 주를 보낸 것과 같은
 *     모양이다)
 */
public record InterpretationCandidate(
    InterpretationCategory category,
    String title,
    String tendencyText,
    String scopeText,
    String homeObservationGuide,
    List<Long> evidenceRefs,
    ReportInterpretationConfidence confidence) {

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
