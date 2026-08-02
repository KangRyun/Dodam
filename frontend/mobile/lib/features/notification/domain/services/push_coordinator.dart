import 'dart:async';
import 'dart:developer' as developer;

import '../entities/push_message.dart';
import '../repositories/push_token_repository.dart';
import 'push_dedupe.dart';
import 'push_gateway.dart';
import 'push_permission_service.dart';

/// 권한 → Token 등록 → 수신 → 표시·이동으로 이어지는 푸시 흐름을 조정한다.
///
/// SDK는 [PushGateway]·[PushPresenter] 뒤에 있어 이 클래스는 순수 Dart다.
/// 계약: `docs/api/push-notification-delivery-contract.md` §4.
final class PushCoordinator {
  factory PushCoordinator({
    required PushGateway gateway,
    required PushPresenter presenter,
    required PushTokenRepository tokenRepository,
    required PushPermissionService permissionService,
    required void Function(PushMessage message) onOpen,
    required bool Function() isChildModeActive,
    required bool Function() isGuardianSessionActive,
    void Function()? onInboxChanged,
    PushDedupe? dedupe,
    bool exposeTokenInLogs = false,
  }) => PushCoordinator._(
    gateway,
    presenter,
    tokenRepository,
    permissionService,
    onOpen,
    isChildModeActive,
    isGuardianSessionActive,
    onInboxChanged,
    dedupe ?? PushDedupe(),
    exposeTokenInLogs,
  );

  PushCoordinator._(
    this._gateway,
    this._presenter,
    this._tokenRepository,
    this._permissionService,
    this._onOpen,
    this._isChildModeActive,
    this._isGuardianSessionActive,
    this._onInboxChanged,
    this._dedupe,
    this._exposeTokenInLogs,
  );

  final PushGateway _gateway;
  final PushPresenter _presenter;
  final PushTokenRepository _tokenRepository;
  final PushPermissionService _permissionService;
  final void Function(PushMessage message) _onOpen;
  final bool Function() _isChildModeActive;

  /// 지금 보호자 세션이 살아 있는지. 앱 계층만 알 수 있어 주입받는다.
  final bool Function() _isGuardianSessionActive;

  /// 알림함 내용이 바뀌었을 수 있음을 알린다. 미열람 배지를 다시 세는 용도이며
  /// 실패해도 푸시 흐름을 끊지 않는다.
  final void Function()? _onInboxChanged;
  final PushDedupe _dedupe;
  final bool _exposeTokenInLogs;

  final _subscriptions = <StreamSubscription<Object>>[];
  bool _started = false;

  /// 로그인 이후 한 번 호출한다.
  ///
  /// 권한이 거부돼도 예외를 던지지 않는다. 알림함은 그대로 쓸 수 있어야 하고
  /// 푸시는 선택 기능이다(§4.2).
  Future<void> start() async {
    if (_started) return;
    _started = true;

    final status = await _permissionService.request();
    developer.log('알림 권한 = ${status.name}', name: 'push');
    if (status != PushPermissionStatus.granted) return;

    await _presenter.initialize();
    await _registerCurrentToken();

    _subscriptions
      ..add(_gateway.tokenRefreshes.listen(_registerToken))
      ..add(_gateway.foregroundMessages.listen(_present))
      ..add(_gateway.openedMessages.listen(_open))
      // 앱이 떠 있을 때 직접 띄운 알림을 누른 경우다.
      ..add(_presenter.taps.listen(_open));

    // 종료 상태에서 알림을 눌러 실행된 경우를 이어받는다.
    final initial = await _gateway.getInitialMessage();
    if (initial != null) _open(initial);
  }

  /// 로그아웃 시 호출한다. 이 기기 Token을 비활성화하고 구독을 정리한다.
  Future<void> stop() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    _dedupe.clear();
    _started = false;

    await _guard(_tokenRepository.unregister);
  }

  Future<void> _registerCurrentToken() async {
    final token = await _guardValue(_gateway.getToken);
    if (token == null) {
      developer.log('FCM Token 발급 실패 — 등록을 건너뛴다', name: 'push');
      return;
    }
    await _registerToken(token);
  }

  Future<void> _registerToken(String token) async {
    // Token 원문은 비밀이라 평소엔 길이만 남긴다(계약 §5.4). 실기기 검증에서
    // 발송 대상 Token이 필요할 때만 --dart-define=PUSH_LOG_TOKEN=true 로 연다.
    if (_exposeTokenInLogs) {
      developer.log('⚠️ 검증용 FCM Token 노출: $token', name: 'push');
    } else {
      developer.log('FCM Token 등록 시도 (${token.length}자)', name: 'push');
    }
    await _guard(() => _tokenRepository.register(token));
  }

  Future<void> _present(PushMessage message) async {
    // 표시를 건너뛰더라도 알림함에는 새 알림이 쌓였으므로 배지는 갱신한다.
    _notifyInboxChanged();

    // 아동 활동 화면을 알림이 덮거나 위험 문구가 아이에게 노출되면 안 된다
    // (CLAUDE.md 9절·4절 · 계약 §4.4). 알림함에는 이미 원본이 남아 있다.
    if (_isChildModeActive()) return;
    if (!_dedupe.shouldShow(message)) return;

    await _guard(() => _presenter.show(message));
  }

  void _open(PushMessage message) {
    // 백그라운드·종료 상태에서 받은 알림은 _present를 거치지 않아 여기서 처음
    // 알게 된다. 아래 두 게이트보다 **앞**이어야 이동을 막아도 미열람 배지가
    // 정확히 오른다(S15P11B209-502 설계).
    _notifyInboxChanged();

    // 세션이 끝난 뒤 도착한 탭이다. 구독 해제와 플랫폼의 탭 전달이 딱 맞물리지
    // 않아 로그아웃 정리 도중·직후에도 여기까지 올라올 수 있다. S15P11B209-501이
    // "연결 자원이 없으면 알림함"이라는 기본값을 두면서 이동이 항상 일어나게 됐고,
    // 그대로 두면 로그인 화면 위에 직전 보호자의 알림함이 얹힌다(501 QA M-3).
    // 보관했다가 다음 로그인에 여는 방식은 쓰지 않는다 — 여기 오는 탭은 모두
    // 끝난 세션의 것이라 다음 사용자에게는 남의 아동 자원이 된다.
    if (!_isGuardianSessionActive()) {
      developer.log('보호자 세션 없음 — 푸시 이동을 버린다', name: 'push');
      return;
    }

    if (_isChildModeActive()) return;
    _onOpen(message);
  }

  void _notifyInboxChanged() {
    try {
      _onInboxChanged?.call();
    } on Object catch (error) {
      developer.log('알림함 갱신 통지 실패(무시)', name: 'push', error: error);
    }
  }

  /// 푸시 실패가 앱 흐름을 끊지 않게 삼킨다. 부가 기능이라 화면에 오류를
  /// 띄우지 않는다.
  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } on Object catch (error) {
      developer.log('푸시 작업 실패(무시)', name: 'push', error: error);
    }
  }

  Future<T?> _guardValue<T>(Future<T?> Function() action) async {
    try {
      return await action();
    } on Object catch (error) {
      developer.log('푸시 조회 실패(무시)', name: 'push', error: error);
      return null;
    }
  }
}
