import 'package:flutter/material.dart';

import '../../../../app/widgets/app_placeholder_scaffold.dart';

class ActivityHistoryScreen extends StatelessWidget {
  const ActivityHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) => const AppPlaceholderScaffold(
    title: '활동 기록',
    description: '아동별 지난 그림 활동 목록을 확인하는 화면이에요.',
  );
}

class ActivityDetailScreen extends StatelessWidget {
  const ActivityDetailScreen({required this.activityId, super.key});

  final String activityId;

  @override
  Widget build(BuildContext context) => const AppPlaceholderScaffold(
    title: '활동 상세',
    description: '선택한 활동의 그림, 감정과 진행 정보를 확인하는 화면이에요.',
  );
}
