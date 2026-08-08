package com.ssafy.b209.screening.registry;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

/**
 * 선별 게이트가 지켜야 하는 것을 고정한다.
 *
 * <p>이 테스트가 막는 실패는 하나다 — <strong>승인되지 않은 검사가 아이에게 제안되는 것.</strong> 등록부를 손대다 실수로 도구가 켜지거나, 판정 로직이
 * 느슨해지면 여기서 걸린다.
 */
class ScreeningEligibilityTest {

  @Test
  @DisplayName("등록부의 모든 도구는 승인 전이라 제공되지 않는다")
  void everyInstrumentIsDisabled() {
    List<ScreeningInstrument> instruments = ScreeningInstrumentRegistry.all();

    assertThat(instruments).isNotEmpty();
    assertThat(instruments)
        .as("도구를 켜는 것은 코드 변경이 아니라 라이선스·임상 승인 절차다")
        .allSatisfy(
            instrument -> {
              assertThat(instrument.state()).isEqualTo(ScreeningInstrumentState.DISABLED);
              assertThat(instrument.blockers()).isNotEmpty();
            });
  }

  @ParameterizedTest(name = "만 {0}세에게 제공 가능한 도구가 없다")
  @ValueSource(ints = {3, 4, 5, 6, 7, 8, 10, 12, 15})
  @DisplayName("어떤 나이에도 제공 가능한 도구가 없다")
  void noInstrumentIsOfferableAtAnyAge(int years) {
    assertThat(ScreeningEligibility.hasOfferableInstrument(years * 12)).isFalse();
  }

  @Test
  @DisplayName("나이를 모르면 제안하지 않는다")
  void unknownAgeIsNotOffered() {
    // 짐작해서 검사를 권하는 것이 가장 나쁘다.
    assertThat(ScreeningEligibility.hasOfferableInstrument(null)).isFalse();
    assertThat(
            ScreeningEligibility.decide(
                ScreeningInstrumentRegistry.find(ScreeningInstrumentRegistry.K_DST).orElseThrow(),
                null,
                false))
        .isEqualTo(ScreeningOfferState.NOT_OFFERED);
  }

  @Test
  @DisplayName("공식 적용 연령 밖이면 라이선스 사정보다 나이가 먼저다")
  void ageComesBeforeLicense() {
    // K-DST 는 9~71개월이다. 만 8세 아이에게는 '라이선스 대기'가 아니라 '연령 밖'이 맞다 —
    //   라이선스가 풀리면 제공될 것처럼 읽히면 안 된다.
    ScreeningInstrument kdst =
        ScreeningInstrumentRegistry.find(ScreeningInstrumentRegistry.K_DST).orElseThrow();

    assertThat(ScreeningEligibility.decide(kdst, 96, false))
        .isEqualTo(ScreeningOfferState.NOT_ELIGIBLE_BY_AGE);
  }

  @Test
  @DisplayName("적용 연령 안이어도 승인 전이면 제공하지 않는다")
  void inAgeRangeButStillBlocked() {
    ScreeningInstrument kdst =
        ScreeningInstrumentRegistry.find(ScreeningInstrumentRegistry.K_DST).orElseThrow();
    ScreeningInstrument pscK =
        ScreeningInstrumentRegistry.find(ScreeningInstrumentRegistry.PSC_K).orElseThrow();

    assertThat(ScreeningEligibility.decide(kdst, 60, false))
        .isEqualTo(ScreeningOfferState.PENDING_CLINICAL_APPROVAL);
    assertThat(ScreeningEligibility.decide(pscK, 96, false))
        .isEqualTo(ScreeningOfferState.PENDING_LICENSE);
  }

  @Test
  @DisplayName("이미 받은 결과가 있으면 '받을 수 없다'고 말하지 않는다")
  void existingResultWins() {
    ScreeningInstrument kdst =
        ScreeningInstrumentRegistry.find(ScreeningInstrumentRegistry.K_DST).orElseThrow();

    // 62개월에 받은 결과를 기록해 둔 아이가 지금 만 8세여도, 그 기록은 사실이다.
    assertThat(ScreeningEligibility.decide(kdst, 96, true))
        .isEqualTo(ScreeningOfferState.EXTERNAL_RESULT_AVAILABLE);
  }

  @Test
  @DisplayName("정확한 한국어판이 정해지지 않은 도구는 나이로 판정하지 않는다")
  void unconfirmedAgeRangeIsNeverEligible() {
    // 임상위원회가 도구를 고르기 전에 범위를 짐작해 넣으면 지어낸 적용 연령이 된다.
    for (String id :
        List.of(
            ScreeningInstrumentRegistry.ANXIETY_SCREEN_KR,
            ScreeningInstrumentRegistry.DEPRESSION_SCREEN_KR)) {
      ScreeningInstrument instrument = ScreeningInstrumentRegistry.find(id).orElseThrow();
      assertThat(instrument.hasConfirmedAgeRange()).isFalse();
      assertThat(ScreeningEligibility.decide(instrument, 120, false))
          .isEqualTo(ScreeningOfferState.NOT_OFFERED);
    }
  }

  @Test
  @DisplayName("등록부에 없는 도구는 존재하지 않는다")
  void unknownInstrumentIsRejected() {
    // 임의의 검사명이 아동 기록에 남지 않게 하는 자리다.
    assertThat(ScreeningInstrumentRegistry.find("MADE_UP_TEST")).isEmpty();
    assertThat(ScreeningInstrumentRegistry.find(null)).isEmpty();
  }

  @Test
  @DisplayName("결과와 함께 나갈 고지 문구가 도구마다 있다")
  void everyInstrumentCarriesDisclosure() {
    assertThat(ScreeningInstrumentRegistry.all())
        .allSatisfy(instrument -> assertThat(instrument.requiredDisclosure()).isNotBlank());
  }
}
