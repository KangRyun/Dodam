import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';
import '../../application/guardian_pin_controller.dart';
import '../../domain/failures/guardian_pin_failure.dart';
import '../../domain/repositories/guardian_pin_repository.dart';
import '../widgets/guardian_pin_panel.dart';

const guardianPinGateKey = ValueKey('guardian-pin-gate');
const guardianPinForgotKey = ValueKey('guardian-pin-forgot');
const guardianPinResetMessageKey = ValueKey('guardian-pin-reset-message');

/// 보호자 홈 앞에 서는 PIN 확인 화면(S15P11B209-874).
///
/// 보호자 전환은 경로가 넷이지만 모두 `/guardian/home` 라우트로 모이므로 이
/// 화면 하나가 그 앞을 막는다. PIN이 아직 없는 계정은 서버 상태를 읽어 설정
/// 흐름으로 시작한다 — "설정된 PIN이 없다"는 이유로 gate를 열어 주지 않는다.
///
/// 잠금 시각·남은 시도 횟수는 모두 서버가 준 값이다. 여기서 시간을 계산하면
/// 기기 시계를 돌려 잠금을 지나갈 수 있다.
final class GuardianPinGateScreen extends StatefulWidget {
  const GuardianPinGateScreen({
    required this.repository,
    required this.onUnlocked,
    this.onReauthenticate,
    super.key,
  });

  final GuardianPinRepository repository;

  /// 검증이 끝났을 때 호출된다. 잠금 해제 기록과 화면 전환은 호출자(라우터)가
  /// 결정한다.
  final ValueChanged<BuildContext> onUnlocked;

  /// PIN을 잊었을 때의 본인확인. 소셜 재로그인이 성공하고 **지금 로그인된 계정과
  /// 같은 계정**일 때만 `true`를 돌려준다(판정은 앱 셸이 한다).
  ///
  /// 주지 않으면 재설정 진입점을 숨긴다. 배선이 빠졌을 때 gate가 열리는 것보다
  /// 복구 경로가 없는 편이 안전하다.
  final Future<bool> Function(BuildContext context)? onReauthenticate;

  @override
  State<GuardianPinGateScreen> createState() => _GuardianPinGateScreenState();
}

final class _GuardianPinGateScreenState extends State<GuardianPinGateScreen> {
  late final GuardianPinController _controller = GuardianPinController(
    repository: widget.repository,
    // 서버 상태를 읽기 전까지는 "PIN이 있다"고 보고 확인 흐름으로 시작한다.
    // 반대로 두면 조회가 실패한 계정에 설정 화면이 뜬다.
    mode: GuardianPinMode.verify,
  );

  /// 최초 조회로 흐름(확인/설정)을 한 번만 정한다. 이후 조회는 잠금 해제 여부만
  /// 확인하므로 사용자가 입력하던 단계를 되돌리지 않는다.
  bool _resolvedInitialMode = false;

  /// 재설정이 진행 중인지. 본인확인과 초기화 사이에 await가 여럿이라 재탭이
  /// 들어오면 소셜 로그인 창과 `reset()` 요청이 겹친다.
  bool _isResetting = false;

  /// 재설정 실패 안내. PIN 흐름 자체의 문구(컨트롤러 소관)와 섞지 않는다.
  String? _resetMessage;

  /// 마지막으로 화면에 반영한 흐름. 확인↔설정이 바뀌면 재설정 진입점의 노출도
  /// 달라지므로 이 화면도 다시 그려야 한다(패널만 컨트롤러를 구독한다).
  late GuardianPinMode _renderedMode = _controller.mode;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_handleControllerChanged);
    _controller.refreshStatus();
  }

  void _handleControllerChanged() {
    _resolveMode();
    if (!mounted || _renderedMode == _controller.mode) return;
    setState(() => _renderedMode = _controller.mode);
  }

  /// PIN이 아직 없는 계정은 설정부터 시작한다.
  ///
  /// 계약상 조회는 `pinConfigured: false`를 담아 200으로 온다. 조회 대신
  /// `PIN_NOT_CONFIGURED`가 오는 경우도 같은 뜻이라 같은 흐름으로 보낸다.
  void _resolveMode() {
    if (_resolvedInitialMode) return;
    final status = _controller.serverStatus;
    final notConfigured =
        _controller.failureType == GuardianPinFailureType.notConfigured;
    if (status == null && !notConfigured) return;
    _resolvedInitialMode = true;
    if (status?.pinConfigured ?? false) return;
    _controller.restart(GuardianPinMode.configure);
  }

  /// PIN을 잊은 보호자를 본인확인 → 서버 초기화 → 새 PIN 설정으로 보낸다.
  ///
  /// 백엔드 `DELETE users/me/guardian-pin`은 현재 PIN 없이 로그인 세션만으로
  /// 지운다. 그래서 초기화 앞에 재인증을 세운다 — 이게 없으면 기기를 넘겨받은
  /// 아이가 이 버튼으로 새 PIN을 설정해 gate를 그냥 지나간다.
  Future<void> _startReset() async {
    final reauthenticate = widget.onReauthenticate;
    if (reauthenticate == null || _isResetting) return;
    setState(() {
      _isResetting = true;
      _resetMessage = null;
    });
    try {
      final confirmed = await reauthenticate(context);
      if (!mounted) return;
      if (!confirmed) {
        setState(
          () => _resetMessage = '본인 확인을 마치지 못했어요. 로그인한 계정으로 다시 시도해 주세요.',
        );
        return;
      }
      await widget.repository.reset();
      if (!mounted) return;
      // 초기 조회가 뒤늦게 도착해 확인 흐름으로 되돌리지 못하게 못 박는다.
      _resolvedInitialMode = true;
      _controller.restart(GuardianPinMode.configure);
      setState(() => _resetMessage = null);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _resetMessage = _resetFailureMessage(error));
    } finally {
      if (mounted) setState(() => _isResetting = false);
    }
  }

  /// 초기화 실패 문구. 서버가 준 typed failure만 구분하고, 나머지는 원인을
  /// 드러내지 않는 일반 문구로 덮는다.
  String _resetFailureMessage(Object error) {
    if (error is! GuardianPinFailure) {
      return 'PIN을 초기화하지 못했어요. 잠시 후 다시 시도해 주세요.';
    }
    return switch (error.type) {
      GuardianPinFailureType.unavailable =>
        '지금은 PIN 기능을 사용할 수 없어요. 잠시 후 다시 시도해 주세요.',
      GuardianPinFailureType.accessTokenInvalid ||
      GuardianPinFailureType.authenticationRequired => '로그인 정보를 다시 확인해 주세요.',
      GuardianPinFailureType.accountSuspended => '현재 계정에서는 이 기능을 사용할 수 없어요.',
      GuardianPinFailureType.userNotFound => '보호자 정보를 확인하지 못했어요.',
      GuardianPinFailureType.dataConflict => '현재 상태를 다시 확인한 뒤 시도해 주세요.',
      _ => 'PIN을 초기화하지 못했어요. 잠시 후 다시 시도해 주세요.',
    };
  }

  @override
  void dispose() {
    _controller.removeListener(_handleControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  /// 재설정 진입점은 확인 흐름에서만 쓸모가 있다. 설정 흐름에는 지울 PIN이
  /// 없고, 잠금 상태에서는 오히려 유일한 탈출구라 그대로 열어 둔다.
  bool get _showsForgotEntry =>
      widget.onReauthenticate != null &&
      _controller.mode == GuardianPinMode.verify;

  @override
  Widget build(BuildContext context) => Scaffold(
    key: guardianPinGateKey,
    backgroundColor: AppColors.canvas,
    body: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: GuardianPinPanel(
              controller: _controller,
              onCompleted: () => widget.onUnlocked(context),
            ),
          ),
          if (_showsForgotEntry) _buildForgotEntry(),
        ],
      ),
    ),
  );

  Widget _buildForgotEntry() => ColoredBox(
    color: AppColors.canvas,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_resetMessage case final message?) ...[
                Semantics(
                  key: guardianPinResetMessageKey,
                  liveRegion: true,
                  label: message,
                  child: ExcludeSemantics(
                    child: Text(
                      message,
                      textAlign: TextAlign.center,
                      style: AppTypography.bodySm.copyWith(
                        color: AppColors.error,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
              ],
              SizedBox(
                height: AppSizes.minTouchTarget,
                // 진행 표시로 무한 애니메이션(스피너)을 두지 않는다. 재설정은
                // 대부분의 시간을 제공자 로그인 화면 위에서 보내 이 버튼이 보이지
                // 않고, 화면 하단에 상시 도는 인디케이터는 스크린 리더와 프레임
                // 정지 판정(테스트 포함)을 모두 방해한다. 중복 실행은 버튼을
                // 비활성으로 막는다.
                child: TextButton(
                  key: guardianPinForgotKey,
                  onPressed: _isResetting ? null : _startReset,
                  child: Text(
                    'PIN을 잊으셨나요?',
                    style: AppTypography.button.copyWith(
                      color: _isResetting
                          ? AppColors.onDisabled
                          : AppColors.inkMuted,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
