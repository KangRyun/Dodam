import 'package:flutter/material.dart';

import '../../domain/entities/additional_email_input.dart';
import '../../domain/entities/consent_agreement_input.dart';
import '../../domain/entities/new_user_onboarding_input.dart';
import '../../domain/entities/onboarding_profile_input.dart';
import 'additional_email_screen.dart';
import 'onboarding_consent_screen.dart';
import 'onboarding_profile_screen.dart';

typedef NewUserOnboardingComplete =
    Future<void> Function(NewUserOnboardingInput input);

enum NewUserOnboardingStep { profile, email, consent }

class NewUserOnboardingFlowScreen extends StatefulWidget {
  const NewUserOnboardingFlowScreen({
    required this.needsEmail,
    required this.onComplete,
    this.onBack,
    this.loadConsentTerms,
    super.key,
  });

  final bool needsEmail;
  final NewUserOnboardingComplete onComplete;
  final VoidCallback? onBack;

  /// 약관 상세 보기용 USER 전문 로더(S15P11B209-884).
  final ConsentTermsLoader? loadConsentTerms;

  @override
  State<NewUserOnboardingFlowScreen> createState() =>
      _NewUserOnboardingFlowScreenState();
}

class _NewUserOnboardingFlowScreenState
    extends State<NewUserOnboardingFlowScreen> {
  NewUserOnboardingStep _step = NewUserOnboardingStep.profile;
  OnboardingProfileInput? _profile;
  String? _email;

  // 기본 정보 이후 이메일 제공 여부에 따른 분기
  Future<void> _submitProfile(OnboardingProfileInput input) async {
    setState(() {
      _profile = input;
      _step = widget.needsEmail
          ? NewUserOnboardingStep.email
          : NewUserOnboardingStep.consent;
    });
  }

  Future<void> _submitEmail(AdditionalEmailInput input) async {
    setState(() {
      _email = input.email;
      _step = NewUserOnboardingStep.consent;
    });
  }

  Future<void> _submitConsents(ConsentAgreementInput consents) async {
    final profile = _profile;
    if (profile == null) return;

    await widget.onComplete(
      NewUserOnboardingInput(
        profile: profile,
        email: _email,
        consents: consents,
      ),
    );
  }

  // 현재 단계에서 이전 화면으로 이동
  void _goBack() {
    switch (_step) {
      case NewUserOnboardingStep.profile:
        widget.onBack?.call();
      case NewUserOnboardingStep.email:
        setState(() => _step = NewUserOnboardingStep.profile);
      case NewUserOnboardingStep.consent:
        setState(() {
          _step = widget.needsEmail
              ? NewUserOnboardingStep.email
              : NewUserOnboardingStep.profile;
        });
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: const Duration(milliseconds: 220),
    child: switch (_step) {
      NewUserOnboardingStep.profile => OnboardingProfileScreen(
        key: const ValueKey('onboarding-flow-profile'),
        onSubmit: _submitProfile,
        onBack: widget.onBack == null ? null : _goBack,
      ),
      NewUserOnboardingStep.email => AdditionalEmailScreen(
        key: const ValueKey('onboarding-flow-email'),
        onSubmit: _submitEmail,
        onBack: _goBack,
      ),
      NewUserOnboardingStep.consent => OnboardingConsentScreen(
        key: const ValueKey('onboarding-flow-consent'),
        onSubmit: _submitConsents,
        onBack: _goBack,
        loadConsentTerms: widget.loadConsentTerms,
      ),
    },
  );
}
