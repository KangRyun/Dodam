import 'package:dodam/features/auth/auth.dart';
import 'package:flutter/material.dart';

void main() => runApp(const OnboardingConsentPreview());

class OnboardingConsentPreview extends StatelessWidget {
  const OnboardingConsentPreview({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: OnboardingConsentScreen(
      onSubmit: (input) async {
        await Future<void>.delayed(const Duration(milliseconds: 700));
        debugPrint('Agreed consents: ${input.agreedConsents}');
      },
    ),
  );
}
