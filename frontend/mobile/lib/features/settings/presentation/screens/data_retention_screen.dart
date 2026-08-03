import 'package:flutter/material.dart';

import '../../../../app/widgets/app_failure_view.dart';
import '../../../../design_system/design_system.dart';
import '../../../consent/presentation/screens/consent_terms_screen.dart';
import '../../../consent/presentation/widgets/consent_term_detail_sheet.dart';
import '../../application/data_retention_controller.dart';
import '../../domain/repositories/data_retention_repository.dart';

/// 설정 > 데이터 보관 기간 (S15P11B209-456).
///
/// 본인에게 적용 중인 보관 기간과 만료 안내 시점을 조회해 보여주고, 프리셋
/// 칩으로 바꿔 저장한다(`GET`·`PATCH /users/me/data-retention`).
///
/// 계약(`docs/api/data-retention-policy-contract.md`)이 정한 표시 원칙을 지킨다.
/// - 수치는 잠정값이므로 `PROVISIONAL`일 때 "확정 전" 안내를 띄운다(§0-3, §5③).
/// - "N일 후 삭제됩니다" 같은 삭제 집행 약속을 넣지 않는다 — 삭제 소비자가 아직
///   없다(§5①). 화면은 보관·안내 "기준"이라고만 말한다.
/// - 안내 시점은 보관 기간보다 짧아야 한다는 불변식을 컨트롤러가 지킨다(§2).
class DataRetentionScreen extends StatefulWidget {
  const DataRetentionScreen({
    required this.repository,
    this.openPrivacyPolicy,
    super.key,
  });

  final DataRetentionRepository repository;

  /// 개인정보 처리방침 원문을 열 때 실행할 동작. 주지 않으면 앱 안 웹뷰로
  /// 이동한다(웹뷰는 플랫폼 구현이 필요해 위젯 테스트에서 대체 동작을 넣는다).
  final TermUrlOpener? openPrivacyPolicy;

  @override
  State<DataRetentionScreen> createState() => _DataRetentionScreenState();
}

class _DataRetentionScreenState extends State<DataRetentionScreen> {
  late final DataRetentionController _controller = DataRetentionController(
    widget.repository,
  );

  @override
  void initState() {
    super.initState();
    _controller.load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final succeeded = await _controller.save();
    if (!mounted) return;
    if (succeeded) {
      showAppMessage(
        context,
        message: '보관 기간을 저장했어요.',
        type: AppMessageType.success,
      );
      return;
    }
    final message = _controller.saveFailureMessage;
    if (message != null) {
      showAppMessage(context, message: message, type: AppMessageType.error);
    }
  }

  /// 설정 > 약관 및 정책의 "개인정보 처리방침"과 같은 공표 문서를 같은 방식으로
  /// 연다. 새 주소를 하드코딩하지 않고 그 헬퍼를 재사용한다.
  void _openPrivacyPolicy() {
    const title = '개인정보 처리방침';
    final url = consentTermContentUri(legalDocumentUrl('privacy/'));
    if (url == null) {
      showAppMessage(
        context,
        message: '$title 주소를 열 수 없어요.',
        type: AppMessageType.error,
      );
      return;
    }
    openConsentTermUrl(context, title, url, openTermUrl: widget.openPrivacyPolicy);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.canvas,
    appBar: AppTopBar(
      title: '데이터 보관 기간',
      onBack: () => Navigator.of(context).maybePop(),
    ),
    body: SafeArea(
      child: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) => switch (_controller.status) {
          DataRetentionStatus.loading => const AppLoadingView(
            key: ValueKey('data-retention-loading'),
            message: '보관 설정을 불러오고 있어요',
          ),
          DataRetentionStatus.error => AppFailureView(
            title: '보관 설정을 불러오지 못했어요',
            failure: _controller.error,
            onRetry: _controller.load,
          ),
          DataRetentionStatus.ready => _DataRetentionBody(
            controller: _controller,
            onSave: _save,
            onOpenPrivacyPolicy: _openPrivacyPolicy,
          ),
        },
      ),
    ),
  );
}

class _DataRetentionBody extends StatelessWidget {
  const _DataRetentionBody({
    required this.controller,
    required this.onSave,
    required this.onOpenPrivacyPolicy,
  });

  final DataRetentionController controller;
  final Future<void> Function() onSave;
  final VoidCallback onOpenPrivacyPolicy;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(AppSpacing.xl),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSizes.contentMaxWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SectionCard(
              title: '데이터를 얼마나 보관할까요',
              description: '아이의 그림·대화·분석 데이터를 보관하는 기간이에요.',
              child: _ChipGroup(
                children: [
                  for (final days in controller.retentionOptions)
                    _OptionChip(
                      key: ValueKey('data-retention-days-$days'),
                      label: '$days일',
                      isSelected: controller.retentionDays == days,
                      onTap: () => controller.setRetentionDays(days),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            _SectionCard(
              title: '만료 안내는 언제 받을까요',
              description: '보관 기간이 끝나기 전에 미리 알려드릴 시점이에요.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ChipGroup(
                    children: [
                      for (final days in controller.noticeOptions)
                        _OptionChip(
                          key: ValueKey('data-retention-notice-$days'),
                          label: '$days일 전',
                          isSelected: controller.noticeDaysBefore == days,
                          isEnabled: controller.isNoticeOptionEnabled(days),
                          onTap: () => controller.setNoticeDaysBefore(days),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.info_outline_rounded,
                        size: AppIconSize.sm,
                        color: AppColors.inkMuted,
                      ),
                      const SizedBox(width: AppSpacing.xxs),
                      Expanded(
                        child: Text(
                          '안내 시점은 보관 기간보다 짧아야 해요.',
                          style: AppTypography.bodySm,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            _PolicyNoteCard(onOpenPrivacyPolicy: onOpenPrivacyPolicy),
            const SizedBox(height: AppSpacing.xl),
            AppButton(
              key: const ValueKey('data-retention-save'),
              label: '저장',
              isLoading: controller.isSaving,
              onPressed: controller.canSave ? () => onSave() : null,
            ),
          ],
        ),
      ),
    ),
  );
}

/// 흰 카드 + 제목·설명 + 내용. 화면의 각 설정 묶음을 담는다.
class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.description,
    required this.child,
  });

  final String title;
  final String description;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.lg),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      border: Border.all(color: AppColors.outline),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppTypography.titleMd),
        const SizedBox(height: AppSpacing.xxs),
        Text(description, style: AppTypography.bodySm),
        const SizedBox(height: AppSpacing.md),
        child,
      ],
    ),
  );
}

class _ChipGroup extends StatelessWidget {
  const _ChipGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: AppSpacing.xs,
    runSpacing: AppSpacing.xs,
    children: children,
  );
}

/// 값 하나를 고르는 알약형 칩. 선택·비활성 상태를 색으로 구분한다.
class _OptionChip extends StatelessWidget {
  const _OptionChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.isEnabled = true,
    super.key,
  });

  final String label;
  final bool isSelected;
  final bool isEnabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color background;
    final Color border;
    final Color foreground;
    if (!isEnabled) {
      background = AppColors.surfaceSoft;
      border = AppColors.outline;
      foreground = AppColors.onDisabled;
    } else if (isSelected) {
      background = AppColors.leafSoft;
      border = AppColors.leaf;
      foreground = AppColors.ink;
    } else {
      background = AppColors.surface;
      border = AppColors.outline;
      foreground = AppColors.ink;
    }

    return Semantics(
      button: true,
      selected: isSelected,
      enabled: isEnabled,
      child: Material(
        color: background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          side: BorderSide(color: border, width: isSelected ? 2 : 1),
        ),
        child: InkWell(
          onTap: isEnabled ? onTap : null,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isSelected) ...[
                  const Icon(
                    Icons.check_rounded,
                    size: AppIconSize.sm,
                    color: AppColors.leaf,
                  ),
                  const SizedBox(width: AppSpacing.xxs),
                ],
                Text(
                  label,
                  style: AppTypography.bodyStrong.copyWith(
                    color: foreground,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 보관·안내가 무엇을 뜻하는지 설명하고 처리방침으로 잇는 카드.
///
/// 계약 §5①에 따라 "N일 후 삭제됩니다" 같은 삭제 집행 약속을 넣지 않는다.
class _PolicyNoteCard extends StatelessWidget {
  const _PolicyNoteCard({required this.onOpenPrivacyPolicy});

  final VoidCallback onOpenPrivacyPolicy;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.surfaceSoft,
      borderRadius: BorderRadius.circular(AppRadius.lg),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '여기서 정한 값은 보관과 안내의 기준이에요. 실제 삭제 시점은 서비스의 '
          '데이터 처리 정책을 따라요.',
          style: AppTypography.bodySm,
        ),
        const SizedBox(height: AppSpacing.sm),
        InkWell(
          key: const ValueKey('data-retention-privacy-link'),
          onTap: onOpenPrivacyPolicy,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '개인정보 처리방침 보기',
                  style: AppTypography.bodySm.copyWith(
                    color: AppColors.leaf,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: AppSpacing.xxs),
                const Icon(
                  Icons.open_in_new_rounded,
                  size: AppIconSize.sm,
                  color: AppColors.leaf,
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
