package com.ssafy.b209.community.domain;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.time.LocalDateTime;
import org.junit.jupiter.api.Test;

class CommunityPostDomainTest {

  private static final LocalDateTime CREATED = LocalDateTime.parse("2026-07-24T00:00:00");
  private static final LocalDateTime UPDATED = LocalDateTime.parse("2026-07-24T01:00:00");

  @Test
  void updateReplacesEditableFieldsAndBumpsUpdatedAt() {
    CommunityPost post =
        CommunityPost.create(7L, PostType.GUARDIAN_STORY, "제목", "본문", false, CREATED);

    post.update(PostType.EXPERT_QNA, "새 제목", "새 본문", true, UPDATED);

    assertThat(post.getPostType()).isEqualTo(PostType.EXPERT_QNA);
    assertThat(post.getTitle()).isEqualTo("새 제목");
    assertThat(post.getContent()).isEqualTo("새 본문");
    assertThat(post.isAnonymous()).isTrue();
    assertThat(post.getUpdatedAt()).isEqualTo(UPDATED);
    assertThat(post.getCreatedAt()).isEqualTo(CREATED);
    assertThat(post.getPostStatus()).isEqualTo(PostStatus.ACTIVE);
    assertThat(post.isVisible()).isTrue();
    assertThat(post.getDeletedAt()).isNull();
  }

  @Test
  void updateRejectsNullRequiredFields() {
    CommunityPost post =
        CommunityPost.create(7L, PostType.GUARDIAN_STORY, "제목", "본문", false, CREATED);

    assertThatThrownBy(() -> post.update(null, "제목", "본문", false, UPDATED))
        .isInstanceOf(NullPointerException.class);
    assertThatThrownBy(() -> post.update(PostType.GUARDIAN_STORY, "제목", "본문", false, null))
        .isInstanceOf(NullPointerException.class);
  }

  @Test
  void softDeleteMarksPostDeletedAndRecordsTimestamp() {
    CommunityPost post =
        CommunityPost.create(7L, PostType.GUARDIAN_STORY, "제목", "본문", false, CREATED);

    post.softDelete(UPDATED);

    assertThat(post.getPostStatus()).isEqualTo(PostStatus.DELETED);
    assertThat(post.getDeletedAt()).isEqualTo(UPDATED);
  }

  @Test
  void softDeleteRejectsAlreadyDeletedPost() {
    CommunityPost post =
        CommunityPost.create(7L, PostType.GUARDIAN_STORY, "제목", "본문", false, CREATED);
    post.softDelete(UPDATED);

    assertThatThrownBy(() -> post.softDelete(UPDATED)).isInstanceOf(IllegalStateException.class);
  }

  @Test
  void softDeleteRejectsNullTimestamp() {
    CommunityPost post =
        CommunityPost.create(7L, PostType.GUARDIAN_STORY, "제목", "본문", false, CREATED);

    assertThatThrownBy(() -> post.softDelete(null)).isInstanceOf(NullPointerException.class);
  }
}
