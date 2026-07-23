package com.ssafy.b209.auth.service;

/** Redis가 원자적으로 판정한 Refresh Token rotation 결과다. */
public enum RefreshTokenRotationResult {
  /** 현재 Token이 확인되어 새 Token으로 교체되었다. */
  ROTATED,
  /** 세션이 없거나 만료되었다. */
  INVALID,
  /** 요청 기기가 최초 로그인 기기와 다르다. */
  DEVICE_MISMATCH,
  /** 현재 Token이 아닌 같은 family의 과거 Token이 제시되어 family가 폐기되었다. */
  REUSED
}
