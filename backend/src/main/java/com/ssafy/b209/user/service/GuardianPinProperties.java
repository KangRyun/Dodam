package com.ssafy.b209.user.service;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

/**
 * 보호자 PIN 해시와 초기화 정책 설정이다 (S15P11B209-879).
 *
 * <p>{@code pepper} 는 PIN 해시 앞단에 적용하는 서버 비밀키다. 운영에서는 시크릿으로 주입하며, 비어 있으면 PIN API 만 503으로 거부하고
 * 애플리케이션은 정상 부팅한다 — 기동을 막으면 PIN 과 무관한 기능까지 함께 멈춘다(기기 Token 암호화 키와 같은 방식).
 *
 * <p><b>pepper 를 왜 두는가.</b> 4자리 PIN 은 조합이 10,000개뿐이다. BCrypt 로 해시해도 DB 가 유출되면 전수 시도로 원문을 복원할 수 있다.
 * pepper 키는 DB 밖에 있으므로, 해시만 가진 공격자는 시도할 입력 자체를 만들 수 없다.
 */
@Component
@ConfigurationProperties(prefix = "app.security.guardian-pin")
public class GuardianPinProperties {

  private String pepper = "";

  /** BCrypt 강도. 4자리 PIN 은 엔트로피가 낮아 pepper 와 잠금이 주된 방어선이지만, 해시 비용도 기본값보다 높게 둔다. */
  private int hashStrength = 12;

  /**
   * PIN 초기화를 허용하는 소셜 재인증 창(분).
   *
   * <p>{@code users.last_login_at} 이 이 시간 안이어야 초기화를 허용한다. 새 토큰 타입을 만들지 않고 "방금 소셜 로그인을 통과했다"는 사실을
   * 재사용한다. 창이 너무 넓으면 로그인 상태를 오래 유지한 기기에서 아이가 초기화를 눌러 PIN 을 없앨 수 있다.
   */
  private int resetReauthWindowMinutes = 5;

  public String getPepper() {
    return pepper;
  }

  public void setPepper(String pepper) {
    this.pepper = pepper;
  }

  public int getHashStrength() {
    return hashStrength;
  }

  public void setHashStrength(int hashStrength) {
    this.hashStrength = hashStrength;
  }

  public int getResetReauthWindowMinutes() {
    return resetReauthWindowMinutes;
  }

  public void setResetReauthWindowMinutes(int resetReauthWindowMinutes) {
    this.resetReauthWindowMinutes = resetReauthWindowMinutes;
  }

  /**
   * @return pepper 가 구성돼 PIN 을 다룰 수 있는 상태인지
   */
  public boolean isConfigured() {
    return pepper != null && !pepper.isBlank();
  }
}
