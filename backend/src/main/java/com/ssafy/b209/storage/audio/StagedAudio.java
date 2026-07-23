package com.ssafy.b209.storage.audio;

import java.nio.file.Path;

/**
 * 검증은 끝났지만 멱등성 선점 전이라 영구 보관되지 않은 음성 임시 파일이다.
 *
 * <p>임시 경로는 같은 패키지의 저장 구현체만 사용하며 Controller·응답 DTO로 전달하지 않는다.
 */
public final class StagedAudio {
  private final Path temporaryFile;
  private final AudioFormat format;
  private final long size;
  private final String checksumSha256;
  private final long durationMillis;

  StagedAudio(
      Path temporaryFile,
      AudioFormat format,
      long size,
      String checksumSha256,
      long durationMillis) {
    this.temporaryFile = temporaryFile;
    this.format = format;
    this.size = size;
    this.checksumSha256 = checksumSha256;
    this.durationMillis = durationMillis;
  }

  Path temporaryFile() {
    return temporaryFile;
  }

  AudioFormat format() {
    return format;
  }

  /**
   * @return 실제 저장된 Byte 수
   */
  public long size() {
    return size;
  }

  /**
   * @return 원본 Byte의 SHA-256 Hex
   */
  public String checksumSha256() {
    return checksumSha256;
  }

  /**
   * @return 검증 가능한 컨테이너 또는 프레임 기준 길이(ms)
   */
  public long durationMillis() {
    return durationMillis;
  }
}
