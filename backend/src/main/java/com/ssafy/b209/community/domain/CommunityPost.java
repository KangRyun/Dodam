package com.ssafy.b209.community.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.LocalDateTime;

/**
 * DB v1.2 {@code community_posts} 테이블에 매핑되는 커뮤니티 게시글 Entity다.
 *
 * <p>커뮤니티 조회 API는 Native Query를 사용하지만 게시글 작성은 팀 표준 JPA 영속화로 처리한다. 첨부와 Template 저장 구조는 이 범위에서 다루지
 * 않으므로 {@code template_data_json}과 첨부 관련 컬럼은 매핑하지 않는다.
 */
@Entity
@Table(name = "community_posts")
public class CommunityPost {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @Column(name = "author_user_id")
  private Long authorUserId;

  @Enumerated(EnumType.STRING)
  @Column(name = "post_type", nullable = false, length = 40)
  private PostType postType;

  @Column(name = "title", nullable = false, length = 200)
  private String title;

  @Column(name = "content", nullable = false, columnDefinition = "LONGTEXT")
  private String content;

  @Column(name = "is_anonymous", nullable = false)
  private boolean anonymous;

  @Column(name = "is_visible", nullable = false)
  private boolean visible;

  @Enumerated(EnumType.STRING)
  @Column(name = "post_status", nullable = false, length = 20)
  private PostStatus postStatus;

  @Column(name = "created_at", nullable = false)
  private LocalDateTime createdAt;

  @Column(name = "updated_at", nullable = false)
  private LocalDateTime updatedAt;

  @Column(name = "deleted_at")
  private LocalDateTime deletedAt;

  /** JPA가 Entity를 복원할 때 사용하는 생성자다. */
  protected CommunityPost() {}

  private CommunityPost(
      Long authorUserId,
      PostType postType,
      String title,
      String content,
      boolean anonymous,
      LocalDateTime now) {
    this.authorUserId = authorUserId;
    this.postType = postType;
    this.title = title;
    this.content = content;
    this.anonymous = anonymous;
    this.visible = true;
    this.postStatus = PostStatus.ACTIVE;
    this.createdAt = now;
    this.updatedAt = now;
    this.deletedAt = null;
  }

  /**
   * 활성·공개 상태의 새 게시글을 생성한다.
   *
   * @param authorUserId 작성자 사용자 ID
   * @param postType 게시글 유형
   * @param title 게시글 제목
   * @param content 게시글 본문
   * @param anonymous 익명 게시글 여부
   * @param now 생성·수정 시각으로 사용할 UTC 기준 시각
   * @return {@link PostStatus#ACTIVE}이고 공개 상태인 새 게시글
   */
  public static CommunityPost create(
      Long authorUserId,
      PostType postType,
      String title,
      String content,
      boolean anonymous,
      LocalDateTime now) {
    return new CommunityPost(authorUserId, postType, title, content, anonymous, now);
  }

  /**
   * 게시글 식별자를 반환한다.
   *
   * @return 저장 후 채번된 게시글 ID, 저장 전에는 {@code null}
   */
  public Long getId() {
    return id;
  }

  /**
   * 작성자 사용자 ID를 반환한다.
   *
   * @return 작성자 사용자 ID
   */
  public Long getAuthorUserId() {
    return authorUserId;
  }

  /**
   * 게시글 유형을 반환한다.
   *
   * @return 게시글 유형
   */
  public PostType getPostType() {
    return postType;
  }

  /**
   * 게시글 제목을 반환한다.
   *
   * @return 게시글 제목
   */
  public String getTitle() {
    return title;
  }

  /**
   * 게시글 본문을 반환한다.
   *
   * @return 게시글 본문
   */
  public String getContent() {
    return content;
  }

  /**
   * 익명 게시글 여부를 반환한다.
   *
   * @return 익명이면 {@code true}
   */
  public boolean isAnonymous() {
    return anonymous;
  }

  /**
   * 게시글 공개 여부를 반환한다.
   *
   * @return 공개 상태이면 {@code true}
   */
  public boolean isVisible() {
    return visible;
  }

  /**
   * 게시글 상태를 반환한다.
   *
   * @return 게시글 노출 상태
   */
  public PostStatus getPostStatus() {
    return postStatus;
  }

  /**
   * 생성 시각을 반환한다.
   *
   * @return UTC 기준 생성 시각
   */
  public LocalDateTime getCreatedAt() {
    return createdAt;
  }

  /**
   * 수정 시각을 반환한다.
   *
   * @return UTC 기준 수정 시각
   */
  public LocalDateTime getUpdatedAt() {
    return updatedAt;
  }
}
