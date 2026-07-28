package com.ssafy.b209.drawing.htp.domain;

import java.util.Optional;

/** HTP 활동에서 서버가 고정 순서로 제시하는 그림 주제다. */
public enum HtpDrawingSubject {
  /** 첫 번째 집 그림이다. */
  HOUSE,
  /** 두 번째 나무 그림이다. */
  TREE,
  /** 세 번째 사람 그림이다. */
  PERSON;

  /**
   * HTP 계약에 따른 다음 그림 주제를 반환한다.
   *
   * @return 다음 주제, 사람 그림이 마지막이면 빈 값
   */
  public Optional<HtpDrawingSubject> next() {
    return switch (this) {
      case HOUSE -> Optional.of(TREE);
      case TREE -> Optional.of(PERSON);
      case PERSON -> Optional.empty();
    };
  }
}
