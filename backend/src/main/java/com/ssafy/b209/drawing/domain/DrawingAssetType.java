package com.ssafy.b209.drawing.domain;

/** 그림 활동 과정에서 저장되는 파일의 용도를 구분한다. */
public enum DrawingAssetType {
  /** 편집 중인 임시 초안 파일이다. */
  DRAFT,
  /** 그림 활동 진행 중 분석 등에 사용하는 중간 스냅샷이다. */
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
