import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';
import '../../domain/failures/push_token_registration_failure.dart';

/// 이 기기가 푸시를 받지 못하는 상태임을 보호자에게 알리는 안내 띠.
///
/// 보호자 대시보드와 알림 팝업이 같은 문구를 쓴다. 아동 화면에는 올리지 않는다.
class PushRegistrationNotice extends StatelessWidget {
  const PushRegistrationNotice({
    required this.failure,
    this.onDismiss,
    this.dense = false,
    super.key,
  });

  static const notice = ValueKey('push-registration-notice');
  static const dismissAction = ValueKey('push-registration-notice-dismiss');

  final PushTokenRegistrationFailure failure;

  /// 안내를 닫는다. 주지 않으면 닫기 버튼을 그리지 않는다.
  final VoidCallback? onDismiss;

  /// 팝업처럼 좁은 자리에서 쓰는 축약 배치.
  final bool dense;

  @override
  Widget build(BuildContext context) => Container(
    key: notice,
    padding: EdgeInsets.all(dense ? AppSpacing.sm : AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.warningSoft,
      borderRadius: BorderRadius.circular(AppRadius.md),
      border: Border.all(color: AppColors.warning),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.notifications_off_outlined,
          size: AppIconSize.lg,
          color: AppColors.warning,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(title, style: AppTypography.bodyStrong),
              const SizedBox(height: AppSpacing.xxs),
              Text(_reasonFor(failure.type), style: AppTypography.bodySm),
              if (!dense) ...[
                const SizedBox(height: AppSpacing.xxs),
                const Text(fallbackHint, style: AppTypography.caption),
              ],
            ],
          ),
        ),
        if (onDismiss case final dismiss?) ...[
          const SizedBox(width: AppSpacing.xs),
          IconButton(
            key: dismissAction,
            onPressed: dismiss,
            tooltip: '안내 닫기',
            iconSize: AppIconSize.md,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close_rounded, color: AppColors.inkMuted),
          ),
        ],
      ],
    ),
  );

  static const title = '푸시 알림을 받지 못할 수 있어요';
  static const fallbackHint = '새 알림은 이 알림 목록에서 계속 확인할 수 있어요.';

  static String _reasonFor(PushTokenRegistrationFailureType type) =>
      switch (type) {
        // 서버가 정한 Token 소유권 정책이라 앱에서 되돌릴 수 없다
        // (S15P11B209-549/550). 보호자가 할 수 있는 조치만 안내한다.
        PushTokenRegistrationFailureType.claimedByAnotherAccount =>
          '이 기기가 다른 계정의 알림 기기로 등록되어 있어요. '
              '그 계정에서 로그아웃한 뒤 다시 로그인하면 이 계정으로 등록돼요.',
        PushTokenRegistrationFailureType.storageUnavailable =>
          '서버가 알림 기기 등록을 준비하지 못했어요. 잠시 뒤 다시 로그인해 주세요.',
      };
}
