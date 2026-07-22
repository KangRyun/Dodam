import 'package:dodam/features/auth/auth.dart';
import 'package:flutter/material.dart';

void main() => runApp(const AdditionalEmailPreview());

class AdditionalEmailPreview extends StatelessWidget {
  const AdditionalEmailPreview({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: AdditionalEmailScreen(
      onSubmit: (input) async {
        debugPrint('Additional email: ${input.email}');
        await Future<void>.delayed(const Duration(milliseconds: 500));
      },
    ),
  );
}
