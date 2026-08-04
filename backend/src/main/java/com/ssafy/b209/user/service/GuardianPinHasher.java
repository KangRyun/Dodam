package com.ssafy.b209.user.service;

import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.user.exception.GuardianPinErrorCode;
import java.nio.charset.StandardCharsets;
import java.security.InvalidKeyException;
import java.security.NoSuchAlgorithmException;
import java.util.Base64;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.stereotype.Component;

/**
 * 보호자 PIN 을 pepper 적용 후 BCrypt 로 해시하고 비교한다 (S15P11B209-879).
 *
 * <p><b>왜 두 단계인가.</b> 4자리 PIN 은 조합이 10,000개뿐이라, BCrypt 만 쓰면 DB 유출 시 전수 시도로 원문이 복원된다(강도 12에서도 수십 분
 * 규모다). pepper 키는 DB 가 아니라 시크릿에 있으므로, 해시만 가진 공격자는 대조할 입력을 만들 수 없다. 반대로 pepper 만 쓰면 같은 PIN 이 같은 값으로
 * 저장돼 사용자 간 비교가 가능해진다 — BCrypt 의 salt 가 그것을 막는다. 둘은 서로를 대체하지 않는다.
 *
 * <p>PIN 원문은 이 클래스 밖으로 나가지 않고, 로그에도 남기지 않는다. 예외 메시지에도 넣지 않는다.
 */
@Component
public class GuardianPinHasher {

  /** 저장 행에 남기는 알고리즘 식별자. 장차 알고리즘을 바꿀 때 기존 행을 구분하는 표식이다. */
  static final String ALGORITHM = "HMAC_SHA256+BCRYPT";

  private static final String MAC_ALGORITHM = "HmacSHA256";

  private final GuardianPinProperties properties;
  private final BCryptPasswordEncoder encoder;

  /**
   * pepper 설정과 BCrypt 인코더를 준비한다.
   *
   * @param properties pepper·강도 설정
   */
  public GuardianPinHasher(GuardianPinProperties properties) {
    this.properties = properties;
    this.encoder = new BCryptPasswordEncoder(properties.getHashStrength());
  }

  /**
   * @return pepper 가 구성돼 PIN 을 다룰 수 있는지
   */
  public boolean isConfigured() {
    return properties.isConfigured();
  }

  /** pepper 가 없으면 PIN 을 다룰 수 없다. 호출부보다 여기서 먼저 막아 미구성 상태로 해시가 만들어지는 것을 방지한다. */
  private void requireConfigured() {
    if (!isConfigured()) {
      throw new BusinessException(GuardianPinErrorCode.PIN_UNAVAILABLE);
    }
  }

  /**
   * PIN 을 저장 가능한 해시로 만든다.
   *
   * @param rawPin 숫자 4자리 PIN 원문
   * @return pepper 를 거친 값의 BCrypt 해시
   */
  public String hash(String rawPin) {
    requireConfigured();
    return encoder.encode(peppered(rawPin));
  }

  /**
   * 저장된 해시와 입력 PIN 이 같은지 비교한다.
   *
   * @param rawPin 입력 PIN 원문
   * @param storedHash 저장된 해시
   * @return 일치하면 {@code true}
   */
  public boolean matches(String rawPin, String storedHash) {
    requireConfigured();
    return encoder.matches(peppered(rawPin), storedHash);
  }

  /**
   * @return 저장 행에 남길 알고리즘 식별자
   */
  public String algorithm() {
    return ALGORITHM;
  }

  /**
   * PIN 에 pepper 를 적용한다.
   *
   * <p>BCrypt 는 입력 72바이트를 넘기면 뒤를 자르므로, HMAC 결과를 Base64 로 인코딩해 길이를 44자로 고정한다(원문 길이가 해시 입력 길이에 영향을 주지
   * 않는다).
   */
  private String peppered(String rawPin) {
    try {
      Mac mac = Mac.getInstance(MAC_ALGORITHM);
      mac.init(
          new SecretKeySpec(
              properties.getPepper().getBytes(StandardCharsets.UTF_8), MAC_ALGORITHM));
      return Base64.getEncoder()
          .encodeToString(mac.doFinal(rawPin.getBytes(StandardCharsets.UTF_8)));
    } catch (NoSuchAlgorithmException | InvalidKeyException exception) {
      // 메시지에 PIN 이 섞이지 않도록 예외 원문을 그대로 올리지 않는다.
      throw new BusinessException(GuardianPinErrorCode.PIN_UNAVAILABLE);
    }
  }
}
