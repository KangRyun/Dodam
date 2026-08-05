package com.ssafy.b209.report.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.LocalDateTime;

/**
 * 리포트 표지에 쓸 아동 표시명만 읽는 읽기 모델이다 (875 §2 {@code childDisplayName}).
 *
 * <p><b>표시명(별명) 하나만 읽는다.</b> 생년월일 등 다른 아동 정보는 이 화면에 필요하지 않고, 읽을 수 있게 열어 두면 언젠가 응답에 실린다 — 아동 민감정보를
 * 다루는 서비스라 조회 범위 자체를 좁히는 것이 방어다(CLAUDE.md 9절). {@code children} 테이블에서 별명 외의 컬럼은 매핑하지 않는다.
 *
 * <p>삭제 시각을 함께 읽는 이유는 <b>지워진 아동의 표시명을 리포트에 되살리지 않기 위해서</b>다. 보관 기간·탈퇴로 아동 데이터를 지웠는데 리포트 표지에 이름이 남으면
 * 삭제가 끝나지 않은 것이 된다.
 */
@Entity
@Table(name = "children")
public class ReportChildView {

  @Id private Long id;

  @Column(name = "nickname", nullable = false)
  private String nickname;

  @Column(name = "deleted_at")
  private LocalDateTime deletedAt;

  /** JPA가 Entity를 복원할 때 사용하는 생성자다. */
  protected ReportChildView() {}

  /**
   * 리포트 표지에 노출할 표시명을 돌려준다.
   *
   * @return 아동 표시명이며 삭제된 아동이면 {@code null}
   */
  public String displayName() {
    return deletedAt == null ? nickname : null;
  }
}
