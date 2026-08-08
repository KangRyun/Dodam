package com.ssafy.b209.screening.registry;

/**
 * 한 아동에게 그 도구를 지금 제공할 수 있는지 판정한다.
 *
 * <p><strong>결정론적 코드다.</strong> 같은 입력에는 언제나 같은 답이 나오고, LLM 은 이 판정에 관여하지 않는다 — 모델이 도구를 켜거나 제안할 수 있으면
 * 그림 한 장이 검사 권고의 근거가 된다.
 *
 * <p>판정 순서에 의미가 있다.
 *
 * <ol>
 *   <li>이미 기록된 외부 결과가 있으면 그 사실이 먼저다 — 이미 받은 검사를 "받을 수 없다"고 말하면 안 된다.
 *   <li>나이를 모르면 제안하지 않는다. 짐작해서 권하는 것이 가장 나쁘다.
 *   <li>공식 적용 연령 밖이면 거기서 끝난다. 라이선스 사정보다 <strong>아이에게 맞는 도구인가</strong>가 먼저다.
 *   <li>그다음이 라이선스, 그다음이 임상 승인이다.
 * </ol>
 */
public final class ScreeningEligibility {

  private ScreeningEligibility() {}

  /**
   * 도구 하나에 대한 제공 가능 여부를 판정한다.
   *
   * <p>{@code childAgeMonths} 는 만 나이(년)를 12배 한 값이라 개월 정밀도가 없다. 이 값은 <strong>어떤 도구를 제외할지 고르는 데만
   * 쓰고</strong> 발달 판정이나 또래 비교에 쓰지 않는다. 경계에서 한 해가 통째로 움직이지만, 지금 등록부의 모든 도구가 어차피 제공되지 않으므로 판정이 느슨해도
   * 아이에게 잘못된 검사가 나가지 않는다.
   *
   * @param instrument 등록부에 실린 도구
   * @param childAgeMonths 아동 나이(개월)이며 모르면 {@code null}
   * @param hasExternalResult 외부에서 받은 결과가 이미 기록돼 있으면 {@code true}
   * @return 제공 가능 여부 판정
   */
  public static ScreeningOfferState decide(
      ScreeningInstrument instrument, Integer childAgeMonths, boolean hasExternalResult) {
    if (instrument == null) {
      return ScreeningOfferState.NOT_OFFERED;
    }
    if (hasExternalResult) {
      return ScreeningOfferState.EXTERNAL_RESULT_AVAILABLE;
    }
    if (childAgeMonths == null || !instrument.hasConfirmedAgeRange()) {
      return ScreeningOfferState.NOT_OFFERED;
    }
    if (childAgeMonths < instrument.minAgeMonths() || childAgeMonths > instrument.maxAgeMonths()) {
      return ScreeningOfferState.NOT_ELIGIBLE_BY_AGE;
    }
    if (instrument.blockers().contains(ScreeningActivationBlocker.LICENSE)) {
      return ScreeningOfferState.PENDING_LICENSE;
    }
    if (instrument.blockers().contains(ScreeningActivationBlocker.CLINICAL_APPROVAL)
        || instrument.blockers().contains(ScreeningActivationBlocker.CLINICAL_OPERATIONS)) {
      return ScreeningOfferState.PENDING_CLINICAL_APPROVAL;
    }
    if (instrument.state() == ScreeningInstrumentState.ENABLED) {
      return ScreeningOfferState.OFFERABLE_AFTER_CONSENT;
    }
    return ScreeningOfferState.NOT_OFFERED;
  }

  /**
   * 지금 이 아동에게 제공할 수 있는 도구가 하나라도 있는지 알려 준다.
   *
   * <p>리포트가 "선별검사를 받아보세요"를 스스로 말하지 못하게 막는 자리다. 등록부의 모든 도구가 승인 전이라 지금은 언제나 {@code false} 이며,
   * <strong>그 사실이 코드로 확인된다는 것이 이 메서드의 요점이다.</strong>
   *
   * @param childAgeMonths 아동 나이(개월)이며 모르면 {@code null}
   * @return 제공 가능한 도구가 있으면 {@code true}
   */
  public static boolean hasOfferableInstrument(Integer childAgeMonths) {
    return ScreeningInstrumentRegistry.all().stream()
        .map(instrument -> decide(instrument, childAgeMonths, false))
        .anyMatch(state -> state == ScreeningOfferState.OFFERABLE_AFTER_CONSENT);
  }
}
