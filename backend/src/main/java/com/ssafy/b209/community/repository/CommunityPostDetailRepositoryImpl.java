package com.ssafy.b209.community.repository;

import com.ssafy.b209.community.domain.PostType;
import jakarta.persistence.EntityManager;
import jakarta.persistence.Query;
import java.sql.Timestamp;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;
import org.springframework.stereotype.Repository;

/**
 * 게시글 상세 공개 계약에 필요한 정규화 관계를 Native Query로 조회하는 Repository 구현체다.
 *
 * <p>게시글 ID와 일반 공개 상태를 하나의 WHERE 조건으로 적용해 HIDDEN·DELETED·비공개 게시글의 존재 정보를 반환하지 않는다.
 *
 * <p>{@code editableByMe}는 익명 여부와 무관하게 작성자 본인이면 참이다. 실제 수정 권한을 판정하는 {@code
 * CommunityPostCommandService.updatePost()}가 익명 글도 작성자에게 허용하므로 응답 플래그를 그 판정과 일치시킨다. 익명성은 작성자 표시를
 * 마스킹해 보호하며 수정 권한을 없애서 보호하지 않는다.
 */
@Repository
public class CommunityPostDetailRepositoryImpl implements CommunityPostDetailRepository {

  private static final String POST_DETAIL_SQL =
      """
      SELECT p.id, p.post_type, p.title, p.content, p.is_anonymous, p.created_at, p.updated_at,
             u.id, u.nickname, u.profile_image_url,
             (SELECT COUNT(*) FROM post_likes pl WHERE pl.post_id = p.id),
             (SELECT COUNT(*) FROM comments c
                WHERE c.post_id = p.id
                  AND c.comment_status = 'ACTIVE'
                  AND c.is_visible = true
                  AND c.deleted_at IS NULL),
             CASE WHEN EXISTS (
               SELECT 1 FROM post_likes mine
               WHERE mine.post_id = p.id AND mine.user_id = :viewerUserId
             ) THEN 1 ELSE 0 END,
             CASE WHEN p.author_user_id = :viewerUserId THEN 1 ELSE 0 END
      FROM community_posts p
      LEFT JOIN users u ON u.id = p.author_user_id
      WHERE p.id = :postId
        AND p.post_status = 'ACTIVE'
        AND p.is_visible = true
        AND p.deleted_at IS NULL
        AND NOT EXISTS (
          SELECT 1 FROM user_blocks ub
          WHERE ub.blocker_user_id = :viewerUserId
            AND ub.blocked_user_id = p.author_user_id
        )
      """;

  private static final String TEMPLATE_FIELDS_SQL =
      """
      SELECT field_code, value_type, value_text, display_order
      FROM community_post_template_fields
      WHERE community_post_id = :postId
      ORDER BY display_order ASC
      """;

  private final EntityManager entityManager;

  /**
   * 상세 조회 Native Query를 실행할 영속성 관리자를 주입한다.
   *
   * @param entityManager DB v1.2 Native Query 실행 도구
   */
  public CommunityPostDetailRepositoryImpl(EntityManager entityManager) {
    this.entityManager = entityManager;
  }

  /**
   * 일반 공개 상세 조건 및 현재 사용자 파생값을 한 행으로 조회한다.
   *
   * @param postId 조회할 게시글 ID
   * @param viewerUserId 현재 인증 사용자 ID
   * @return 공개 게시글 상세 행 또는 조건 불일치 시 빈 값
   */
  @Override
  public Optional<CommunityPostDetailRow> findPublicPost(Long postId, Long viewerUserId) {
    Query query = entityManager.createNativeQuery(POST_DETAIL_SQL);
    query.setParameter("postId", postId);
    query.setParameter("viewerUserId", viewerUserId);

    @SuppressWarnings("unchecked")
    List<Object[]> rows = query.getResultList();
    return rows.stream().findFirst().map(this::toDetailRow);
  }

  /**
   * 게시글 Template 필드를 저장된 노출 순서대로 반환한다.
   *
   * @param postId 공개 확인을 마친 게시글 ID
   * @return Template field의 코드·유형·문자열 원문·순서 목록
   */
  @Override
  public List<CommunityPostTemplateFieldRow> findTemplateFieldsByPostId(Long postId) {
    Query query = entityManager.createNativeQuery(TEMPLATE_FIELDS_SQL);
    query.setParameter("postId", postId);

    @SuppressWarnings("unchecked")
    List<Object[]> rows = query.getResultList();
    return rows.stream()
        .map(
            values ->
                new CommunityPostTemplateFieldRow(
                    (String) values[0],
                    (String) values[1],
                    (String) values[2],
                    ((Number) values[3]).intValue()))
        .toList();
  }

  private CommunityPostDetailRow toDetailRow(Object[] values) {
    return new CommunityPostDetailRow(
        longValue(values[0]),
        PostType.valueOf((String) values[1]),
        (String) values[2],
        (String) values[3],
        booleanValue(values[4]),
        localDateTime(values[5]),
        localDateTime(values[6]),
        nullableLong(values[7]),
        (String) values[8],
        (String) values[9],
        longValue(values[10]),
        longValue(values[11]),
        booleanValue(values[12]),
        booleanValue(values[13]));
  }

  private long longValue(Object value) {
    return ((Number) value).longValue();
  }

  private Long nullableLong(Object value) {
    return value == null ? null : longValue(value);
  }

  private boolean booleanValue(Object value) {
    if (value instanceof Boolean booleanValue) {
      return booleanValue;
    }
    return ((Number) value).intValue() != 0;
  }

  private LocalDateTime localDateTime(Object value) {
    if (value instanceof LocalDateTime localDateTime) {
      return localDateTime;
    }
    return ((Timestamp) value).toLocalDateTime();
  }
}
