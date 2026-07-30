package com.ssafy.b209.drawing.config;

import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * MySQL {@code stroke_*} 테이블을 MongoDB로 옮기는 일회성 이관 러너의 스위치를 Binding한다 (S15P11B209-365).
 *
 * <p><b>기본은 꺼짐이다.</b> 켜두면 배포·재시작마다 전량을 다시 읽는다. upsert 라 데이터가 깨지지는 않지만 기동 시간을 갉아먹는다. 한 번 켜서 돌리고 즉시
 * 되돌리는 용도로 설계했다.
 *
 * @param enabled 이관 실행 여부
 * @param batchSize 한 번에 읽어 옮길 배치 수. 1 이상이어야 한다
 */
@ConfigurationProperties(prefix = "app.stroke.mongo-backfill")
public record StrokeMongoBackfillProperties(boolean enabled, int batchSize) {

  /**
   * 이관이 무한 반복하거나 메모리를 통째로 점유하지 않도록 불변 조건을 검증한다.
   *
   * @param enabled 이관 실행 여부
   * @param batchSize 한 번에 읽어 옮길 배치 수
   * @throws IllegalArgumentException 페이지 크기가 1 미만인 경우
   */
  public StrokeMongoBackfillProperties {
    if (batchSize < 1) {
      throw new IllegalArgumentException("Stroke backfill batch size must be at least 1");
    }
  }
}
