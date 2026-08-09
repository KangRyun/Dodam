package com.ssafy.b209.conversation.dto;

/** 캔버스 크기에 대해 0~1로 정규화한 사각형 좌표다. */
public record BoundingBox(double x, double y, double width, double height) {

  public boolean isNormalized() {
    return x >= 0
        && y >= 0
        && width >= 0
        && height >= 0
        && x <= 1
        && y <= 1
        && width <= 1
        && height <= 1
        && x + width <= 1
        && y + height <= 1;
  }
}
