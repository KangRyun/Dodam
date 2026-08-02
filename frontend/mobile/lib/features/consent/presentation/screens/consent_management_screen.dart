import 'package:flutter/material.dart';

import '../../../../app/widgets/app_failure_view.dart';
import '../../../../design_system/design_system.dart';
import '../../../child/data/dto/child_dtos.dart';
import '../../domain/repositories/consent_repository.dart';
import '../controllers/consent_management_controller.dart';
import '../widgets/consent_section_card.dart';
import '../widgets/consent_term_detail_sheet.dart';

/// 설정 > 동의 관리.
///
/// 회원가입 때 받은 동의 목록을 대상별로 보여준다. 필수 약관은 켜짐 상태로
/// 잠그고(표시만), 선택 약관만 On/Off로 철회·재동의할 수 있다. 아동 동의는
/// 드롭다운으로 아이를 골라 확인한다.
class ConsentManagementScreen extends StatefulWidget {
  const ConsentManagementScreen({
    required this.repository,
    required this.children,
    this.openTermUrl,
    super.key,
  });

  final ConsentRepository repository;
  final List<ChildSummaryDto> children;

  /// 약관 전문 URL을 열 때 실행할 동작. 주지 않으면 [openConsentTermUrl]이 앱 안
  /// 웹뷰로 이동한다. 웹뷰는 플랫폼 구현이 필요해 위젯 테스트에서 대체 동작을 넣는다.
  final TermUrlOpener? openTermUrl;

  @override
  State<ConsentManagementScreen> createState() =>
      _ConsentManagementScreenState();
}

class _ConsentManagementScreenState extends State<ConsentManagementScreen> {
  late final ConsentManagementController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ConsentManagementController(widget.repository);
    _controller.loadGuardian();
    final firstChild = widget.children.firstOrNull;
    if (firstChild != null) {
      _controller.selectChild(firstChild.childId);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _toggle(ConsentView item, bool agreed, {int? childId}) async {
    final ok = await _controller.setAgreed(
      termId: item.termId,
      agreed: agreed,
      childId: childId,
    );
    if (!mounted) return;
    if (ok) {
      showAppMessage(
        context,
        message: agreed ? '\'${item.title}\' 동의를 다시 받았어요.' : '철회되었습니다.',
      );
    } else {
      showAppMessage(
        context,
        message: '변경하지 못했어요. 잠시 후 다시 시도해 주세요.',
        type: AppMessageType.error,
      );
    }
  }

  void _showTermDetail(ConsentView item) {
    showConsentTermDetailSheet(
      context: context,
      termId: item.termId,
      title: item.title,
      required: item.required,
      version: item.version,
      contentHtml: item.contentHtml,
      contentUrl: item.contentUrl,
      openTermUrl: widget.openTermUrl,
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.canvas,
    appBar: AppTopBar(
      title: '동의 관리',
      onBack: () => Navigator.of(context).maybePop(),
    ),
    body: SafeArea(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppSizes.wideContentMaxWidth,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _guardianSection(),
                  const SizedBox(height: AppSpacing.lg),
                  _childSection(),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _guardianSection() => _ConsentSection(
    key: const ValueKey('consent-guardian-section'),
    title: '보호자 동의',
    status: _controller.guardianStatus,
    consents: _controller.guardianConsents,
    error: _controller.guardianError,
    onRetry: _controller.loadGuardian,
    isPending: _controller.isPending,
    onToggle: (item, agreed) => _toggle(item, agreed),
    onShowDetail: _showTermDetail,
  );

  Widget _childSection() {
    final children = widget.children;
    if (children.isEmpty) {
      return const ConsentSectionCard(
        title: '아동 동의',
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Text(
            '등록된 아이가 없어요. 아이를 등록하면 아동 동의를 관리할 수 있어요.',
            style: TextStyle(color: AppColors.inkMuted),
          ),
        ),
      );
    }
    final selectedId = _controller.selectedChildId ?? children.first.childId;
    return _ConsentSection(
      key: const ValueKey('consent-child-section'),
      title: '아동 동의',
      status: _controller.childStatus,
      consents: _controller.childConsents,
      error: _controller.childError,
      onRetry: () => _controller.selectChild(selectedId),
      isPending: _controller.isPending,
      onToggle: (item, agreed) => _toggle(item, agreed, childId: selectedId),
      onShowDetail: _showTermDetail,
      header: _ChildPicker(
        children: children,
        selectedId: selectedId,
        onChanged: (id) => _controller.selectChild(id),
      ),
    );
  }
}

class _ChildPicker extends StatelessWidget {
  const _ChildPicker({
    required this.children,
    required this.selectedId,
    required this.onChanged,
  });

  final List<ChildSummaryDto> children;
  final int selectedId;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: DropdownButtonFormField<int>(
      key: const ValueKey('consent-child-picker'),
      initialValue: selectedId,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: '아동',
        filled: true,
        fillColor: AppColors.canvas,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
      ),
      items: [
        for (final child in children)
          DropdownMenuItem<int>(
            value: child.childId,
            child: Text(child.nickname),
          ),
      ],
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
    ),
  );
}

class _ConsentSection extends StatelessWidget {
  const _ConsentSection({
    required this.title,
    required this.status,
    required this.consents,
    required this.error,
    required this.onRetry,
    required this.isPending,
    required this.onToggle,
    required this.onShowDetail,
    this.header,
    super.key,
  });

  final String title;
  final ConsentSectionStatus status;
  final List<ConsentView> consents;
  final Object? error;
  final VoidCallback onRetry;
  final bool Function(int termId) isPending;
  final void Function(ConsentView item, bool agreed) onToggle;
  final void Function(ConsentView item) onShowDetail;
  final Widget? header;

  @override
  Widget build(BuildContext context) => ConsentSectionCard(
    title: title,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ?header,
        switch (status) {
          ConsentSectionStatus.loading => const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
            child: Center(child: CircularProgressIndicator()),
          ),
          ConsentSectionStatus.error => AppFailureView(
            title: '동의 현황을 불러오지 못했어요',
            failure: error,
            onRetry: onRetry,
          ),
          ConsentSectionStatus.ready =>
            consents.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                    child: Text(
                      '표시할 동의 항목이 없어요.',
                      style: TextStyle(color: AppColors.inkMuted),
                    ),
                  )
                : Column(
                    children: [
                      for (final item in consents)
                        _ConsentRow(
                          item: item,
                          pending: isPending(item.termId),
                          onToggle: (agreed) => onToggle(item, agreed),
                          onShowDetail: () => onShowDetail(item),
                        ),
                    ],
                  ),
        },
      ],
    ),
  );
}

class _ConsentRow extends StatelessWidget {
  const _ConsentRow({
    required this.item,
    required this.pending,
    required this.onToggle,
    required this.onShowDetail,
  });

  final ConsentView item;
  final bool pending;
  final ValueChanged<bool> onToggle;
  final VoidCallback onShowDetail;

  @override
  Widget build(BuildContext context) {
    // 필수 약관은 켜짐 상태로 잠가 표시만 한다(철회 불가). 선택 약관만 토글.
    final switchWidget = pending
        ? const SizedBox.square(
            dimension: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Switch(
            key: ValueKey('consent-switch-${item.termId}'),
            value: item.required ? true : item.agreed,
            onChanged: item.required ? null : onToggle,
          );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title, style: AppTypography.bodyStrong),
                const SizedBox(height: AppSpacing.xxs),
                ConsentRequirementBadge(required: item.required),
              ],
            ),
          ),
          IconButton(
            key: ValueKey('consent-detail-${item.termId}'),
            tooltip: '약관 보기',
            icon: const Icon(
              Icons.info_outline_rounded,
              color: AppColors.inkMuted,
            ),
            onPressed: onShowDetail,
          ),
          switchWidget,
        ],
      ),
    );
  }
}

