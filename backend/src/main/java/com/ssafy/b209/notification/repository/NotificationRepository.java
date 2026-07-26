package com.ssafy.b209.notification.repository;

import com.ssafy.b209.notification.domain.Notification;
import java.util.Optional;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/** 수신자 소유 알림의 목록 조회와 읽음 처리를 담당한다. */
public interface NotificationRepository extends JpaRepository<Notification, Long> {

  /**
   * 수신자의 알림을 유형·미열람 조건으로 조회한다.
   *
   * <p>{@code type}이 {@code null}이면 유형 제한을 적용하지 않고, {@code unreadOnly}가 {@code false}면 읽은 알림도 포함한다.
   * 조건을 SQL 한 문장에 담아 조건별 메서드가 늘어나지 않게 한다.
   *
   * @param recipientUserId 수신자 사용자 ID
   * @param type 알림 유형 또는 전체 조회를 뜻하는 {@code null}
   * @param unreadOnly 미열람만 조회할지 여부
   * @param pageable 페이지·크기·정렬
   * @return 조건에 맞는 알림 페이지
   */
  @Query(
      "select notification from Notification notification "
          + "where notification.recipientUserId = :recipientUserId "
          + "and (:type is null or notification.notificationType = :type) "
          + "and (:unreadOnly = false or notification.readAt is null)")
  Page<Notification> findInbox(
      @Param("recipientUserId") Long recipientUserId,
      @Param("type") String type,
      @Param("unreadOnly") boolean unreadOnly,
      Pageable pageable);

  /**
   * 수신자 본인의 알림 한 건을 찾는다.
   *
   * <p>다른 사용자의 알림은 빈 값으로 돌려준다. 접근 거부와 미존재를 구분하면 알림 ID의 존재 여부가 드러난다.
   *
   * @param id 알림 ID
   * @param recipientUserId 수신자 사용자 ID
   * @return 본인 알림이면 해당 알림
   */
  Optional<Notification> findByIdAndRecipientUserId(Long id, Long recipientUserId);
}
