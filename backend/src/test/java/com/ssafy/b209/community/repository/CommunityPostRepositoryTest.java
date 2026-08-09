package com.ssafy.b209.community.repository;

import static org.assertj.core.api.Assertions.assertThat;

import com.ssafy.b209.community.domain.CommunityPost;
import com.ssafy.b209.community.domain.PostType;
import jakarta.persistence.EntityManager;
import java.time.LocalDateTime;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.test.context.ActiveProfiles;

@DataJpaTest
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@ActiveProfiles("test")
class CommunityPostRepositoryTest {

  private static final LocalDateTime NOW = LocalDateTime.parse("2026-07-24T00:00:00");

  @Autowired private EntityManager entityManager;

  @Autowired private CommunityPostRepository communityPostRepository;

  @Test
  void findsActiveNotDeletedPostForUpdate() {
    CommunityPost saved =
        communityPostRepository.saveAndFlush(
            CommunityPost.create(null, PostType.GUARDIAN_STORY, "제목", "본문", false, NOW));
    entityManager.flush();
    entityManager.clear();

    assertThat(communityPostRepository.findNotDeletedByIdForUpdate(saved.getId())).isPresent();
  }

  @Test
  void excludesSoftDeletedPost() {
    CommunityPost saved =
        communityPostRepository.saveAndFlush(
            CommunityPost.create(null, PostType.GUARDIAN_STORY, "제목", "본문", false, NOW));
    saved.softDelete(NOW);
    communityPostRepository.saveAndFlush(saved);
    entityManager.flush();
    entityManager.clear();

    assertThat(communityPostRepository.findNotDeletedByIdForUpdate(saved.getId())).isEmpty();
  }

  @Test
  void returnsEmptyForMissingId() {
    assertThat(communityPostRepository.findNotDeletedByIdForUpdate(999_999L)).isEmpty();
  }
}
