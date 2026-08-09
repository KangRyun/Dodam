package com.ssafy.b209.notification.push;

import java.util.Map;

/**
 * 한 기기로 보낼 data-only 푸시 메시지다.
 *
 * <p>계약(§0-1)에 따라 {@code notification} 블록 없이 {@code data} 맵만으로 구성한다. FCM data 제약상 모든 값은 문자열이며, 표시
 * 문구도 data에 담아 앱이 표시를 통제한다.
 *
 * @param token 발송 대상 기기 Token 원문
 * @param data 문자열 키·값으로 구성한 페이로드
 */
public record PushMessage(String token, Map<String, String> data) {}
