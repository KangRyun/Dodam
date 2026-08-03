package com.ssafy.b209.community;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.ssafy.b209.auth.token.AuthenticatedUser;
import java.nio.charset.StandardCharsets;
import java.util.List;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.RequestBuilder;
import org.testcontainers.containers.MySQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

/**
 * 커뮤니티 게시글과 댓글 CRUD endpoint를 실 MySQL로 관통 검증하는 통합 테스트다.
 *
 * <p>커뮤니티 단면에는 통합 테스트가 없어 다중 생성자 빈 배선 사고(develop CI #172)가 로컬에서 잡히지 않았다. 이 클래스는 그 회귀 그물이면서 유형별 작성
 * 권한, 공개 조건 필터, 정렬·페이징 화이트리스트, Soft Delete 후 비노출을 함께 검증한다.
 *
 * <p>인증은 다른 단면 통합 테스트와 같이 검증된 {@link AuthenticatedUser} Principal을 SecurityContext에 넣어 재현한다. 전문가
 * 팔로우·Template 필드는 쓰기 API가 아직 없으므로 jdbc로 직접 구성하고, 게시글 자체는 가능한 한 공개 API로 만든다.
 */
@Testcontainers
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("integration-test")
class CommunityPostIntegrationTest {

  private static final Long GUARDIAN_USER_ID = 41L;
  private static final Long OTHER_GUARDIAN_USER_ID = 42L;
  private static final Long EXPERT_USER_ID = 43L;
  private static final Long ADMIN_USER_ID = 44L;

  @Container @ServiceConnection
  static final MySQLContainer<?> MYSQL_CONTAINER =
      new MySQLContainer<>("mysql:8.4.10")
          .withDatabaseName("dodam_community")
          .withUsername("test")
          .withPassword("test");

  @Autowired private MockMvc mockMvc;
  @Autowired private JdbcTemplate jdbcTemplate;
  @Autowired private ObjectMapper objectMapper;

  @BeforeEach
  void setUp() {
    authenticate(GUARDIAN_USER_ID);
    jdbcTemplate.update("DELETE FROM community_post_template_fields");
    jdbcTemplate.update("DELETE FROM post_likes");
    jdbcTemplate.update("DELETE FROM comments");
    jdbcTemplate.execute("ALTER TABLE comments AUTO_INCREMENT = 1");
    jdbcTemplate.update("DELETE FROM community_posts");
    jdbcTemplate.update("DELETE FROM expert_follows");
    jdbcTemplate.update("DELETE FROM expert_profiles");
    jdbcTemplate.update("DELETE FROM users");
    jdbcTemplate.update(
        "INSERT INTO users (id, role, nickname, account_status, profile_image_url) VALUES "
            + "(?, 'GUARDIAN', '별이맘', 'ACTIVE', 'https://cdn.example.com/guardian.png'), "
            + "(?, 'GUARDIAN', '다른보호자', 'ACTIVE', NULL), "
            + "(?, 'EXPERT', '미술치료사', 'ACTIVE', NULL), "
            + "(?, 'ADMIN', '운영자', 'ACTIVE', NULL)",
        GUARDIAN_USER_ID,
        OTHER_GUARDIAN_USER_ID,
        EXPERT_USER_ID,
        ADMIN_USER_ID);
  }

  @AfterEach
  void clearSecurityContext() {
    SecurityContextHolder.clearContext();
  }

  // ---------------------------------------------------------------- 167 게시글 작성

  @Test
  void createsPostAsActiveVisibleAndReturnsLocationWithDetail() throws Exception {
    String body =
        mockMvc
            .perform(createPost("GUARDIAN_STORY", "우리 아이 첫 그림", "오늘 처음으로 가족을 그렸어요.", false))
            .andExpect(status().isCreated())
            .andExpect(header().exists("Location"))
            .andExpect(jsonPath("$.data.postId").isNumber())
            .andExpect(jsonPath("$.data.postType").value("GUARDIAN_STORY"))
            .andExpect(jsonPath("$.data.title").value("우리 아이 첫 그림"))
            .andExpect(jsonPath("$.data.content").value("오늘 처음으로 가족을 그렸어요."))
            .andExpect(jsonPath("$.data.author.userId").value(GUARDIAN_USER_ID))
            .andExpect(jsonPath("$.data.author.nickname").value("별이맘"))
            .andExpect(jsonPath("$.data.anonymous").value(false))
            .andExpect(jsonPath("$.data.attachments").isEmpty())
            .andExpect(jsonPath("$.data.templateData").isEmpty())
            .andExpect(jsonPath("$.data.likeCount").value(0))
            .andExpect(jsonPath("$.data.commentCount").value(0))
            .andExpect(jsonPath("$.data.likedByMe").value(false))
            .andExpect(jsonPath("$.data.editableByMe").value(true))
            .andReturn()
            .getResponse()
            .getContentAsString(StandardCharsets.UTF_8);
    long postId = objectMapper.readTree(body).at("/data/postId").asLong();

    assertThat(
            jdbcTemplate.queryForMap(
                "SELECT post_status, is_visible, deleted_at, author_user_id "
                    + "FROM community_posts WHERE id = ?",
                postId))
        .containsEntry("post_status", "ACTIVE")
        .containsEntry("is_visible", true)
        .containsEntry("deleted_at", null)
        .containsEntry("author_user_id", GUARDIAN_USER_ID);
  }

  @Test
  void hidesAuthorForAnonymousPost() throws Exception {
    mockMvc
        .perform(createPost("GUARDIAN_STORY", "익명 고민", "요즘 아이가 그림을 안 그려요.", true))
        .andExpect(status().isCreated())
        .andExpect(jsonPath("$.data.anonymous").value(true))
        .andExpect(jsonPath("$.data.author").doesNotExist());
  }

  @Test
  void rejectsNoticeFromGuardianAndAllowsItForAdmin() throws Exception {
    mockMvc
        .perform(createPost("NOTICE", "점검 공지", "새벽 2시에 점검이 있습니다.", false))
        .andExpect(status().isForbidden())
        .andExpect(jsonPath("$.code").value("POST_TYPE_NOT_ALLOWED"));

    authenticate(ADMIN_USER_ID);
    mockMvc
        .perform(createPost("NOTICE", "점검 공지", "새벽 2시에 점검이 있습니다.", false))
        .andExpect(status().isCreated())
        .andExpect(jsonPath("$.data.postType").value("NOTICE"));
  }

  @Test
  void restrictsExpertResourceTypesToExpertsAndAdmins() throws Exception {
    mockMvc
        .perform(createPost("EXPERT_COLUMN", "그림으로 읽는 마음", "전문가 칼럼 본문입니다.", false))
        .andExpect(status().isForbidden())
        .andExpect(jsonPath("$.code").value("POST_TYPE_NOT_ALLOWED"));

    authenticate(EXPERT_USER_ID);
    mockMvc
        .perform(createPost("EXPERT_COLUMN", "그림으로 읽는 마음", "전문가 칼럼 본문입니다.", false))
        .andExpect(status().isCreated())
        .andExpect(jsonPath("$.data.author.userId").value(EXPERT_USER_ID));
  }

  @Test
  void rejectsInvalidCreateRequestBody() throws Exception {
    mockMvc
        .perform(createPost("GUARDIAN_STORY", "  ", "본문은 있습니다.", false))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.code").value("COMMON_400_001"));

    mockMvc
        .perform(
            post("/api/v1/posts")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"title\":\"유형 없음\",\"content\":\"본문\"}"))
        .andExpect(status().isBadRequest());

    assertThat(postCount()).isZero();
  }

  // ---------------------------------------------------------------- 165 게시글 목록

  @Test
  void listsOnlyActiveVisiblePostsNewestFirst() throws Exception {
    insertPost(1, GUARDIAN_USER_ID, "GUARDIAN_STORY", "공개 1", "본문 1", false, "ACTIVE", true, null);
    insertPost(2, GUARDIAN_USER_ID, "GUARDIAN_STORY", "공개 2", "본문 2", false, "ACTIVE", true, null);
    insertPost(3, GUARDIAN_USER_ID, "GUARDIAN_STORY", "숨김", "본문 3", false, "HIDDEN", true, null);
    insertPost(4, GUARDIAN_USER_ID, "GUARDIAN_STORY", "비공개", "본문 4", false, "ACTIVE", false, null);
    insertPost(
        5,
        GUARDIAN_USER_ID,
        "GUARDIAN_STORY",
        "삭제됨",
        "본문 5",
        false,
        "DELETED",
        true,
        "2026-07-24 00:00:00");

    mockMvc
        .perform(get("/api/v1/posts"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.totalElements").value(2))
        .andExpect(jsonPath("$.data.totalPages").value(1))
        .andExpect(jsonPath("$.data.first").value(true))
        .andExpect(jsonPath("$.data.last").value(true))
        .andExpect(jsonPath("$.data.hasNext").value(false))
        .andExpect(jsonPath("$.data.content[0].postId").value(2))
        .andExpect(jsonPath("$.data.content[1].postId").value(1));
  }

  @Test
  void filtersByTypeKeywordAndAuthorRole() throws Exception {
    insertPost(
        1, GUARDIAN_USER_ID, "GUARDIAN_STORY", "보호자 이야기", "크레파스 후기", false, "ACTIVE", true, null);
    insertPost(
        2, EXPERT_USER_ID, "EXPERT_COLUMN", "전문가 칼럼", "크레파스 심리", false, "ACTIVE", true, null);
    insertPost(
        3, GUARDIAN_USER_ID, "ACTIVITY_REVIEW", "활동 후기", "물감 후기", false, "ACTIVE", true, null);

    mockMvc
        .perform(get("/api/v1/posts").param("type", "EXPERT_COLUMN"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.totalElements").value(1))
        .andExpect(jsonPath("$.data.content[0].postId").value(2));

    mockMvc
        .perform(get("/api/v1/posts").param("keyword", "크레파스"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.totalElements").value(2));

    mockMvc
        .perform(get("/api/v1/posts").param("authorRole", "EXPERT"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.totalElements").value(1))
        .andExpect(jsonPath("$.data.content[0].author.userId").value(EXPERT_USER_ID));
  }

  @Test
  void sortsByLikeCountAndPaginates() throws Exception {
    insertPost(1, GUARDIAN_USER_ID, "GUARDIAN_STORY", "좋아요 0", "본문", false, "ACTIVE", true, null);
    insertPost(2, GUARDIAN_USER_ID, "GUARDIAN_STORY", "좋아요 2", "본문", false, "ACTIVE", true, null);
    like(2, GUARDIAN_USER_ID);
    like(2, OTHER_GUARDIAN_USER_ID);

    mockMvc
        .perform(get("/api/v1/posts").param("sort", "likeCount,asc"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.content[0].postId").value(1))
        .andExpect(jsonPath("$.data.content[1].postId").value(2))
        .andExpect(jsonPath("$.data.content[1].likeCount").value(2))
        .andExpect(jsonPath("$.data.content[1].likedByMe").value(true));

    mockMvc
        .perform(get("/api/v1/posts").param("size", "1").param("page", "0"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.content.length()").value(1))
        .andExpect(jsonPath("$.data.totalPages").value(2))
        .andExpect(jsonPath("$.data.hasNext").value(true))
        .andExpect(jsonPath("$.data.last").value(false));

    mockMvc
        .perform(get("/api/v1/posts").param("size", "1").param("page", "1"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.first").value(false))
        .andExpect(jsonPath("$.data.hasNext").value(false));
  }

  @Test
  void returnsFollowingFeedOnlyForFollowedExperts() throws Exception {
    insertPost(1, EXPERT_USER_ID, "EXPERT_COLUMN", "팔로우한 전문가", "본문", false, "ACTIVE", true, null);
    insertPost(2, GUARDIAN_USER_ID, "GUARDIAN_STORY", "내 글", "본문", false, "ACTIVE", true, null);

    mockMvc
        .perform(get("/api/v1/posts").param("feed", "FOLLOWING"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.totalElements").value(0));

    jdbcTemplate.update(
        "INSERT INTO expert_profiles (id, display_name, career_years, user_id) "
            + "VALUES (7, '미술치료사', 5, ?)",
        EXPERT_USER_ID);
    jdbcTemplate.update(
        "INSERT INTO expert_follows (guardian_user_id, expert_profile_id) VALUES (?, 7)",
        GUARDIAN_USER_ID);

    mockMvc
        .perform(get("/api/v1/posts").param("feed", "FOLLOWING"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.totalElements").value(1))
        .andExpect(jsonPath("$.data.content[0].postId").value(1));
  }

  @Test
  void masksAnonymousAuthorAndPreviewsLongContentInList() throws Exception {
    String longContent = "가".repeat(250);
    insertPost(
        1, GUARDIAN_USER_ID, "GUARDIAN_STORY", "익명 글", longContent, true, "ACTIVE", true, null);

    mockMvc
        .perform(get("/api/v1/posts"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.content[0].anonymous").value(true))
        .andExpect(jsonPath("$.data.content[0].isAnonymous").doesNotExist())
        .andExpect(jsonPath("$.data.content[0].author").doesNotExist())
        .andExpect(jsonPath("$.data.content[0].previewContent").value("가".repeat(200) + "…"));
  }

  @Test
  void rejectsQueryOutsidePublicContract() throws Exception {
    mockMvc
        .perform(get("/api/v1/posts").param("sort", "title,desc"))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.code").value("VALIDATION_FAILED"));

    mockMvc
        .perform(get("/api/v1/posts").param("size", "101"))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.code").value("VALIDATION_FAILED"));

    mockMvc
        .perform(get("/api/v1/posts").param("page", "-1"))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.code").value("VALIDATION_FAILED"));

    mockMvc
        .perform(get("/api/v1/posts").param("type", "UNKNOWN_TYPE"))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.code").value("VALIDATION_FAILED"));

    mockMvc
        .perform(get("/api/v1/posts").param("authorRole", "ADMIN"))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.code").value("VALIDATION_FAILED"));
  }

  // ---------------------------------------------------------------- 166 게시글 상세

  @Test
  void returnsDetailWithAggregatesAndTemplateFieldsInDisplayOrder() throws Exception {
    insertPost(
        1, GUARDIAN_USER_ID, "ACTIVITY_REVIEW", "활동 후기", "전체 본문", false, "ACTIVE", true, null);
    like(1, OTHER_GUARDIAN_USER_ID);
    like(1, GUARDIAN_USER_ID);
    insertComment(1, "ACTIVE", true, null);
    insertComment(1, "DELETED", true, "2026-07-24 00:00:00");
    insertComment(1, "ACTIVE", false, null);
    jdbcTemplate.update(
        "INSERT INTO community_post_template_fields "
            + "(community_post_id, field_code, value_type, value_text, display_order) VALUES "
            + "(1, 'RATING', 'NUMBER', '5', 2), "
            + "(1, 'MATERIAL', 'STRING', '크레파스', 1)");

    mockMvc
        .perform(get("/api/v1/posts/{postId}", 1))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.postId").value(1))
        .andExpect(jsonPath("$.data.content").value("전체 본문"))
        .andExpect(
            jsonPath("$.data.author.profileImageUrl").value("https://cdn.example.com/guardian.png"))
        .andExpect(jsonPath("$.data.likeCount").value(2))
        .andExpect(jsonPath("$.data.commentCount").value(1))
        .andExpect(jsonPath("$.data.likedByMe").value(true))
        .andExpect(jsonPath("$.data.editableByMe").value(true))
        .andExpect(jsonPath("$.data.templateData[0].fieldCode").value("MATERIAL"))
        .andExpect(jsonPath("$.data.templateData[0].value").value("크레파스"))
        .andExpect(jsonPath("$.data.templateData[1].fieldCode").value("RATING"))
        .andExpect(jsonPath("$.data.templateData[1].valueType").value("NUMBER"));
  }

  @Test
  void hidesNonPublicPostsBehindTheSameNotFound() throws Exception {
    insertPost(1, GUARDIAN_USER_ID, "GUARDIAN_STORY", "숨김", "본문", false, "HIDDEN", true, null);
    insertPost(2, GUARDIAN_USER_ID, "GUARDIAN_STORY", "비공개", "본문", false, "ACTIVE", false, null);
    insertPost(
        3,
        GUARDIAN_USER_ID,
        "GUARDIAN_STORY",
        "삭제",
        "본문",
        false,
        "DELETED",
        true,
        "2026-07-24 00:00:00");

    for (long postId : List.of(1L, 2L, 3L, 999L)) {
      mockMvc
          .perform(get("/api/v1/posts/{postId}", postId))
          .andExpect(status().isNotFound())
          .andExpect(jsonPath("$.code").value("POST_NOT_FOUND"));
    }
  }

  @Test
  void showsOtherUsersPostAsNotEditable() throws Exception {
    insertPost(
        1, OTHER_GUARDIAN_USER_ID, "GUARDIAN_STORY", "남의 글", "본문", false, "ACTIVE", true, null);

    mockMvc
        .perform(get("/api/v1/posts/{postId}", 1))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.editableByMe").value(false))
        .andExpect(jsonPath("$.data.author.userId").value(OTHER_GUARDIAN_USER_ID));
  }

  @Test
  void keepsAnonymousPostEditableForItsAuthor() throws Exception {
    insertPost(1, GUARDIAN_USER_ID, "GUARDIAN_STORY", "내 익명 글", "본문", true, "ACTIVE", true, null);

    mockMvc
        .perform(get("/api/v1/posts/{postId}", 1))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.anonymous").value(true))
        .andExpect(jsonPath("$.data.author").doesNotExist())
        // 수정 API는 익명 글도 작성자에게 허용하므로 응답 플래그도 참이어야 한다.
        .andExpect(jsonPath("$.data.editableByMe").value(true));
  }

  // ---------------------------------------------------------------- 168 게시글 수정·삭제

  @Test
  void replacesOwnPostContentAndType() throws Exception {
    insertPost(
        1, GUARDIAN_USER_ID, "GUARDIAN_STORY", "원래 제목", "원래 본문", false, "ACTIVE", true, null);

    mockMvc
        .perform(updatePost(1, "ACTIVITY_REVIEW", "새 제목", "새 본문", true))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.postType").value("ACTIVITY_REVIEW"))
        .andExpect(jsonPath("$.data.title").value("새 제목"))
        .andExpect(jsonPath("$.data.content").value("새 본문"))
        .andExpect(jsonPath("$.data.anonymous").value(true))
        .andExpect(jsonPath("$.data.author").doesNotExist());

    assertThat(
            jdbcTemplate.queryForMap(
                "SELECT post_type, title, content, is_anonymous, post_status "
                    + "FROM community_posts WHERE id = 1"))
        .containsEntry("post_type", "ACTIVITY_REVIEW")
        .containsEntry("title", "새 제목")
        .containsEntry("content", "새 본문")
        .containsEntry("is_anonymous", true)
        .containsEntry("post_status", "ACTIVE");
  }

  @Test
  void rejectsUpdateByAnotherGuardianEvenForAdmin() throws Exception {
    insertPost(
        1, OTHER_GUARDIAN_USER_ID, "GUARDIAN_STORY", "남의 글", "본문", false, "ACTIVE", true, null);

    mockMvc
        .perform(updatePost(1, "GUARDIAN_STORY", "가로채기", "본문", false))
        .andExpect(status().isForbidden())
        .andExpect(jsonPath("$.code").value("POST_ACCESS_DENIED"));

    // 삭제와 달리 수정은 관리자에게도 허용하지 않는다.
    authenticate(ADMIN_USER_ID);
    mockMvc
        .perform(updatePost(1, "GUARDIAN_STORY", "관리자 수정", "본문", false))
        .andExpect(status().isForbidden())
        .andExpect(jsonPath("$.code").value("POST_ACCESS_DENIED"));
  }

  @Test
  void rejectsUpdateToTypeTheAuthorCannotWrite() throws Exception {
    insertPost(1, GUARDIAN_USER_ID, "GUARDIAN_STORY", "내 글", "본문", false, "ACTIVE", true, null);

    mockMvc
        .perform(updatePost(1, "NOTICE", "공지로 바꾸기", "본문", false))
        .andExpect(status().isForbidden())
        .andExpect(jsonPath("$.code").value("POST_TYPE_NOT_ALLOWED"));

    assertThat(
            jdbcTemplate.queryForObject(
                "SELECT post_type FROM community_posts WHERE id = 1", String.class))
        .isEqualTo("GUARDIAN_STORY");
  }

  @Test
  void softDeletesOwnPostAndRemovesItFromReadPaths() throws Exception {
    insertPost(1, GUARDIAN_USER_ID, "GUARDIAN_STORY", "지울 글", "본문", false, "ACTIVE", true, null);

    mockMvc.perform(delete("/api/v1/posts/{postId}", 1)).andExpect(status().isNoContent());

    assertThat(
            jdbcTemplate.queryForMap(
                "SELECT post_status, deleted_at FROM community_posts WHERE id = 1"))
        .containsEntry("post_status", "DELETED")
        .doesNotContainEntry("deleted_at", null);

    mockMvc.perform(get("/api/v1/posts/{postId}", 1)).andExpect(status().isNotFound());
    mockMvc
        .perform(get("/api/v1/posts"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.totalElements").value(0));

    mockMvc
        .perform(delete("/api/v1/posts/{postId}", 1))
        .andExpect(status().isNotFound())
        .andExpect(jsonPath("$.code").value("POST_NOT_FOUND"));
  }

  @Test
  void allowsAdminToDeleteAnotherUsersPostButNotOtherGuardians() throws Exception {
    insertPost(1, GUARDIAN_USER_ID, "GUARDIAN_STORY", "삭제 대상", "본문", false, "ACTIVE", true, null);

    authenticate(OTHER_GUARDIAN_USER_ID);
    mockMvc
        .perform(delete("/api/v1/posts/{postId}", 1))
        .andExpect(status().isForbidden())
        .andExpect(jsonPath("$.code").value("POST_ACCESS_DENIED"));

    authenticate(ADMIN_USER_ID);
    mockMvc.perform(delete("/api/v1/posts/{postId}", 1)).andExpect(status().isNoContent());

    assertThat(
            jdbcTemplate.queryForObject(
                "SELECT post_status FROM community_posts WHERE id = 1", String.class))
        .isEqualTo("DELETED");
  }

  // ---------------------------------------------------------------- 583 게시글 좋아요 등록·취소

  @Test
  void repeatedLikeAndUnlikeRequestsKeepTheSameFinalState() throws Exception {
    insertPost(1, EXPERT_USER_ID, "EXPERT_COLUMN", "좋아요 대상", "본문", false, "ACTIVE", true, null);

    mockMvc
        .perform(post("/api/v1/posts/{postId}/likes", 1))
        .andExpect(status().isCreated())
        .andExpect(jsonPath("$.data.postId").value(1))
        .andExpect(jsonPath("$.data.liked").value(true))
        .andExpect(jsonPath("$.data.likeCount").value(1));

    mockMvc
        .perform(post("/api/v1/posts/{postId}/likes", 1))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.postId").value(1))
        .andExpect(jsonPath("$.data.liked").value(true))
        .andExpect(jsonPath("$.data.likeCount").value(1));

    assertThat(
            jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM post_likes WHERE post_id = 1 AND user_id = ?",
                Integer.class,
                GUARDIAN_USER_ID))
        .isEqualTo(1);

    mockMvc.perform(delete("/api/v1/posts/{postId}/likes", 1)).andExpect(status().isNoContent());
    mockMvc.perform(delete("/api/v1/posts/{postId}/likes", 1)).andExpect(status().isNoContent());

    assertThat(
            jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM post_likes WHERE post_id = 1 AND user_id = ?",
                Integer.class,
                GUARDIAN_USER_ID))
        .isZero();
  }

  @Test
  void likeChangesAreImmediatelyVisibleInPostDetail() throws Exception {
    insertPost(1, EXPERT_USER_ID, "EXPERT_COLUMN", "집계 대상", "본문", false, "ACTIVE", true, null);

    mockMvc.perform(post("/api/v1/posts/{postId}/likes", 1)).andExpect(status().isCreated());
    mockMvc
        .perform(get("/api/v1/posts/{postId}", 1))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.likeCount").value(1))
        .andExpect(jsonPath("$.data.likedByMe").value(true));

    mockMvc.perform(delete("/api/v1/posts/{postId}/likes", 1)).andExpect(status().isNoContent());
    mockMvc
        .perform(get("/api/v1/posts/{postId}", 1))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.likeCount").value(0))
        .andExpect(jsonPath("$.data.likedByMe").value(false));
  }

  @Test
  void rejectsLikesForNonPublicPostsAndUnsupportedRoles() throws Exception {
    insertPost(1, GUARDIAN_USER_ID, "GUARDIAN_STORY", "숨김 글", "본문", false, "ACTIVE", false, null);

    mockMvc
        .perform(post("/api/v1/posts/{postId}/likes", 1))
        .andExpect(status().isNotFound())
        .andExpect(jsonPath("$.code").value("POST_NOT_FOUND"));

    insertPost(2, GUARDIAN_USER_ID, "GUARDIAN_STORY", "공개 글", "본문", false, "ACTIVE", true, null);
    authenticate(ADMIN_USER_ID);
    mockMvc
        .perform(post("/api/v1/posts/{postId}/likes", 2))
        .andExpect(status().isForbidden())
        .andExpect(jsonPath("$.code").value("AUTH_403_002"));
  }

  @Test
  void rejectsWriteAndReadWithoutAuthentication() throws Exception {
    insertPost(1, GUARDIAN_USER_ID, "GUARDIAN_STORY", "공개 글", "본문", false, "ACTIVE", true, null);
    SecurityContextHolder.clearContext();

    mockMvc.perform(get("/api/v1/posts")).andExpect(status().isUnauthorized());
    mockMvc.perform(get("/api/v1/posts/{postId}", 1)).andExpect(status().isUnauthorized());
    mockMvc
        .perform(createPost("GUARDIAN_STORY", "제목", "본문", false))
        .andExpect(status().isUnauthorized());
    mockMvc
        .perform(updatePost(1, "GUARDIAN_STORY", "제목", "본문", false))
        .andExpect(status().isUnauthorized());
    mockMvc.perform(delete("/api/v1/posts/{postId}", 1)).andExpect(status().isUnauthorized());
  }

  // ---------------------------------------------------------------- 582 댓글 작성·수정·삭제

  @Test
  void createsUpdatesAndSoftDeletesComment() throws Exception {
    insertPost(1, EXPERT_USER_ID, "EXPERT_COLUMN", "공개 글", "본문", false, "ACTIVE", true, null);

    mockMvc
        .perform(
            post("/api/v1/posts/{postId}/comments", 1)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"content\":\"첫 댓글\",\"anonymous\":false}"))
        .andExpect(status().isCreated())
        .andExpect(header().string("Location", "/api/v1/comments/1"))
        .andExpect(jsonPath("$.data.commentId").value(1))
        .andExpect(jsonPath("$.data.author.nickname").value("별이맘"))
        .andExpect(jsonPath("$.data.editableByMe").value(true));

    mockMvc
        .perform(
            patch("/api/v1/comments/{commentId}", 1)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"content\":\"수정 댓글\"}"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.content").value("수정 댓글"));

    mockMvc.perform(delete("/api/v1/comments/{commentId}", 1)).andExpect(status().isNoContent());

    assertThat(
            jdbcTemplate.queryForMap(
                "SELECT content, comment_status, deleted_at FROM comments WHERE id = 1"))
        .containsEntry("content", "수정 댓글")
        .containsEntry("comment_status", "DELETED")
        .doesNotContainEntry("deleted_at", null);
  }

  @Test
  void anonymousCommentHidesAuthorButRemainsEditableByWriter() throws Exception {
    insertPost(1, EXPERT_USER_ID, "EXPERT_COLUMN", "공개 글", "본문", false, "ACTIVE", true, null);

    mockMvc
        .perform(
            post("/api/v1/posts/{postId}/comments", 1)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"content\":\"익명 댓글\",\"anonymous\":true}"))
        .andExpect(status().isCreated())
        .andExpect(jsonPath("$.data.author").doesNotExist())
        .andExpect(jsonPath("$.data.anonymous").value(true))
        .andExpect(jsonPath("$.data.editableByMe").value(true));
  }

  @Test
  void nonAuthorCannotUpdateOrDeleteCommentButAdminCanDelete() throws Exception {
    insertPost(1, GUARDIAN_USER_ID, "GUARDIAN_STORY", "공개 글", "본문", false, "ACTIVE", true, null);
    insertComment(1, "ACTIVE", true, null);

    mockMvc
        .perform(
            patch("/api/v1/comments/{commentId}", 1)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"content\":\"가로채기\"}"))
        .andExpect(status().isForbidden())
        .andExpect(jsonPath("$.code").value("COMMENT_ACCESS_DENIED"));
    mockMvc.perform(delete("/api/v1/comments/{commentId}", 1)).andExpect(status().isForbidden());

    authenticate(ADMIN_USER_ID);
    mockMvc.perform(delete("/api/v1/comments/{commentId}", 1)).andExpect(status().isNoContent());
  }

  @Test
  void rejectsCommentForMissingPostAndBlankContent() throws Exception {
    mockMvc
        .perform(
            post("/api/v1/posts/{postId}/comments", 999)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"content\":\"댓글\",\"anonymous\":false}"))
        .andExpect(status().isNotFound())
        .andExpect(jsonPath("$.code").value("POST_NOT_FOUND"));

    mockMvc
        .perform(
            post("/api/v1/posts/{postId}/comments", 999)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"content\":\"\",\"anonymous\":false}"))
        .andExpect(status().isBadRequest());
  }

  // ---------------------------------------------------------------- 요청·fixture 도우미

  private RequestBuilder createPost(
      String postType, String title, String content, boolean anonymous) {
    return post("/api/v1/posts")
        .contentType(MediaType.APPLICATION_JSON)
        .content(requestBody(postType, title, content, anonymous));
  }

  private RequestBuilder updatePost(
      long postId, String postType, String title, String content, boolean anonymous) {
    return patch("/api/v1/posts/{postId}", postId)
        .contentType(MediaType.APPLICATION_JSON)
        .content(requestBody(postType, title, content, anonymous));
  }

  private String requestBody(String postType, String title, String content, boolean anonymous) {
    return """
        {
          "postType": "%s",
          "title": "%s",
          "content": "%s",
          "anonymous": %s
        }
        """
        .formatted(postType, title, content, anonymous);
  }

  private void insertPost(
      long id,
      Long authorUserId,
      String postType,
      String title,
      String content,
      boolean anonymous,
      String status,
      boolean visible,
      String deletedAt) {
    jdbcTemplate.update(
        "INSERT INTO community_posts "
            + "(id, author_user_id, post_type, title, content, is_anonymous, is_visible, "
            + "post_status, deleted_at) "
            + "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
        id,
        authorUserId,
        postType,
        title,
        content,
        anonymous,
        visible,
        status,
        deletedAt);
  }

  private void like(long postId, Long userId) {
    jdbcTemplate.update("INSERT INTO post_likes (post_id, user_id) VALUES (?, ?)", postId, userId);
  }

  private void insertComment(long postId, String status, boolean visible, String deletedAt) {
    jdbcTemplate.update(
        "INSERT INTO comments (post_id, author_user_id, content, comment_status, is_visible, "
            + "deleted_at) VALUES (?, ?, '댓글', ?, ?, ?)",
        postId,
        OTHER_GUARDIAN_USER_ID,
        status,
        visible,
        deletedAt);
  }

  private int postCount() {
    return jdbcTemplate.queryForObject("SELECT COUNT(*) FROM community_posts", Integer.class);
  }

  private void authenticate(Long userId) {
    SecurityContextHolder.getContext()
        .setAuthentication(
            UsernamePasswordAuthenticationToken.authenticated(
                new AuthenticatedUser(userId), null, List.of()));
  }
}
