import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';
import '../../../child/data/dto/child_consent_dtos.dart';
import '../../../consent/presentation/widgets/consent_term_detail_sheet.dart';
import '../../domain/entities/consent_agreement_input.dart';

typedef OnboardingConsentSubmit =
    Future<void> Function(ConsentAgreementInput input);

/// 상세 보기용 USER 범위 약관 전문을 불러온다. null이면 상세 보기는 짧은 요약만
/// 보여준다(S15P11B209-884).
typedef ConsentTermsLoader = Future<List<ConsentTermDto>> Function();

class OnboardingConsentScreen extends StatefulWidget {
  const OnboardingConsentScreen({
    required this.onSubmit,
    this.onBack,
    this.loadConsentTerms,
    super.key,
  });

  final OnboardingConsentSubmit onSubmit;
  final VoidCallback? onBack;

  /// 설정과 동일한 서버 약관 전문(`contentHtml`)을 상세 보기에 쓰기 위한 로더.
  final ConsentTermsLoader? loadConsentTerms;

  @override
  State<OnboardingConsentScreen> createState() =>
      _OnboardingConsentScreenState();
}

class _OnboardingConsentScreenState extends State<OnboardingConsentScreen> {
  final Set<ConsentCode> _agreedConsents = {};
  bool _isSubmitting = false;
  String? _submitError;

  // 상세 보기용 서버 약관 전문(USER 범위). 로더가 없거나 실패하면 비어 있고,
  // 상세 보기는 짧은 요약으로 대체한다(S15P11B209-884).
  List<ConsentTermDto> _serverTerms = const [];

  @override
  void initState() {
    super.initState();
    _loadConsentTerms();
  }

  Future<void> _loadConsentTerms() async {
    final loader = widget.loadConsentTerms;
    if (loader == null) return;
    try {
      final terms = await loader();
      if (mounted) setState(() => _serverTerms = terms);
    } catch (_) {
      // 전문 로드 실패는 조용히 무시하고 짧은 요약으로 대체한다.
    }
  }

  // 서버 약관 termCode ↔ 온보딩 ConsentCode 매핑(remote_auth_repository와 동일 기준).
  ConsentCode? _codeForTermCode(String termCode) => switch (termCode) {
    'SERVICE_TOS' || 'SERVICE_TERMS' => ConsentCode.serviceTerms,
    'CHILD_PERSONAL_INFO' => ConsentCode.childPrivacy,
    'DRAWING_ANALYSIS' => ConsentCode.drawingAnalysis,
    'VOICE_PROCESSING' => ConsentCode.voiceProcessing,
    'EXPERT_SHARING' => ConsentCode.expertSharing,
    'AI_TRAINING' => ConsentCode.aiTraining,
    'MARKETING' => ConsentCode.marketingNotifications,
    _ => null,
  };

  ConsentTermDto? _serverTermFor(ConsentCode code) {
    for (final term in _serverTerms) {
      if (_codeForTermCode(term.termCode) == code) return term;
    }
    return null;
  }

  // 약관 상세 보기: 서버 전문(설정과 동일한 시트)이 있으면 그걸 우선하고, 없으면
  // 짧은 요약 다이얼로그로 대체한다(S15P11B209-884).
  Future<void> _showConsentDetail(_ConsentItem item) {
    final term = _serverTermFor(item.code);
    final hasFullText =
        (term?.contentHtml?.trim().isNotEmpty ?? false) ||
        (term?.contentUrl?.trim().isNotEmpty ?? false);
    if (term != null && hasFullText) {
      return showConsentTermDetailSheet(
        context: context,
        termId: term.termId,
        title: term.title,
        required: term.required,
        version: term.version,
        contentHtml: term.contentHtml,
        contentUrl: term.contentUrl,
      );
    }
    return showDialog<void>(
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
  }

  // 보호자(사용자) 가입 단계에서는 USER 범위 약관만 다룬다. 아동 관련(개인정보·
  // 그림분석·음성·전문가공유·AI학습) 동의는 아동 등록 시 별도로 받으므로 여기서
  // 제외한다(S15P11B209-884).
  static const _requiredConsents = {ConsentCode.serviceTerms};

  // 이 화면에 노출하는 동의 코드(하단 _consentItems와 1:1).
  Iterable<ConsentCode> get _displayedCodes =>
      _consentItems.map((item) => item.code);

  // 필수 약관 완료 여부
  bool get _hasRequiredConsents =>
      _agreedConsents.containsAll(_requiredConsents);

  // 전체 동의 상태(노출 항목 기준)
  bool get _hasAllConsents =>
      _displayedCodes.every(_agreedConsents.contains);

  void _toggleAll(bool value) {
    setState(() {
      _submitError = null;
      if (value) {
        _agreedConsents.addAll(_displayedCodes);
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
                              onShowDetail: () =>
                                  _showConsentDetail(_consentItems[index]),
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
    required this.onShowDetail,
  });

  final _ConsentItem item;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final VoidCallback onShowDetail;

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
        onPressed: onShowDetail,
        icon: const Text('›', style: TextStyle(fontSize: 28)),
        color: AppColors.inkMuted,
      ),
      const SizedBox(width: AppSpacing.xs),
    ],
  );
}

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

// 보호자(사용자) 가입 단계 약관 — USER 범위만. 아동 관련 동의(개인정보·그림분석·
// 음성·전문가공유·AI학습)는 아동 등록 화면에서 받으므로 여기서는 다루지 않는다
// (S15P11B209-884).
const _consentItems = [
  _ConsentItem(
    code: ConsentCode.serviceTerms,
    label: '서비스 이용약관',
    description: '도담 서비스 이용에 필요한 기본 약관',
    detail: '도담 서비스의 이용 조건과 사용자 권리·의무를 확인합니다.',
    isRequired: true,
  ),
  _ConsentItem(
    code: ConsentCode.marketingNotifications,
    label: '마케팅 및 알림 수신',
    description: '서비스 소식과 이벤트 알림 수신',
    detail: '도담의 서비스 소식과 이벤트 안내를 받을 수 있습니다.',
    isRequired: false,
  ),
];
