package com.ssafy.b209.notification.repository;

import com.ssafy.b209.notification.domain.NotificationAttribute;
import java.util.Collection;
import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;

/** 알림 부가 속성을 페이지 단위로 한 번에 조회한다. */
public interface NotificationAttributeRepository
    extends JpaRepository<NotificationAttribute, Long> {

  /**
   * 여러 알림의 부가 속성을 한 번의 질의로 가져온다. 항목별 조회로 N+1이 생기지 않게 한다.
   *
   * @param notificationIds 현재 페이지의 알림 ID 목록
   * @return 부가 속성 목록이며 키 순으로 정렬한다
   */
  List<NotificationAttribute> findByNotificationIdInOrderByAttributeKeyAsc(
      Collection<Long> notificationIds);
}
