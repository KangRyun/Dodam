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
import java.util.Objects;

/**
 * {@code comments} 테이블에 저장되는 커뮤니티 댓글이다.
 *
 * <p>작성자와 익명 여부는 감사 목적으로 유지하며 삭제 요청은 본문을 물리 삭제하지 않고 상태와 삭제 시각을 변경한다.
 */
@Entity
@Table(name = "comments")
public class CommunityComment {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @Column(name = "post_id", nullable = false)
  private Long postId;

  @Column(name = "author_user_id")
  private Long authorUserId;

  @Column(name = "content", nullable = false, columnDefinition = "TEXT")
  private String content;

  @Column(name = "is_anonymous", nullable = false)
  private boolean anonymous;

  @Column(name = "is_visible", nullable = false)
  private boolean visible;

  @Enumerated(EnumType.STRING)
  @Column(name = "comment_status", nullable = false, length = 20)
  private CommentStatus commentStatus;

  @Column(name = "created_at", nullable = false)
  private LocalDateTime createdAt;

  @Column(name = "updated_at", nullable = false)
  private LocalDateTime updatedAt;

  @Column(name = "deleted_at")
  private LocalDateTime deletedAt;

  /** JPA가 댓글을 복원할 때 사용하는 생성자다. */
  protected CommunityComment() {}

  private CommunityComment(
      Long postId, Long authorUserId, String content, boolean anonymous, LocalDateTime now) {
    this.postId = Objects.requireNonNull(postId, "postId must not be null");
    this.authorUserId = Objects.requireNonNull(authorUserId, "authorUserId must not be null");
    this.content = Objects.requireNonNull(content, "content must not be null");
    this.anonymous = anonymous;
    this.visible = true;
    this.commentStatus = CommentStatus.ACTIVE;
    this.createdAt = Objects.requireNonNull(now, "now must not be null");
    this.updatedAt = now;
  }

  /**
   * 공개 상태의 새 댓글을 생성한다.
   *
   * @param postId 소속 게시글 ID
   * @param authorUserId 작성자 사용자 ID
   * @param content 댓글 본문
   * @param anonymous 익명 표시 여부
   * @param now 생성 시각
   * @return 저장 전 댓글
   */
  public static CommunityComment create(
      Long postId, Long authorUserId, String content, boolean anonymous, LocalDateTime now) {
    return new CommunityComment(postId, authorUserId, content, anonymous, now);
  }

  /**
   * 작성자 요청으로 본문과 수정 시각을 변경한다.
   *
   * @param content 교체할 댓글 본문
   * @param now 수정 시각
   */
  public void updateContent(String content, LocalDateTime now) {
    this.content = Objects.requireNonNull(content, "content must not be null");
    this.updatedAt = Objects.requireNonNull(now, "now must not be null");
  }

  /**
   * 작성자 또는 관리자 요청으로 댓글을 Soft Delete한다.
   *
   * @param now 삭제 처리 시각
   */
  public void softDelete(LocalDateTime now) {
    this.commentStatus = CommentStatus.DELETED;
    this.deletedAt = Objects.requireNonNull(now, "now must not be null");
    this.updatedAt = now;
  }

  /**
   * @return 저장 후 채번된 댓글 ID
   */
  public Long getId() {
    return id;
  }

  /**
   * @return 소속 게시글 ID
   */
  public Long getPostId() {
    return postId;
  }

  /**
   * @return 감사 목적으로 유지하는 작성자 사용자 ID
   */
  public Long getAuthorUserId() {
    return authorUserId;
  }

  /**
   * @return 댓글 본문
   */
  public String getContent() {
    return content;
  }

  /**
   * @return 익명으로 표시해야 하면 {@code true}
   */
  public boolean isAnonymous() {
    return anonymous;
  }

  /**
   * @return 일반 사용자에게 공개되는 댓글이면 {@code true}
   */
  public boolean isVisible() {
    return visible;
  }

  /**
   * @return 댓글의 공개·삭제 상태
   */
  public CommentStatus getCommentStatus() {
    return commentStatus;
  }

  /**
   * @return 생성 시각
   */
  public LocalDateTime getCreatedAt() {
    return createdAt;
  }

  /**
   * @return 마지막 수정 시각
   */
  public LocalDateTime getUpdatedAt() {
    return updatedAt;
  }

  /**
   * @return 삭제 시각, 삭제되지 않았으면 {@code null}
   */
  public LocalDateTime getDeletedAt() {
    return deletedAt;
  }
}
