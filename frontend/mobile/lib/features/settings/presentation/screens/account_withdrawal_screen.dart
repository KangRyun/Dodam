import 'package:flutter/material.dart';

import '../../../../app/router/app_router.dart';
import '../../../../design_system/design_system.dart';
import '../../../auth/auth.dart';
import '../../application/account_withdrawal_controller.dart';
import '../../domain/repositories/account_withdrawal_repository.dart';
import '../models/account_withdrawal_notice.dart';

/// 회원 탈퇴 확인과 데이터 처리 안내 화면 (USER-05 `DELETE /users/me`).
///
/// 명세 §6.4는 "아동·그림·음성·대화·리포트 삭제 범위와 법적 보존 데이터는 탈퇴
/// 응답 전 확인 화면에 표시한다"고 요구한다. 그래서 안내를 읽고 확인해야만
/// 확인 문구 입력이 열리고, 확인 문구가 정확히 일치해야만 요청을 보낸다.
///
/// 성공하면 로그아웃과 같은 정리([onSignOut])를 그대로 재사용하고 로그인 화면으로
/// 돌아간다. 탈퇴한 계정의 세션이 기기에 남으면 다음 실행에서 만료된 토큰으로
/// 자동 진입을 시도하게 된다.
class AccountWithdrawalScreen extends StatefulWidget {
  const AccountWithdrawalScreen({
    required this.repository,
    required this.onSignOut,
    this.connectedChildCount,
    super.key,
  });

  final AccountWithdrawalRepository repository;
  final AuthSignOut onSignOut;

  /// 현재 계정에 연결된 아이 수. 안내 문구를 이 값에 맞춰 바꾼다.
  ///
  /// 목록 조회가 아직 끝나지 않았거나 실패해 **수를 확인하지 못했으면 `null`**이다.
  /// 기본값을 0이 아니라 `null`로 둔 이유는, 확인하지 못한 상태에서 "아이가 없다"고
  /// 안내하면 서버가 실제로는 아이를 삭제하는데도 거짓 안심을 주기 때문이다.
  final int? connectedChildCount;

  @override
  State<AccountWithdrawalScreen> createState() =>
      _AccountWithdrawalScreenState();
}

class _AccountWithdrawalScreenState extends State<AccountWithdrawalScreen> {
  late final AccountWithdrawalController _controller = AccountWithdrawalController(
    widget.repository,
  );
  final TextEditingController _confirmationField = TextEditingController();

  @override
  void dispose() {
    _confirmationField.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: '정말 탈퇴할까요?',
      message: '탈퇴하면 위 안내대로 데이터가 처리돼요. 되돌릴 수 없어요.',
      confirmLabel: '탈퇴하기',
      isDanger: true,
      illustration: const Icon(
        Icons.warning_amber_rounded,
        size: 48,
        color: AppColors.error,
      ),
    );
    if (confirmed != true || !mounted) return;

    final succeeded = await _controller.submit();
    if (!mounted) return;

    if (!succeeded) {
      final message = _controller.failureMessage;
      if (message != null) {
        showAppMessage(context, message: message, type: AppMessageType.error);
      }
      return;
    }

    // 세션 정리는 로그아웃 경로를 그대로 쓴다. 실패해도 기기 세션은 지워지므로
    // 되돌리지 않고 로그인 화면으로 보낸다.
    try {
      await widget.onSignOut();
    } on Object {
      // 탈퇴는 이미 서버에서 끝났다. 정리 실패로 사용자를 붙잡아 두지 않는다.
    }
    if (!mounted) return;
    showAppMessage(
      context,
      message: '탈퇴 처리가 완료됐어요.',
      type: AppMessageType.success,
    );
    AppRouter.goLogin(context);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.canvas,
    appBar: AppTopBar(
      title: '회원 탈퇴',
      onBack: () => Navigator.of(context).maybePop(),
    ),
    body: SafeArea(
      child: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) => SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppSizes.contentMaxWidth,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _WithdrawalHeader(),
                  const SizedBox(height: AppSpacing.lg),
                  for (final section in buildAccountWithdrawalNotice(
                    connectedChildCount: widget.connectedChildCount,
                  )) ...[
                    _NoticeCard(section: section),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  const SizedBox(height: AppSpacing.xs),
                  AppCheckboxTile(
                    key: const ValueKey('withdrawal-acknowledge'),
                    label: '위 데이터 처리 안내를 모두 확인했어요',
                    value: _controller.noticeAcknowledged,
                    onChanged: _controller.isSubmitting
                        ? null
                        : (value) => _controller.setNoticeAcknowledged(
                            acknowledged: value,
                          ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppTextField(
                    key: const ValueKey('withdrawal-confirmation-field'),
                    controller: _confirmationField,
                    label: '확인 문구',
                    hintText: withdrawalConfirmationKeyword,
                    helperText:
                        '$withdrawalConfirmationKeyword를 그대로 입력하면 탈퇴 버튼이 열려요.',
                    enabled: !_controller.isSubmitting,
                    textInputAction: TextInputAction.done,
                    onChanged: _controller.updateConfirmationInput,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  AppButton(
                    key: const ValueKey('withdrawal-submit'),
                    label: '회원 탈퇴',
                    variant: AppButtonVariant.danger,
                    isLoading: _controller.isSubmitting,
                    onPressed: _controller.canSubmit ? _submit : null,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  AppButton(
                    label: '취소',
                    variant: AppButtonVariant.secondary,
                    onPressed: _controller.isSubmitting
                        ? null
                        : () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _WithdrawalHeader extends StatelessWidget {
  const _WithdrawalHeader();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.lg),
    decoration: BoxDecoration(
      color: AppColors.errorSoft,
      borderRadius: BorderRadius.circular(AppRadius.lg),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.info_outline_rounded, color: AppColors.error),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                '탈퇴 전에 꼭 확인해 주세요',
                style: AppTypography.titleMd.copyWith(color: AppColors.error),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        const Text(
          '탈퇴하면 계정과 아이 데이터가 아래와 같이 처리돼요. 처리 내용을 확인한 뒤 진행해 주세요.',
          style: AppTypography.body,
        ),
      ],
    ),
  );
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({required this.section});

  final AccountWithdrawalNoticeSection section;

  @override
  Widget build(BuildContext context) {
    final visual = _visualFor(section.tone);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(visual.icon, size: AppIconSize.lg, color: visual.color),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(section.title, style: AppTypography.bodyStrong),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          for (final item in section.items)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 6, right: AppSpacing.xs),
                    child: SizedBox.square(
                      dimension: 4,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppColors.inkMuted,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      item,
                      style: AppTypography.body.copyWith(
                        color: AppColors.inkMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _NoticeVisual {
  const _NoticeVisual(this.icon, this.color);

  final IconData icon;
  final Color color;
}

_NoticeVisual _visualFor(AccountWithdrawalNoticeTone tone) => switch (tone) {
  AccountWithdrawalNoticeTone.removed => const _NoticeVisual(
    Icons.delete_outline_rounded,
    AppColors.error,
  ),
  AccountWithdrawalNoticeTone.kept => const _NoticeVisual(
    Icons.inventory_2_outlined,
    AppColors.leaf,
  ),
  AccountWithdrawalNoticeTone.scheduled => const _NoticeVisual(
    Icons.schedule_rounded,
    AppColors.warning,
  ),
  AccountWithdrawalNoticeTone.undecided => const _NoticeVisual(
    Icons.help_outline_rounded,
    AppColors.inkMuted,
  ),
};
