package com.ssafy.b209.notification.service;

import com.ssafy.b209.notification.domain.Notification;
import com.ssafy.b209.notification.repository.AnalysisCompletedRecipientRepository;
import com.ssafy.b209.notification.repository.NotificationRepository;
import java.time.Clock;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.List;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 분석 완료 시 보호자에게 남길 알림함 원본을 생성한다.
 *
 * <p>발송 성공 여부와 무관하게 알림함 기록이 먼저 남아야 하므로(계약 §0-4·§5.1) 이 저장은 발송과 분리된 독립 Transaction에서 수행한다. 리포트 완료
 * Transaction이 이미 커밋된 뒤 호출되므로 여기서 실패해도 완료 처리는 되돌리지 않는다.
 *
 * <p>푸시 본문은 아동 이름·그림 내용·분석 원문을 담지 않는 중립 문구만 사용한다(§6).
 */
@Service
public class AnalysisCompletedNotificationService {

  private static final String TYPE = "ANALYSIS_COMPLETED";
  private static final String RESOURCE_TYPE_REPORT = "REPORT";
  private static final String TITLE = "분석이 완료됐어요";
  private static final String CONTENT = "리포트를 확인해 보세요";

  private final NotificationRepository notificationRepository;
  private final AnalysisCompletedRecipientRepository recipientRepository;
  private final Clock clock;

  /**
   * 알림 저장소, 수신자 해석 저장소, 시각 기준을 연결한다.
   *
   * @param notificationRepository 알림 저장소
   * @param recipientRepository 보호자 수신자 해석 저장소
   * @param clock 서버 기준 시계
   */
  public AnalysisCompletedNotificationService(
      NotificationRepository notificationRepository,
      AnalysisCompletedRecipientRepository recipientRepository,
      Clock clock) {
    this.notificationRepository = notificationRepository;
    this.recipientRepository = recipientRepository;
    this.clock = clock;
  }

  /**
   * 완료된 리포트의 보호자마다 분석 완료 알림함 원본을 생성한다.
   *
   * @param reportId 완료된 리포트 식별자
   * @return 저장된 알림의 발송용 요약 목록이며 수신 대상이 없으면 빈 목록
   */
  @Transactional
  public List<CreatedNotification> createAnalysisCompleted(Long reportId) {
    List<Long> guardianUserIds = recipientRepository.findGuardianUserIdsByReportId(reportId);
    if (guardianUserIds.isEmpty()) {
      return List.of();
    }
    LocalDateTime now = LocalDateTime.ofInstant(clock.instant(), ZoneOffset.UTC);
    List<CreatedNotification> created = new ArrayList<>();
    for (Long guardianUserId : guardianUserIds) {
      Notification saved =
          notificationRepository.save(
              Notification.create(guardianUserId, TYPE, TITLE, CONTENT, reportId, null, null, now));
      created.add(
          new CreatedNotification(
              saved.getId(), guardianUserId, TYPE, TITLE, CONTENT, RESOURCE_TYPE_REPORT, reportId));
    }
    return created;
  }
}
