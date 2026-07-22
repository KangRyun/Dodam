enum ConsentCode {
  serviceTerms,
  childPrivacy,
  drawingAnalysis,
  voiceProcessing,
  expertSharing,
  aiTraining,
  marketingNotifications,
}

final class ConsentAgreementInput {
  ConsentAgreementInput({required Set<ConsentCode> agreedConsents})
    : agreedConsents = Set.unmodifiable(agreedConsents);

  final Set<ConsentCode> agreedConsents;

  bool isAgreed(ConsentCode code) => agreedConsents.contains(code);
}
