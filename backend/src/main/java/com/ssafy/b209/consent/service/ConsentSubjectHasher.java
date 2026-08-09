package com.ssafy.b209.consent.service;

import com.ssafy.b209.consent.domain.ConsentTargetScope;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.HexFormat;
import org.springframework.stereotype.Component;

/** 삭제 후에도 대상을 직접 노출하지 않고 동의 이력을 연결할 SHA-256 참조 hash를 생성한다. */
@Component
public class ConsentSubjectHasher {

  /** 상태를 보관하지 않는 동의 대상 Hash 생성기를 만든다. */
  public ConsentSubjectHasher() {}

  /**
   * 동의 대상 종류와 ID를 구분한 결정론적 hash를 생성한다.
   *
   * @param scope 사용자 또는 아동 대상 범위
   * @param subjectId 사용자 ID 또는 아동 ID
   * @return 64자 소문자 SHA-256 hash
   */
  public String hash(ConsentTargetScope scope, Long subjectId) {
    try {
      String reference = scope.name() + ":" + subjectId;
      byte[] digest =
          MessageDigest.getInstance("SHA-256").digest(reference.getBytes(StandardCharsets.UTF_8));
      return HexFormat.of().formatHex(digest);
    } catch (NoSuchAlgorithmException exception) {
      throw new IllegalStateException("SHA-256 is not available", exception);
    }
  }
}
