package com.ssafy.b209.user.dto.response;

import io.swagger.v3.oas.annotations.media.Schema;

/**
 * 사용자에게 적용되는 데이터 보관 정책을 전달한다.
 *
 * <p>저장 위치는 {@code user_data_retention_settings}이며, 행이 없는 사용자에게는 컬럼 DEFAULT와 동일한 값을 반환한다.
 *
 * <p>보관 기간 수치는 아직 팀·자문 확정 전이다. 인프라 정책 문서가 {@code images/audio/reports} 보존기간을 {@code [결정 대기]}로 두고 임의
 * 수치를 금지하므로, 여기서는 새 수치를 만들지 않고 보관 만료 알림(S15P11B209-557)이 이미 사용하는 기준값을 잠정 기본값으로 승격했다. 확정 전임을 소비자가
 * 구분할 수 있도록 {@link #policyStatus}에 {@link #PROVISIONAL}을 함께 내려준다.
 *
 * <p>또한 보관 기간이 지난 파일을 실제로 지우는 소비자(삭제 큐 워커)는 아직 없다. 그래서 이 응답은 "며칠 뒤 삭제된다"는 보장을 표현하지 않고 현재 적용 중인 보관
 * 기간과 확정 여부만 나타낸다.
 *
 * @param retentionDays 데이터를 보관하는 기간(일)
 * @param noticeDaysBefore 보관 만료 며칠 전에 안내하는지(일)
 * @param policyStatus 보관 정책 수치의 확정 상태
 */
@Schema(description = "사용자 데이터 보관 정책")
public record DataRetentionPolicyResponse(
    @Schema(description = "데이터 보관 기간(일)", example = "180") int retentionDays,
    @Schema(description = "보관 만료 사전 안내 시점(일)", example = "30") int noticeDaysBefore,
    @Schema(description = "보관 정책 수치의 확정 상태", example = "PROVISIONAL") String policyStatus) {

  /** 보관 기간 수치가 팀 확정 전 잠정값임을 나타내는 상태값이다. */
  public static final String PROVISIONAL = "PROVISIONAL";

  /** 보관 설정 행이 없는 사용자에게 적용할 보관 기간(일)이며 컬럼 DEFAULT와 같다. */
  public static final int DEFAULT_RETENTION_DAYS = 180;

  /** 보관 설정 행이 없는 사용자에게 적용할 사전 안내 시점(일)이며 컬럼 DEFAULT와 같다. */
  public static final int DEFAULT_NOTICE_DAYS_BEFORE = 30;

  /**
   * 저장된 보관 기간으로 응답을 만든다.
   *
   * <p>확정 상태는 저장하지 않고 항상 {@link #PROVISIONAL}로 채운다. 사용자가 값을 바꿀 수 있어도(S15P11B209-565) 그것이 정책 수치의 팀
   * 확정을 뜻하지는 않기 때문이다.
   *
   * @param retentionDays 데이터를 보관하는 기간(일)
   * @param noticeDaysBefore 보관 만료 며칠 전에 안내하는지(일)
   * @return 전달받은 기간과 잠정 상태를 담은 보관 정책 응답
   */
  public static DataRetentionPolicyResponse provisional(int retentionDays, int noticeDaysBefore) {
    return new DataRetentionPolicyResponse(retentionDays, noticeDaysBefore, PROVISIONAL);
  }

  /**
   * 보관 설정 행이 없는 사용자에게 반환할 기본값을 만든다.
   *
   * <p>값은 {@code user_data_retention_settings} 컬럼 DEFAULT와 일치시켜, 행 생성 시점에 응답이 달라지지 않게 한다.
   *
   * @return 컬럼 DEFAULT와 동일한 보관 정책
   */
  public static DataRetentionPolicyResponse defaults() {
    return provisional(DEFAULT_RETENTION_DAYS, DEFAULT_NOTICE_DAYS_BEFORE);
  }
}
