import 'dart:async';

import '../data/dto/notification_inbox_dtos.dart';
import '../domain/repositories/notification_inbox_repository.dart';
import 'notification_badge_controller.dart';

/// [NotificationReadMarker.markRead] 결과.
enum NotificationReadOutcome {
  /// 이미 읽은 알림이라 서버를 부르지 않았다.
  alreadyRead,

  /// 같은 알림의 읽음 처리가 진행 중이라 이번 요청을 흘려보냈다.
  inFlight,

  /// 서버가 읽음으로 처리했다. [NotificationReadMarkResult.readAt]에 시각이 있다.
  success,

  /// 서버 호출이 실패했다. 화면은 사용자에게 안내만 하고 이동은 막지 않는다.
  failure,
}

/// 읽음 처리 결과와, 성공했을 때 서버가 준 읽은 시각.
final class NotificationReadMarkResult {
  const NotificationReadMarkResult(this.outcome, {this.readAt});

  final NotificationReadOutcome outcome;

  /// [NotificationReadOutcome.success]일 때만 값이 있다.
  final String? readAt;

  /// 화면이 카드 하나를 열람 상태로 바꿔야 하는지.
  bool get shouldMarkCardRead => outcome == NotificationReadOutcome.success;
}

/// 알림 단건 읽음 처리(NOTI-04)와 미열람 배지 동기화를 한곳에 모은다.
///
/// 알림함 목록 화면과 보호자 대시보드 알림 팝업이 같은 규칙으로 동작해야
/// 배지와 목록이 어긋나지 않는다. 두 화면이 각자 감산·재조회를 구현하면 한쪽만
/// 고쳐질 위험이 있어 이 클래스를 함께 쓴다. 화면마다 하나씩 만든다(진행 중인
/// 요청 집합이 화면 상태다).
final class NotificationReadMarker {
  NotificationReadMarker(this._repository, {this.badgeController});

  final NotificationInboxRepository _repository;

  /// 읽음 결과를 반영할 배지. 없으면 배지를 건드리지 않고 목록만 동작한다
  /// (단독 라우트·테스트 구성).
  final NotificationBadgeController? badgeController;

  /// 읽음 처리 응답을 기다리는 중인 알림 id. 화면이 들고 있는
  /// [NotificationItemDto]는 build 시점에 캡처된 불변 인스턴스라 응답이 오기
  /// 전에는 계속 미열람으로 보인다. 연타를 막지 않으면 서버는 멱등이라 1건만
  /// 줄지만 배지는 두 번 줄어든다.
  final _pending = <int>{};

  /// 미열람 알림을 읽음으로 바꾸고 배지를 맞춘다.
  ///
  /// 이동의 전제로 삼지 않도록 호출부는 결과를 기다리지 않아도 된다. 푸시 클릭
  /// 경로에는 읽음 호출 자체가 없으므로, 읽음을 이동 조건으로 두면 두 경로의
  /// 동작이 갈라진다(S15P11B209-501).
  Future<NotificationReadMarkResult> markRead(NotificationItemDto item) async {
    if (item.isRead) {
      return const NotificationReadMarkResult(
        NotificationReadOutcome.alreadyRead,
      );
    }
    // 응답을 기다리는 동안 같은 카드를 다시 눌러도 위 isRead 가드는 통과한다.
    // 진행 중인 id를 붙잡아 두 번째 탭을 흘려보내야 감산이 한 번만 일어난다.
    if (!_pending.add(item.notificationId)) {
      return const NotificationReadMarkResult(NotificationReadOutcome.inFlight);
    }

    try {
      final result = await _repository.markRead(item.notificationId);
      // 화면에 미열람으로 남아 있던 항목의 첫 읽음 처리이므로 배지에서 1건 뺀다.
      // 왕복을 기다리지 않고 바로 반응하는 것이 계약 §6의 설계 의도다.
      badgeController?.decrementBy(1);
      // 그리고 서버 값으로 맞춘다. NOTI-04 응답에는 "이번 호출로 미열람이 실제로
      // 줄었는지" 알려주는 필드가 없다(NOTI-05는 updatedCount를 주는 비대칭).
      // 다른 기기에서 이미 읽은 건이면 서버 미열람 수는 그대로인데 여기서만 1을
      // 빼서 배지가 실제보다 적게 남는다. 감산이 맞았으면 서버도 같은 수를 주므로
      // 배지는 움직이지 않고, 틀렸을 때만 제자리로 올라간다 — 정상 경로에는
      // 깜빡임이 없다. decrementBy가 세대를 올려 두어 이 조회가 최신이고,
      // 컨트롤러가 요청을 합쳐 두므로 연타해도 재조회가 늘지 않는다.
      unawaited(badgeController?.refresh());
      return NotificationReadMarkResult(
        NotificationReadOutcome.success,
        readAt: result.readAt,
      );
    } on Object {
      return const NotificationReadMarkResult(NotificationReadOutcome.failure);
    } finally {
      _pending.remove(item.notificationId);
    }
  }
}
