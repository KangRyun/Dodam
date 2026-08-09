package com.ssafy.b209.community;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.ssafy.b209.auth.token.AuthenticatedUser;
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
import org.testcontainers.containers.MySQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

/** 커뮤니티 신고와 사용자 차단 계약을 실제 MySQL 스키마까지 관통해 검증한다. */
@Testcontainers
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("integration-test")
class CommunitySafetyIntegrationTest {

  private static final long REPORTER_ID = 81L;
  private static final long TARGET_USER_ID = 82L;

  @Container @ServiceConnection
  static final MySQLContainer<?> MYSQL_CONTAINER =
      new MySQLContainer<>("mysql:8.4.10")
          .withDatabaseName("dodam_community_safety")
          .withUsername("test")
          .withPassword("test");

  @Autowired private MockMvc mockMvc;
  @Autowired private JdbcTemplate jdbcTemplate;

  @BeforeEach
  void setUp() {
    authenticate(REPORTER_ID);
    jdbcTemplate.update("DELETE FROM user_blocks");
    jdbcTemplate.update("DELETE FROM complaints");
    jdbcTemplate.update("DELETE FROM comments");
    jdbcTemplate.update("DELETE FROM community_posts");
    jdbcTemplate.update("DELETE FROM users");
    jdbcTemplate.update(
        "INSERT INTO users (id, role, nickname, account_status) VALUES "
            + "(?, 'GUARDIAN', '신고자', 'ACTIVE'), (?, 'GUARDIAN', '차단대상', 'ACTIVE')",
        REPORTER_ID,
        TARGET_USER_ID);
  }

  @AfterEach
  void clearSecurityContext() {
    SecurityContextHolder.clearContext();
  }

  @Test
  void createsComplaintAndRejectsSameTargetAndReason() throws Exception {
    long postId = insertPost(TARGET_USER_ID, "개인정보 포함 글");
    String request =
        """
        {
          "targetType": "POST",
          "targetId": %d,
          "reasonCode": "PERSONAL_INFORMATION",
          "description": "아동의 학교 정보가 포함되어 있습니다."
        }
        """
            .formatted(postId);

    mockMvc
        .perform(
            post("/api/v1/complaints").contentType(MediaType.APPLICATION_JSON).content(request))
        .andExpect(status().isCreated())
        .andExpect(header().exists("Location"))
        .andExpect(jsonPath("$.data.complaintId").isNumber())
        .andExpect(jsonPath("$.data.targetType").value("POST"))
        .andExpect(jsonPath("$.data.targetId").value(postId))
        .andExpect(jsonPath("$.data.reasonCode").value("PERSONAL_INFORMATION"))
        .andExpect(jsonPath("$.data.status").value("PENDING"));

    mockMvc
        .perform(
            post("/api/v1/complaints").contentType(MediaType.APPLICATION_JSON).content(request))
        .andExpect(status().isConflict())
        .andExpect(jsonPath("$.code").value("COMPLAINT_ALREADY_EXISTS"));
  }

  @Test
  void rejectsComplaintForUnavailablePost() throws Exception {
    mockMvc
        .perform(
            post("/api/v1/complaints")
                .contentType(MediaType.APPLICATION_JSON)
                .content(
                    """
                    {
                      "targetType": "POST",
                      "targetId": 99999,
                      "reasonCode": "OTHER",
                      "description": "확인이 필요합니다."
                    }
                    """))
        .andExpect(status().isNotFound())
        .andExpect(jsonPath("$.code").value("POST_NOT_FOUND"));
  }

  @Test
  void createsComplaintForActiveComment() throws Exception {
    long postId = insertPost(TARGET_USER_ID, "댓글이 달린 글");
    jdbcTemplate.update(
        "INSERT INTO comments "
            + "(post_id, author_user_id, content, is_anonymous, is_visible, comment_status) "
            + "VALUES (?, ?, '신고 대상 댓글', FALSE, TRUE, 'ACTIVE')",
        postId,
        TARGET_USER_ID);
    long commentId = jdbcTemplate.queryForObject("SELECT MAX(id) FROM comments", Long.class);

    mockMvc
        .perform(
            post("/api/v1/complaints")
                .contentType(MediaType.APPLICATION_JSON)
                .content(
                    """
                    {
                      "targetType": "COMMENT",
                      "targetId": %d,
                      "reasonCode": "HARASSMENT"
                    }
                    """
                        .formatted(commentId)))
        .andExpect(status().isCreated())
        .andExpect(jsonPath("$.data.targetType").value("COMMENT"))
        .andExpect(jsonPath("$.data.targetId").value(commentId));
  }

  @Test
  void blocksAndUnblocksUserIdempotentlyAndFiltersTheirPosts() throws Exception {
    long postId = insertPost(TARGET_USER_ID, "차단 전에는 보이는 글");

    mockMvc
        .perform(post("/api/v1/users/me/blocks/{userId}", TARGET_USER_ID))
        .andExpect(status().isCreated())
        .andExpect(jsonPath("$.data.blockedUserId").value(TARGET_USER_ID))
        .andExpect(jsonPath("$.data.blocked").value(true));
    mockMvc
        .perform(post("/api/v1/users/me/blocks/{userId}", TARGET_USER_ID))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.blocked").value(true));

    mockMvc
        .perform(get("/api/v1/posts"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.content").isEmpty());
    mockMvc
        .perform(get("/api/v1/posts/{postId}", postId))
        .andExpect(status().isNotFound())
        .andExpect(jsonPath("$.code").value("POST_NOT_FOUND"));

    mockMvc
        .perform(delete("/api/v1/users/me/blocks/{userId}", TARGET_USER_ID))
        .andExpect(status().isNoContent());
    mockMvc
        .perform(delete("/api/v1/users/me/blocks/{userId}", TARGET_USER_ID))
        .andExpect(status().isNoContent());

    mockMvc
        .perform(get("/api/v1/posts"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.content[0].title").value("차단 전에는 보이는 글"));
  }

  @Test
  void rejectsSelfBlockAndUnknownUser() throws Exception {
    mockMvc
        .perform(post("/api/v1/users/me/blocks/{userId}", REPORTER_ID))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.code").value("USER_BLOCK_SELF_NOT_ALLOWED"));

    mockMvc
        .perform(post("/api/v1/users/me/blocks/{userId}", 99999))
        .andExpect(status().isNotFound())
        .andExpect(jsonPath("$.code").value("USER_404_001"));
  }

  private long insertPost(long authorId, String title) {
    jdbcTemplate.update(
        "INSERT INTO community_posts "
            + "(author_user_id, post_type, title, content, is_anonymous, is_visible, post_status) "
            + "VALUES (?, 'GUARDIAN_STORY', ?, '본문', FALSE, TRUE, 'ACTIVE')",
        authorId,
        title);
    return jdbcTemplate.queryForObject("SELECT MAX(id) FROM community_posts", Long.class);
  }

  private void authenticate(long userId) {
    SecurityContextHolder.getContext()
        .setAuthentication(
            UsernamePasswordAuthenticationToken.authenticated(
                new AuthenticatedUser(userId), null, List.of()));
  }
}
