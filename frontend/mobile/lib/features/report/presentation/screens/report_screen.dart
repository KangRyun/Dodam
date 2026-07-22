import 'package:flutter/material.dart';

import '../../../../app/widgets/app_placeholder_scaffold.dart';

class ReportScreen extends StatelessWidget {
  const ReportScreen({required this.reportId, super.key});

  final String reportId;

  @override
  Widget build(BuildContext context) => const AppPlaceholderScaffold(
    title: '관찰 리포트',
    description: '활동을 바탕으로 보호자에게 제공할 관찰 정보를 확인하는 화면이에요.',
  );
}
