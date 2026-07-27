import 'dart:async';

import 'package:dodam/features/notification/domain/entities/push_message.dart';
import 'package:dodam/features/notification/domain/repositories/push_token_repository.dart';
import 'package:dodam/features/notification/domain/services/push_coordinator.dart';
import 'package:dodam/features/notification/domain/services/push_gateway.dart';
import 'package:dodam/features/notification/domain/services/push_permission_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _FakeGateway gateway;
  late _FakePresenter presenter;
  late _FakeTokenRepository tokenRepository;
  late _FakePermissionService permissionService;
  late List<PushMessage> opened;
  late bool childModeActive;

  PushCoordinator build() => PushCoordinator(
    gateway: gateway,
    presenter: presenter,
    tokenRepository: tokenRepository,
    permissionService: permissionService,
    onOpen: opened.add,
    isChildModeActive: () => childModeActive,
  );

  PushMessage message(int id) => PushMessage(
    notificationId: id,
    type: 'ANALYSIS_COMPLETED',
    title: '분석이 완료됐어요',
    content: '리포트를 확인해 보세요',
  );

  setUp(() {
    gateway = _FakeGateway();
    presenter = _FakePresenter();
    tokenRepository = _FakeTokenRepository();
    permissionService = _FakePermissionService();
    opened = [];
    childModeActive = false;
  });

  tearDown(() {
    gateway.dispose();
    presenter.dispose();
  });

  test('권한이 허용되면 현재 Token을 등록한다', () async {
    gateway.token = 'fcm-token';

    await build().start();

    expect(tokenRepository.registered, ['fcm-token']);
    expect(presenter.initialized, isTrue);
  });

  test('권한이 거부되면 Token을 등록하지 않고 조용히 끝난다', () async {
    permissionService.status = PushPermissionStatus.denied;
    gateway.token = 'fcm-token';

    await build().start();

    expect(tokenRepository.registered, isEmpty);
    expect(presenter.initialized, isFalse);
  });

  test('Token이 갱신되면 다시 등록한다', () async {
    gateway.token = 'token-1';
    await build().start();

    gateway.emitTokenRefresh('token-2');
    await pumpEventQueue();

    expect(tokenRepository.registered, ['token-1', 'token-2']);
  });

  test('포그라운드 메시지를 표시한다', () async {
    await build().start();

    gateway.emitForeground(message(900));
    await pumpEventQueue();

    expect(presenter.shown.single.notificationId, 900);
  });

  test('같은 알림이 두 번 와도 한 번만 표시한다', () async {
    await build().start();

    gateway
      ..emitForeground(message(900))
      ..emitForeground(message(900));
    await pumpEventQueue();

    expect(presenter.shown, hasLength(1));
  });

  test('아동 모드에서는 표시하지 않는다', () async {
    await build().start();
    childModeActive = true;

    gateway.emitForeground(message(900));
    await pumpEventQueue();

    // 아이 화면을 덮거나 위험 문구가 노출되면 안 된다(가드레일 9절).
    expect(presenter.shown, isEmpty);
  });

  test('알림을 누르면 이동 콜백을 부른다', () async {
    await build().start();

    gateway.emitOpened(message(900));
    await pumpEventQueue();

    expect(opened.single.notificationId, 900);
  });

  test('앱이 떠 있을 때 띄운 알림을 눌러도 이동 콜백을 부른다', () async {
    await build().start();

    presenter.emitTap(message(902));
    await pumpEventQueue();

    expect(opened.single.notificationId, 902);
  });

  test('아동 모드에서는 알림 탭으로 이동하지 않는다', () async {
    await build().start();
    childModeActive = true;

    gateway.emitOpened(message(900));
    await pumpEventQueue();

    expect(opened, isEmpty);
  });

  test('종료 상태에서 알림으로 실행되면 최초 메시지를 이어받는다', () async {
    gateway.initialMessage = message(901);

    await build().start();

    expect(opened.single.notificationId, 901);
  });

  test('Token 발급이 실패해도 예외를 흘리지 않는다', () async {
    gateway.tokenError = StateError('no token');

    await build().start();

    expect(tokenRepository.registered, isEmpty);
  });

  test('등록이 실패해도 수신 구독은 계속된다', () async {
    gateway.token = 'fcm-token';
    tokenRepository.failOnRegister = true;

    final coordinator = build();
    await coordinator.start();
    gateway.emitForeground(message(900));
    await pumpEventQueue();

    expect(presenter.shown, hasLength(1));
  });

  test('중지하면 Token을 해제하고 구독을 끊는다', () async {
    final coordinator = build();
    await coordinator.start();

    await coordinator.stop();
    gateway.emitForeground(message(900));
    await pumpEventQueue();

    expect(tokenRepository.unregisterCount, 1);
    expect(presenter.shown, isEmpty);
  });
}

final class _FakeGateway implements PushGateway {
  final _tokenRefreshes = StreamController<String>.broadcast();
  final _foreground = StreamController<PushMessage>.broadcast();
  final _opened = StreamController<PushMessage>.broadcast();

  String? token;
  Object? tokenError;
  PushMessage? initialMessage;

  void emitTokenRefresh(String value) => _tokenRefreshes.add(value);
  void emitForeground(PushMessage value) => _foreground.add(value);
  void emitOpened(PushMessage value) => _opened.add(value);

  void dispose() {
    _tokenRefreshes.close();
    _foreground.close();
    _opened.close();
  }

  @override
  Future<String?> getToken() async {
    final error = tokenError;
    if (error != null) throw error;
    return token;
  }

  @override
  Stream<String> get tokenRefreshes => _tokenRefreshes.stream;

  @override
  Stream<PushMessage> get foregroundMessages => _foreground.stream;

  @override
  Stream<PushMessage> get openedMessages => _opened.stream;

  @override
  Future<PushMessage?> getInitialMessage() async => initialMessage;
}

final class _FakePresenter implements PushPresenter {
  final List<PushMessage> shown = [];
  final _taps = StreamController<PushMessage>.broadcast();
  bool initialized = false;

  void emitTap(PushMessage value) => _taps.add(value);
  void dispose() => _taps.close();

  @override
  Stream<PushMessage> get taps => _taps.stream;

  @override
  Future<void> initialize() async => initialized = true;

  @override
  Future<void> show(PushMessage message) async => shown.add(message);
}

final class _FakeTokenRepository implements PushTokenRepository {
  final List<String> registered = [];
  int unregisterCount = 0;
  bool failOnRegister = false;

  @override
  Future<void> register(String pushToken) async {
    if (failOnRegister) throw StateError('register failed');
    registered.add(pushToken);
  }

  @override
  Future<void> unregister() async => unregisterCount++;
}

final class _FakePermissionService implements PushPermissionService {
  PushPermissionStatus status = PushPermissionStatus.granted;

  @override
  Future<PushPermissionStatus> request() async => status;

  @override
  Future<bool> openSettings() async => true;
}
