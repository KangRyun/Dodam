package com.ssafy.b209.infrastructure.push;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.InvalidPathException;
import java.nio.file.Path;

/**
 * FCM Service Account 자격증명 파일을 실제로 쓸 수 있는지 판정한다.
 *
 * <p>Bean 생성 <em>전에</em> 조건으로 평가되어야 하므로 Spring Bean 이 아니라 정적 유틸이다({@link FcmAvailableCondition}).
 * 파일을 여는 것은 판정 시점의 한 번뿐이며, 내용 파싱이나 네트워크 호출은 하지 않는다.
 *
 * <p>판정을 두는 이유: 자격증명을 읽지 못하면 {@code FirebaseApp} 초기화가 예외로 끝나 애플리케이션 컨텍스트 전체가 붕괴한다. 푸시는 부가 기능이므로 그
 * 실패가 서비스 전면 중단으로 번져서는 안 된다(S15P11B209-681).
 */
public final class FcmCredentials {

  private FcmCredentials() {}

  /**
   * 자격증명 사용 가능 여부와 불가 사유를 함께 담는다.
   *
   * @param usable 발송에 쓸 수 있으면 {@code true}
   * @param reason 불가 사유(사용 가능하면 {@code null}). 경로 외의 내용은 담지 않는다
   */
  public record Availability(boolean usable, String reason) {

    static Availability ok() {
      return new Availability(true, null);
    }

    static Availability blocked(String reason) {
      return new Availability(false, reason);
    }
  }

  /**
   * 주어진 경로의 자격증명이 발송에 쓸 수 있는 상태인지 확인한다.
   *
   * <p>다음을 모두 만족해야 사용 가능으로 본다.
   *
   * <ul>
   *   <li>경로가 비어 있지 않다
   *   <li>읽을 수 있다 — 파일이 없거나 권한이 없으면 여기서 걸린다. 2026-07-28 장애의 실제 원인은 권한이었다(호스트 {@code 600 root}, 컨테이너
   *       실행 계정은 비-root)
   *   <li>일반 파일이다 — compose 의 secret 기본 소스가 {@code /dev/null} 이라 문자 장치가 마운트될 수 있다
   *   <li>내용이 비어 있지 않다 — 자리만 잡아 둔 빈 파일을 정상으로 오인하지 않기 위함
   * </ul>
   *
   * @param credentialsPath 컨테이너 안에서의 자격증명 절대 경로
   * @return 사용 가능 여부와 불가 사유
   */
  public static Availability inspect(String credentialsPath) {
    if (credentialsPath == null || credentialsPath.isBlank()) {
      return Availability.blocked("자격증명 경로가 설정되지 않았습니다");
    }
    Path path;
    try {
      path = Path.of(credentialsPath);
    } catch (InvalidPathException exception) {
      return Availability.blocked("자격증명 경로 형식이 올바르지 않습니다");
    }
    if (!Files.isReadable(path)) {
      return Availability.blocked("자격증명 파일이 없거나 읽을 권한이 없습니다");
    }
    if (!Files.isRegularFile(path)) {
      return Availability.blocked("자격증명 경로가 일반 파일이 아닙니다");
    }
    try {
      if (Files.size(path) == 0L) {
        return Availability.blocked("자격증명 파일이 비어 있습니다");
      }
    } catch (IOException exception) {
      return Availability.blocked("자격증명 파일 크기를 확인하지 못했습니다");
    }
    return Availability.ok();
  }
}
