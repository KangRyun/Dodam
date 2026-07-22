import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';
import '../../domain/entities/consent_agreement_input.dart';

typedef OnboardingConsentSubmit =
    Future<void> Function(ConsentAgreementInput input);

class OnboardingConsentScreen extends StatefulWidget {
  const OnboardingConsentScreen({
    required this.onSubmit,
    this.onBack,
    super.key,
  });

  final OnboardingConsentSubmit onSubmit;
  final VoidCallback? onBack;

  @override
  State<OnboardingConsentScreen> createState() =>
      _OnboardingConsentScreenState();
}

class _OnboardingConsentScreenState extends State<OnboardingConsentScreen> {
  final Set<ConsentCode> _agreedConsents = {};
  bool _isSubmitting = false;
  String? _submitError;

  static const _requiredConsents = {
    ConsentCode.serviceTerms,
    ConsentCode.childPrivacy,
    ConsentCode.drawingAnalysis,
  };

  // 필수 약관 완료 여부
  bool get _hasRequiredConsents =>
      _agreedConsents.containsAll(_requiredConsents);

  // 전체 동의 상태
  bool get _hasAllConsents =>
      _agreedConsents.length == ConsentCode.values.length;

  void _toggleAll(bool value) {
    setState(() {
      _submitError = null;
      if (value) {
        _agreedConsents.addAll(ConsentCode.values);
      } else {
        _agreedConsents.clear();
      }
    });
  }

  void _toggleConsent(ConsentCode code, bool value) {
    setState(() {
      _submitError = null;
      value ? _agreedConsents.add(code) : _agreedConsents.remove(code);
    });
  }

  Future<void> _submit() async {
    if (_isSubmitting || !_hasRequiredConsents) return;

    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });
    try {
      await widget.onSubmit(
        ConsentAgreementInput(agreedConsents: _agreedConsents),
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _submitError = '동의 내용을 저장하지 못했어요. 잠시 후 다시 시도해 주세요.';
        });
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.canvas,
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isTablet = constraints.maxWidth >= 700;
          return SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: isTablet ? AppSpacing.xxl : AppSpacing.lg,
              vertical: AppSpacing.lg,
            ),
            child: Center(
              child: Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxWidth: 680),
                padding: EdgeInsets.all(
                  isTablet ? AppSpacing.xxl : AppSpacing.lg,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(color: AppColors.outline),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.onBack != null) ...[
                      _OnboardingBackButton(onPressed: widget.onBack!),
                      const SizedBox(height: AppSpacing.md),
                    ],
                    const _ProgressHeader(),
                    const SizedBox(height: AppSpacing.xl),
                    const Text(
                      '약관에 동의해 주세요',
                      style: TextStyle(
                        color: AppColors.ink,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    const Text(
                      '도담이 아이의 그림과 이야기를 안전하게 다룰 수 있도록 확인해 주세요.',
                      style: TextStyle(
                        color: AppColors.inkMuted,
                        fontSize: 16,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.leafSoft,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        border: Border.all(color: AppColors.outline),
                      ),
                      child: AppCheckboxTile(
                        key: const ValueKey('consent-all'),
                        label: '전체 동의하기',
                        description: '필수 항목과 선택 항목을 모두 동의해요.',
                        value: _hasAllConsents,
                        onChanged: _isSubmitting ? null : _toggleAll,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.surfaceSoft,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        border: Border.all(color: AppColors.outline),
                      ),
                      child: Column(
                        children: [
                          for (
                            var index = 0;
                            index < _consentItems.length;
                            index++
                          ) ...[
                            _ConsentTile(
                              item: _consentItems[index],
                              value: _agreedConsents.contains(
                                _consentItems[index].code,
                              ),
                              onChanged: _isSubmitting
                                  ? null
                                  : (value) => _toggleConsent(
                                      _consentItems[index].code,
                                      value,
                                    ),
                            ),
                            if (index < _consentItems.length - 1)
                              const Divider(
                                height: 1,
                                indent: AppSpacing.md,
                                endIndent: AppSpacing.md,
                                color: AppColors.outline,
                              ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    const Text(
                      '선택 항목에 동의하지 않아도 도담을 이용할 수 있어요. 동의 내용은 설정에서 언제든 변경할 수 있어요.',
                      style: TextStyle(
                        color: AppColors.inkMuted,
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                    if (_submitError case final error?) ...[
                      const SizedBox(height: AppSpacing.md),
                      Semantics(
                        liveRegion: true,
                        child: Container(
                          key: const ValueKey('consent-submit-error'),
                          width: double.infinity,
                          padding: const EdgeInsets.all(AppSpacing.md),
                          decoration: BoxDecoration(
                            color: AppColors.errorSoft,
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                          child: Text(
                            error,
                            style: const TextStyle(
                              color: AppColors.error,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.xl),
                    AppButton(
                      key: const ValueKey('consent-submit'),
                      label: '동의하고 시작하기',
                      onPressed: _hasRequiredConsents ? _submit : null,
                      isLoading: _isSubmitting,
                      trailing: const Text('→', style: TextStyle(fontSize: 22)),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}

class _OnboardingBackButton extends StatelessWidget {
  const _OnboardingBackButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => TextButton.icon(
    key: const ValueKey('onboarding-consent-back'),
    onPressed: onPressed,
    icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
    label: const Text('뒤로'),
    style: TextButton.styleFrom(
      foregroundColor: AppColors.ink,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
    ),
  );
}

class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader();

  @override
  Widget build(BuildContext context) => const Row(
    children: [
      Text('●', style: TextStyle(color: AppColors.leaf, fontSize: 14)),
      SizedBox(width: AppSpacing.xs),
      Expanded(
        child: Text(
          '시작하기 2 / 2',
          style: TextStyle(
            color: AppColors.inkMuted,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ],
  );
}

class _ConsentTile extends StatelessWidget {
  const _ConsentTile({
    required this.item,
    required this.value,
    required this.onChanged,
  });

  final _ConsentItem item;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: AppCheckboxTile(
          key: ValueKey('consent-${item.code.name}'),
          label: item.label,
          description: item.description,
          value: value,
          isRequired: item.isRequired,
          onChanged: onChanged,
        ),
      ),
      IconButton(
        key: ValueKey('consent-${item.code.name}-detail'),
        tooltip: '${item.label} 자세히 보기',
        onPressed: () => _showConsentDetail(context, item),
        icon: const Text('›', style: TextStyle(fontSize: 28)),
        color: AppColors.inkMuted,
      ),
      const SizedBox(width: AppSpacing.xs),
    ],
  );
}

Future<void> _showConsentDetail(BuildContext context, _ConsentItem item) =>
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(item.label),
        content: Text(item.detail),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('확인'),
          ),
        ],
      ),
    );

class _ConsentItem {
  const _ConsentItem({
    required this.code,
    required this.label,
    required this.description,
    required this.detail,
    required this.isRequired,
  });

  final ConsentCode code;
  final String label;
  final String description;
  final String detail;
  final bool isRequired;
}

const _consentItems = [
  _ConsentItem(
    code: ConsentCode.serviceTerms,
    label: '서비스 이용약관',
    description: '도담 서비스 이용에 필요한 기본 약관',
    detail: '도담 서비스의 이용 조건과 사용자 권리·의무를 확인합니다.',
    isRequired: true,
  ),
  _ConsentItem(
    code: ConsentCode.childPrivacy,
    label: '아동 개인정보 수집·이용',
    description: '아동 프로필과 활동 기록을 안전하게 관리',
    detail: '아동 프로필과 그림 활동 기록의 수집 목적과 보관 기준을 확인합니다.',
    isRequired: true,
  ),
  _ConsentItem(
    code: ConsentCode.drawingAnalysis,
    label: '그림 데이터 분석 활용',
    description: '그림과 활동 과정을 관찰 자료로 정리',
    detail: '그림 결과와 그리기 과정 데이터를 비진단 관찰 자료로 정리합니다.',
    isRequired: true,
  ),
  _ConsentItem(
    code: ConsentCode.voiceProcessing,
    label: '음성 데이터 처리',
    description: '음성 답변을 글자로 변환하고 대화에 활용',
    detail: '아동의 음성 답변을 STT로 변환하고 활동 기록에 활용합니다.',
    isRequired: false,
  ),
  _ConsentItem(
    code: ConsentCode.expertSharing,
    label: '전문가 리포트 공유',
    description: '보호자가 지정한 전문가에게만 자료 공유',
    detail: '보호자가 요청한 경우에만 지정 전문가에게 리포트를 공유합니다.',
    isRequired: false,
  ),
  _ConsentItem(
    code: ConsentCode.aiTraining,
    label: 'AI 학습 데이터 활용',
    description: '비식별 데이터를 서비스 개선에 활용',
    detail: '개인을 알아볼 수 없도록 처리한 데이터를 모델 개선에 활용합니다.',
    isRequired: false,
  ),
  _ConsentItem(
    code: ConsentCode.marketingNotifications,
    label: '마케팅 및 알림 수신',
    description: '서비스 소식과 이벤트 알림 수신',
    detail: '도담의 서비스 소식과 이벤트 안내를 받을 수 있습니다.',
    isRequired: false,
  ),
];
