package com.ssafy.b209.referral;

import java.util.regex.Pattern;

/**
 * 의뢰 요약에 실을 아이 발화에서 <strong>불필요한 신원 정보</strong>를 가린다.
 *
 * <p>의뢰 요약은 <strong>가정 밖으로 나가는 문서</strong>다. 앱 안에서 보호자만 보던 발화가 병원·상담실로 옮겨 가므로, 진료에 필요 없는 학교·주소는 빼고
 * 보낸다.
 *
 * <p><strong>사람 이름은 자동으로 가릴 수 없다.</strong> "민준이가 밀었어"에서 민준이가 친구인지 동생인지 강아지인지 코드로는 알 수 없고, 짐작해 지우면
 * 진료에 필요한 관계 정보까지 사라진다. 그래서 이름은 건드리지 않고, 대신 보호자가 공유 전에 확인하도록 요약에 안내를 함께 싣는다.
 *
 * <p>가리는 것은 <strong>형태로 확실히 알아볼 수 있는 것</strong>뿐이다 — 학교·유치원·어린이집 이름과 아파트 동호수. 애매한 패턴을 넣으면 평범한 발화가
 * 훼손돼 오히려 진료를 방해한다.
 */
public final class ReferralTextRedactor {

  /** 가린 자리 표시다. 지웠다는 사실 자체는 남겨야 전문가가 빈 곳을 오해하지 않는다. */
  private static final String MASK = "○○";

  private static final Pattern SCHOOL =
      Pattern.compile("\\S{1,12}?(초등학교|중학교|고등학교|유치원|어린이집|초등학교병설유치원)");

  private static final Pattern APARTMENT_UNIT = Pattern.compile("\\d{1,4}\\s*동\\s*\\d{1,5}\\s*호");

  private ReferralTextRedactor() {}

  /**
   * 발화 한 줄에서 학교·주소 형태를 가린다.
   *
   * @param text 아이가 한 말 그대로이며 {@code null}이면 그대로 돌려준다
   * @return 가린 문장
   */
  public static String redact(String text) {
    if (text == null || text.isBlank()) {
      return text;
    }
    String redacted = SCHOOL.matcher(text).replaceAll(MASK + "$1");
    return APARTMENT_UNIT.matcher(redacted).replaceAll(MASK + "동 " + MASK + "호");
  }
}
