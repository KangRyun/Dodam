package com.ssafy.b209.community.repository;

import com.ssafy.b209.community.domain.PostListSort.SortDirection;
import com.ssafy.b209.community.domain.PostListSort.SortField;
import com.ssafy.b209.community.domain.PostType;
import jakarta.persistence.EntityManager;
import jakarta.persistence.Query;
import java.sql.Timestamp;
import java.time.LocalDateTime;
import java.util.List;
import org.springframework.stereotype.Repository;

/**
 * 게시글 목록 계약에 필요한 정규화 관계를 Native Query로 집계하는 Repository 구현체다.
 *
 * <p>정렬 식은 검증된 enum에서만 선택하므로 Query Parameter가 SQL 식별자나 정렬 방향에 직접 연결되지 않는다.
 */
@Repository
public class CommunityPostListRepositoryImpl implements CommunityPostListRepository {

  private static final String FROM_AND_WHERE =
      """
      FROM community_posts p
      LEFT JOIN users u ON u.id = p.author_user_id
      WHERE p.post_status = 'ACTIVE'
        AND p.is_visible = true
        AND p.deleted_at IS NULL
        AND (:postType IS NULL OR p.post_type = :postType)
        AND (:keywordPattern IS NULL
          OR p.title LIKE :keywordPattern ESCAPE '!'
          OR p.content LIKE :keywordPattern ESCAPE '!')
        AND (:authorRole IS NULL OR u.role = :authorRole)
        AND (:feed = 'ALL' OR EXISTS (
          SELECT 1
          FROM expert_follows ef
          JOIN expert_profiles ep ON ep.id = ef.expert_profile_id
          WHERE ef.guardian_user_id = :viewerUserId
            AND ep.user_id = p.author_user_id
            AND ep.deleted_at IS NULL
        ))
      """;

  private static final String SELECT_COLUMNS =
      """
      SELECT p.id, p.post_type, p.title, p.content, p.is_anonymous, p.created_at, p.updated_at,
             u.id, u.nickname,
             (SELECT COUNT(*) FROM post_likes pl WHERE pl.post_id = p.id) AS like_count,
             (SELECT COUNT(*) FROM comments c
                WHERE c.post_id = p.id
                  AND c.comment_status = 'ACTIVE'
                  AND c.is_visible = true
                  AND c.deleted_at IS NULL),
             CASE WHEN EXISTS (
               SELECT 1 FROM post_likes mine
               WHERE mine.post_id = p.id AND mine.user_id = :viewerUserId
             ) THEN 1 ELSE 0 END
      """;

  private final EntityManager entityManager;

  /**
   * 공개 게시글 집계 Query를 실행할 영속성 관리자를 주입한다.
   *
   * @param entityManager DB v1.2 Native Query 실행 도구
   */
  public CommunityPostListRepositoryImpl(EntityManager entityManager) {
    this.entityManager = entityManager;
  }

  /**
   * 정규화된 게시글 관계에서 필터 결과와 전체 건수를 조회한다.
   *
   * @param criteria 검증 완료된 검색 조건
   * @return 페이지 목록과 전체 건수
   */
  @Override
  public CommunityPostListPage findPosts(PostListSearchCriteria criteria) {
    Query contentQuery = entityManager.createNativeQuery(contentSql(criteria));
    bindConditions(contentQuery, criteria);
    contentQuery.setFirstResult(Math.multiplyExact(criteria.page(), criteria.size()));
    contentQuery.setMaxResults(criteria.size());

    @SuppressWarnings("unchecked")
    List<Object[]> resultRows = contentQuery.getResultList();
    List<CommunityPostListRow> content = resultRows.stream().map(this::toRow).toList();

    Query countQuery = entityManager.createNativeQuery("SELECT COUNT(*) " + FROM_AND_WHERE);
    bindConditions(countQuery, criteria);
    long totalElements = ((Number) countQuery.getSingleResult()).longValue();
    return new CommunityPostListPage(content, totalElements);
  }

  private String contentSql(PostListSearchCriteria criteria) {
    String orderColumn =
        criteria.sort().field() == SortField.CREATED_AT ? "p.created_at" : "like_count";
    String direction = criteria.sort().direction() == SortDirection.ASC ? "ASC" : "DESC";
    return SELECT_COLUMNS
        + FROM_AND_WHERE
        + " ORDER BY "
        + orderColumn
        + " "
        + direction
        + ", p.id DESC";
  }

  private void bindConditions(Query query, PostListSearchCriteria criteria) {
    query.setParameter("postType", criteria.postType() == null ? null : criteria.postType().name());
    query.setParameter("keywordPattern", criteria.keywordPattern());
    query.setParameter(
        "authorRole", criteria.authorRole() == null ? null : criteria.authorRole().name());
    query.setParameter("feed", criteria.feed().name());
    query.setParameter("viewerUserId", criteria.viewerUserId());
  }

  private CommunityPostListRow toRow(Object[] values) {
    return new CommunityPostListRow(
        longValue(values[0]),
        PostType.valueOf((String) values[1]),
        (String) values[2],
        (String) values[3],
        booleanValue(values[4]),
        localDateTime(values[5]),
        localDateTime(values[6]),
        nullableLong(values[7]),
        (String) values[8],
        longValue(values[9]),
        longValue(values[10]),
        booleanValue(values[11]));
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
