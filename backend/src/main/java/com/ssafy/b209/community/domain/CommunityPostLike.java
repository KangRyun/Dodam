package com.ssafy.b209.community.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.LocalDateTime;
import java.util.Objects;

/**
 * 인증 사용자가 커뮤니티 게시글에 표시한 좋아요 한 건을 나타낸다.
 *
 * <p>{@code post_likes}의 게시글·사용자 유일 제약과 함께 한 사용자가 같은 게시글에 여러 좋아요를 만들지 못하게 한다.
 */
@Entity
@Table(name = "post_likes")
public class CommunityPostLike {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @Column(name = "post_id", nullable = false)
  private Long postId;

  @Column(name = "user_id", nullable = false)
  private Long userId;

  @Column(name = "created_at", nullable = false)
  private LocalDateTime createdAt;

  /** JPA가 좋아요를 복원할 때 사용하는 생성자다. */
  protected CommunityPostLike() {}

  private CommunityPostLike(Long postId, Long userId, LocalDateTime createdAt) {
    this.postId = Objects.requireNonNull(postId, "postId must not be null");
    this.userId = Objects.requireNonNull(userId, "userId must not be null");
    this.createdAt = Objects.requireNonNull(createdAt, "createdAt must not be null");
  }

  /**
   * 게시글과 사용자 조합의 새 좋아요를 생성한다.
   *
   * @param postId 좋아요 대상 게시글 ID
   * @param userId 좋아요를 표시한 사용자 ID
   * @param createdAt 생성 시각
   * @return 저장 전 좋아요
   */
  public static CommunityPostLike create(Long postId, Long userId, LocalDateTime createdAt) {
    return new CommunityPostLike(postId, userId, createdAt);
  }
}
