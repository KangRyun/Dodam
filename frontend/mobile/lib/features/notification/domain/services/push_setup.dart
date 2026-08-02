import '../entities/push_message.dart';
import '../repositories/push_token_repository.dart';
import 'push_coordinator.dart';
import 'push_gateway.dart';
import 'push_permission_service.dart';

/// 푸시 구성 요소 묶음이다.
///
/// 이동 콜백과 아동 모드 판정은 화면 계층만 알 수 있어 [PushCoordinator]를 여기서
/// 만들지 않고, 앱이 [createCoordinator]로 마지막에 조립한다. 이 묶음을 주입하지
/// 않으면 푸시 기능은 꺼진 상태로 동작한다(테스트·목 구성).
final class PushSetup {
  const PushSetup({
    required this.gateway,
    required this.presenter,
    required this.tokenRepository,
    required this.permissionService,
    this.exposeTokenInLogs = false,
  });

  final PushGateway gateway;
  final PushPresenter presenter;
  final PushTokenRepository tokenRepository;
  final PushPermissionService permissionService;

  /// 실기기 검증에서 발송 대상 Token을 확인해야 할 때만 켠다.
  final bool exposeTokenInLogs;

  PushCoordinator createCoordinator({
    required void Function(PushMessage message) onOpen,
    required bool Function() isChildModeActive,
    required bool Function() isGuardianSessionActive,
    void Function()? onInboxChanged,
  }) => PushCoordinator(
    gateway: gateway,
    presenter: presenter,
    tokenRepository: tokenRepository,
    permissionService: permissionService,
    onOpen: onOpen,
    isChildModeActive: isChildModeActive,
    isGuardianSessionActive: isGuardianSessionActive,
    onInboxChanged: onInboxChanged,
    exposeTokenInLogs: exposeTokenInLogs,
  );
}
