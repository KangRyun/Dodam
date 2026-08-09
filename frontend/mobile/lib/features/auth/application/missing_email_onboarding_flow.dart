import '../domain/entities/authenticated_user.dart';

enum MissingEmailOnboardingStep { emailInput, next }

// 소셜 계정 이메일 제공 여부에 따른 온보딩 분기
final class MissingEmailOnboardingFlow {
  const MissingEmailOnboardingFlow();

  MissingEmailOnboardingStep resolve(AuthenticatedUser user) => user.needsEmail
      ? MissingEmailOnboardingStep.emailInput
      : MissingEmailOnboardingStep.next;
}
