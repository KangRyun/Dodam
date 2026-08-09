package com.ssafy.b209.report.service;

import java.util.Objects;

/**
 * 리포트 PDF 에 실을 이미지 한 장이다.
 *
 * <p>렌더러가 저장 위치·인증 방식을 모르고도 배치할 수 있도록 바이트와 크기만 담는다. 픽셀 크기를 함께 주는 이유는 렌더러가 종이 위 배치 크기를 비율로 계산해야 하기
 * 때문이다 — 크기를 모르면 이미지를 늘이거나 찌그러뜨린다.
 *
 * @param bytes 이미지 원본 바이트
 * @param mimeType 저장소가 검증한 MIME Type
 * @param widthPx 가로 픽셀 수
 * @param heightPx 세로 픽셀 수
 */
public record ReportImageAsset(byte[] bytes, String mimeType, int widthPx, int heightPx) {

  /** 렌더러가 배치 계산에 쓸 수 있는 값인지 검증한다. */
  public ReportImageAsset {
    Objects.requireNonNull(bytes, "bytes must not be null");
    if (bytes.length == 0) {
      throw new IllegalArgumentException("bytes must not be empty");
    }
    if (mimeType == null || mimeType.isBlank()) {
      throw new IllegalArgumentException("mimeType must not be blank");
    }
    if (widthPx <= 0 || heightPx <= 0) {
      throw new IllegalArgumentException("image dimensions must be positive");
    }
  }

  /**
   * 세로/가로 비율이다. 종이 폭에 맞춰 높이를 정할 때 쓴다.
   *
   * @return 높이를 폭으로 나눈 값
   */
  public double aspectRatio() {
    return (double) heightPx / widthPx;
  }

  /** 바이트 배열 내용을 로그로 흘리지 않는다. */
  @Override
  public String toString() {
    return "ReportImageAsset[mimeType="
        + mimeType
        + ", widthPx="
        + widthPx
        + ", heightPx="
        + heightPx
        + ", size="
        + bytes.length
        + "]";
  }
}
