package com.ssafy.b209.screening.registry;

import java.util.List;
import java.util.Set;

/**
 * 등록부에 실린 표준화 선별도구 한 건이다.
 *
 * <p><strong>여기에 문항·채점키·규준표·절단점은 없다.</strong> 앞으로도 들어오면 안 된다 — 저장소에 넣는 순간 라이선스 위반이자 무면허 검사도구가 된다. 이
 * 표가 담는 것은 "그 도구가 무엇이고, 누가 채점하며, 왜 아직 못 켜는가"뿐이다.
 *
 * @param instrumentId 도구 식별자
 * @param displayName 공식 도구명
 * @param state 런타임 활성 상태이며 기본은 {@link ScreeningInstrumentState#DISABLED}
 * @param minAgeMonths 공식 적용 연령의 시작(개월, 포함)이며 임상위원회가 확정하지 않았으면 {@code null}
 * @param maxAgeMonths 공식 적용 연령의 끝(개월, 포함)이며 확정하지 않았으면 {@code null}
 * @param respondents 공식 양식이 규정한 응답자
 * @param scoringAuthority 채점 주체다. <strong>이 서비스가 채점하는 도구는 없다</strong>
 * @param requiredDisclosure 결과를 보여 줄 때 반드시 함께 나가는 문구
 * @param sourceIds 근거 자료 식별자
 * @param blockers 지금 이 도구를 막고 있는 사유
 * @param activationBlockerNotes 사람이 읽는 블로커 설명이며 판정에는 쓰지 않는다
 */
public record ScreeningInstrument(
    String instrumentId,
    String displayName,
    ScreeningInstrumentState state,
    Integer minAgeMonths,
    Integer maxAgeMonths,
    Set<String> respondents,
    String scoringAuthority,
    String requiredDisclosure,
    List<String> sourceIds,
    Set<ScreeningActivationBlocker> blockers,
    List<String> activationBlockerNotes) {

  /** 목록·집합은 방어 복사한다. 등록부는 런타임에 바뀌지 않는다. */
  public ScreeningInstrument {
    respondents = respondents == null ? Set.of() : Set.copyOf(respondents);
    sourceIds = sourceIds == null ? List.of() : List.copyOf(sourceIds);
    blockers = blockers == null ? Set.of() : Set.copyOf(blockers);
    activationBlockerNotes =
        activationBlockerNotes == null ? List.of() : List.copyOf(activationBlockerNotes);
  }

  /**
   * 공식 적용 연령이 확정돼 있는지 알려 준다.
   *
   * <p>확정되지 않은 도구(정확한 한국어판을 임상위원회가 아직 고르지 않은 불안·우울 선별)는 나이로 판정할 수 없다. 짐작해서 범위를 넣으면 그 순간 지어낸 적용 연령이
   * 된다.
   *
   * @return 시작·끝이 모두 있으면 {@code true}
   */
  public boolean hasConfirmedAgeRange() {
    return minAgeMonths != null && maxAgeMonths != null;
  }
}
