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
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

/**
 * 리포트 생성이 최종 실패했을 때 보호자에게 남길 알림함 원본을 생성한다.
 *
 * <p>{@link AnalysisCompletedNotificationService}와 같은 구조다 — 발송 성공 여부와 무관하게 알림함 기록이 먼저 남아야 하므로(계약
 * §0-4·§5.1) 이 저장은 발송과 분리된 독립 Transaction에서 수행한다. 실패 기록 Transaction이 이미 커밋된 뒤 호출되므로 여기서 실패해도 실패 기록은
 * 되돌리지 않는다.
 *
 * <p><b>문구에 실패 원인을 싣지 않는다.</b> {@code failureCode}는 {@code OBSERVATION_INVALID_RESPONSE}처럼 내부 분류
 * 이름이라 보호자에게 뜻이 없고, 실패 메시지에는 AI 응답 조각이 섞일 수 있다. 아동 발화·그림 해석·위험 신호는 어떤 경로로도 푸시 본문에 들어가면 안 된다(가드레일 9절
 * · 계약 §6). 보호자는 앱을 열어 리포트 화면에서 다시 시도한다.
 */
@Service
public class ReportFailedNotificationService {

  private static final String TYPE = "ANALYSIS_FAILED";
  private static final String RESOURCE_TYPE_REPORT = "REPORT";
  private static final String TITLE = "리포트를 만들지 못했어요";
  private static final String CONTENT = "앱에서 다시 시도해 주세요";

  private final NotificationRepository notificationRepository;
  private final AnalysisCompletedRecipientRepository recipientRepository;
  private final Clock clock;

  /**
   * 알림 저장소, 수신자 해석 저장소, 시각 기준을 연결한다.
   *
   * <p>수신자 해석은 완료 알림과 같은 저장소를 그대로 쓴다. 리포트 → 그림 활동 → 활성 아동 → 보호자 경로는 완료·실패가 다르지 않아, 같은 Query를 이름만 바꿔
   * 복제하면 한쪽만 고쳐지는 자리가 생긴다.
   *
   * @param notificationRepository 알림 저장소
   * @param recipientRepository 보호자 수신자 해석 저장소
   * @param clock 서버 기준 시계
   */
  public ReportFailedNotificationService(
      NotificationRepository notificationRepository,
      AnalysisCompletedRecipientRepository recipientRepository,
      Clock clock) {
    this.notificationRepository = notificationRepository;
    this.recipientRepository = recipientRepository;
    this.clock = clock;
  }

  /**
   * 최종 실패한 리포트의 보호자마다 실패 알림함 원본을 생성한다.
   *
   * <p>전파 수준이 {@code REQUIRES_NEW}인 이유는 {@link
   * AnalysisCompletedNotificationService#createAnalysisCompleted}와 같다 — 커밋 직후 호출이라 {@code
   * REQUIRED}면 이미 끝난 Transaction에 참여해 INSERT가 조용히 사라진다(S15P11B209-749).
   *
   * @param reportId 최종 실패한 리포트 식별자
   * @return 저장된 알림의 발송용 요약 목록이며 수신 대상이 없으면 빈 목록
   */
  @Transactional(propagation = Propagation.REQUIRES_NEW)
  public List<CreatedNotification> createReportFailed(Long reportId) {
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
