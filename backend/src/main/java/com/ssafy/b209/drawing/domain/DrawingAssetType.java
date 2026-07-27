package com.ssafy.b209.drawing.domain;

/** 그림 활동 과정에서 저장되는 파일의 용도를 구분한다. */
public enum DrawingAssetType {
  /** 편집 중 자동 저장되는 초안 파일이다. 공개 그림 분석(OBJECT_DETECTION)의 INTERMEDIATE 범위 대상이 이 유형이다. */
  DRAFT,
  /** 스냅샷 업로드 API로 저장하는 활동 중간 스냅샷이다. 공개 분석 요청 대상은 아니며(계약상 거부), 중간 분석은 DRAFT를 사용한다. */
  INTERMEDIATE,
  /** 그림 활동의 최종 결과를 나타내는 스냅샷이다. */
  FINAL,
  /** 사용자가 기존 파일을 업로드해 시작한 원본 이미지다. */
  UPLOADED,
  /** 목록과 미리보기에 사용하는 축소 이미지다. */
  THUMBNAIL,
  /** 그림 활동 과정을 재생하기 위한 파일이다. */
  TIMELAPSE;

  /**
   * 스냅샷 업로드 API에서 저장할 수 있는 유형인지 확인한다.
   *
   * @return 중간 또는 최종 스냅샷이면 {@code true}
   */
  public boolean isSnapshotUploadType() {
    return this == INTERMEDIATE || this == FINAL;
  }
}
