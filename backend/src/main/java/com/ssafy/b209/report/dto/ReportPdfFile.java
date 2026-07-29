package com.ssafy.b209.report.dto;

import java.util.Arrays;
import java.util.Objects;

/**
 * HTTP 응답으로 전송할 관찰 리포트 PDF 파일이다.
 *
 * <p>가변 배열의 외부 변경으로 응답 내용이 달라지지 않도록 생성과 조회 시 방어 복사한다.
 *
 * @param fileName 다운로드 파일명
 * @param content PDF 바이트
 */
public record ReportPdfFile(String fileName, byte[] content) {

  public ReportPdfFile {
    if (fileName == null || fileName.isBlank()) {
      throw new IllegalArgumentException("fileName must not be blank");
    }
    content =
        Arrays.copyOf(Objects.requireNonNull(content, "content must not be null"), content.length);
  }

  @Override
  public byte[] content() {
    return Arrays.copyOf(content, content.length);
  }
}
