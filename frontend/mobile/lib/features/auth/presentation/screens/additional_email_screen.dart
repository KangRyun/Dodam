import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';
import '../../domain/entities/additional_email_input.dart';

typedef AdditionalEmailSubmit =
    Future<void> Function(AdditionalEmailInput input);

class AdditionalEmailScreen extends StatefulWidget {
  const AdditionalEmailScreen({required this.onSubmit, this.onBack, super.key});

  final AdditionalEmailSubmit onSubmit;
  final VoidCallback? onBack;

  @override
  State<AdditionalEmailScreen> createState() => _AdditionalEmailScreenState();
}

class _AdditionalEmailScreenState extends State<AdditionalEmailScreen> {
  final _emailController = TextEditingController();
  String? _emailError;
  String? _submitError;
  bool _isSubmitting = false;

  bool get _canSubmit =>
      _emailController.text.trim().isNotEmpty && !_isSubmitting;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;

    final email = _emailController.text.trim();
    final validationMessage = _validateEmail(email);
    if (validationMessage != null) {
      setState(() => _emailError = validationMessage);
      return;
    }

    setState(() {
      _isSubmitting = true;
      _emailError = null;
      _submitError = null;
    });
    try {
      await widget.onSubmit(AdditionalEmailInput(email: email));
    } on Object {
      if (mounted) {
        setState(() => _submitError = '이메일을 저장하지 못했어요. 잠시 후 다시 시도해 주세요.');
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
                constraints: const BoxConstraints(maxWidth: 640),
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
                    const _EmailIllustration(),
                    const SizedBox(height: AppSpacing.lg),
                    const Text(
                      '이메일을 알려주세요',
                      style: TextStyle(
                        color: AppColors.ink,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    const Text(
                      '소셜 계정에서 이메일을 받지 못했어요.\n도담의 중요한 안내를 받을 이메일을 입력해 주세요.',
                      style: TextStyle(
                        color: AppColors.inkMuted,
                        fontSize: 16,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    AppTextField(
                      key: const ValueKey('additional-email-input'),
                      controller: _emailController,
                      label: '이메일',
                      hintText: 'example@email.com',
                      helperText: '로그인 계정을 구분하고 서비스 안내를 전달할 때 사용해요.',
                      errorText: _emailError,
                      prefixIcon: const Icon(Icons.alternate_email_rounded),
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.done,
                      onChanged: (_) => setState(() {
                        _emailError = null;
                        _submitError = null;
                      }),
                      onSubmitted: (_) => _canSubmit ? _submit() : null,
                    ),
                    if (_submitError case final error?) ...[
                      const SizedBox(height: AppSpacing.md),
                      _SubmitFailure(message: error),
                    ],
                    const SizedBox(height: AppSpacing.xl),
                    AppButton(
                      key: const ValueKey('additional-email-next'),
                      label: '확인하고 계속하기',
                      onPressed: _canSubmit ? _submit : null,
                      isLoading: _isSubmitting,
                      trailing: const Icon(Icons.arrow_forward_rounded),
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
    key: const ValueKey('additional-email-back'),
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

String? _validateEmail(String email) {
  if (email.isEmpty) return '이메일을 입력해 주세요.';
  if (email.length > 254) return '이메일은 254자 이하로 입력해 주세요.';
  final parts = email.split('@');
  if (parts.length != 2 ||
      parts.first.isEmpty ||
      parts.last.isEmpty ||
      !parts.last.contains('.') ||
      parts.last.startsWith('.') ||
      parts.last.endsWith('.')) {
    return '올바른 이메일 형식으로 입력해 주세요.';
  }
  return null;
}

class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader();

  @override
  Widget build(BuildContext context) => const Row(
    children: [
      Icon(Icons.eco_rounded, color: AppColors.leaf),
      SizedBox(width: AppSpacing.xs),
      Expanded(
        child: Text(
          '추가 정보',
          style: TextStyle(
            color: AppColors.inkMuted,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ],
  );
}

class _EmailIllustration extends StatelessWidget {
  const _EmailIllustration();

  @override
  Widget build(BuildContext context) => Container(
    width: 72,
    height: 72,
    decoration: const BoxDecoration(
      color: AppColors.leafSoft,
      shape: BoxShape.circle,
    ),
    child: const Icon(
      Icons.mark_email_unread_rounded,
      color: AppColors.leaf,
      size: 34,
    ),
  );
}

class _SubmitFailure extends StatelessWidget {
  const _SubmitFailure({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('additional-email-failure'),
    width: double.infinity,
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.errorSoft,
      borderRadius: BorderRadius.circular(AppRadius.md),
    ),
    child: Row(
      children: [
        const Icon(Icons.error_outline_rounded, color: AppColors.error),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(color: AppColors.error, height: 1.4),
          ),
        ),
      ],
    ),
  );
}
