import 'package:dodam/features/auth/auth.dart';
import 'package:flutter/material.dart';

void main() => runApp(const OnboardingProfilePreview());

class OnboardingProfilePreview extends StatelessWidget {
  const OnboardingProfilePreview({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: OnboardingProfileScreen(
      onSubmit: (input) async {
        debugPrint('${input.role.wireName}: ${input.nickname}');
        await Future<void>.delayed(const Duration(milliseconds: 500));
      },
    ),
  );
}
