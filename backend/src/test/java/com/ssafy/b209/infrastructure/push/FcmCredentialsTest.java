package com.ssafy.b209.infrastructure.push;

import static org.assertj.core.api.Assertions.assertThat;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.attribute.PosixFilePermissions;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.junit.jupiter.api.condition.DisabledOnOs;
import org.junit.jupiter.api.condition.OS;

class FcmCredentialsTest {

  @TempDir Path tempDir;

  @Test
  void 내용이_있는_읽을_수_있는_파일은_사용_가능하다() throws IOException {
    Path credentials = Files.writeString(tempDir.resolve("sa.json"), "{\"type\":\"service_account\"}");

    FcmCredentials.Availability availability = FcmCredentials.inspect(credentials.toString());

    assertThat(availability.usable()).isTrue();
    assertThat(availability.reason()).isNull();
  }

  @Test
  void 파일이_없으면_사용할_수_없다() {
    FcmCredentials.Availability availability =
        FcmCredentials.inspect(tempDir.resolve("없는파일.json").toString());

    assertThat(availability.usable()).isFalse();
    assertThat(availability.reason()).contains("없거나 읽을 권한이 없습니다");
  }

  @Test
  void 빈_파일은_사용할_수_없다() throws IOException {
    // compose 의 secret 기본 소스가 /dev/null 이라 자리만 잡은 빈 파일이 마운트될 수 있다.
    Path empty = Files.createFile(tempDir.resolve("empty.json"));

    FcmCredentials.Availability availability = FcmCredentials.inspect(empty.toString());

    assertThat(availability.usable()).isFalse();
    assertThat(availability.reason()).contains("비어 있습니다");
  }

  @Test
  void 경로가_비어_있으면_사용할_수_없다() {
    assertThat(FcmCredentials.inspect(null).usable()).isFalse();
    assertThat(FcmCredentials.inspect("  ").usable()).isFalse();
  }

  @Test
  void 디렉토리는_사용할_수_없다() {
    FcmCredentials.Availability availability = FcmCredentials.inspect(tempDir.toString());

    assertThat(availability.usable()).isFalse();
    assertThat(availability.reason()).contains("일반 파일이 아닙니다");
  }

  @Test
  @DisabledOnOs(OS.WINDOWS)
  void 읽을_권한이_없으면_사용할_수_없다() throws IOException {
    // 2026-07-28 장애의 실제 원인. 호스트 파일이 600 root 라 비-root 컨테이너 계정이 열지 못했다.
    Path unreadable = Files.writeString(tempDir.resolve("locked.json"), "{}");
    Files.setPosixFilePermissions(unreadable, PosixFilePermissions.fromString("-w--w--w-"));

    FcmCredentials.Availability availability = FcmCredentials.inspect(unreadable.toString());

    assertThat(availability.usable()).isFalse();
    assertThat(availability.reason()).contains("읽을 권한이 없습니다");
  }
}
