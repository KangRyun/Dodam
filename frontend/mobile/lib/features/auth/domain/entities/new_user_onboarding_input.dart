import 'consent_agreement_input.dart';
import 'onboarding_profile_input.dart';

// 신규 사용자 온보딩 최종 입력
final class NewUserOnboardingInput {
  const NewUserOnboardingInput({
    required this.profile,
    required this.consents,
    this.email,
  });

  final OnboardingProfileInput profile;
  final String? email;
  final ConsentAgreementInput consents;
}
