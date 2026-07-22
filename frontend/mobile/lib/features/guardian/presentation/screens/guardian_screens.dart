import 'package:flutter/material.dart';

import '../../../../app/router/app_routes.dart';
import '../../../../app/widgets/app_placeholder_scaffold.dart';

class GuardianHomeScreen extends StatelessWidget {
  const GuardianHomeScreen({super.key});

  @override
  Widget build(BuildContext context) => AppPlaceholderScaffold(
    title: '보호자 홈',
    description: '아동을 선택해 활동을 시작하거나 지난 활동 기록을 확인할 수 있어요.',
    canPop: false,
    primaryLabel: '활동 대상 아동 선택',
    onPrimary: () => Navigator.of(context).pushNamed(AppRoutes.childSelect),
    secondaryLabel: '활동 기록 보기',
    onSecondary: () =>
        Navigator.of(context).pushNamed(AppRoutes.activityHistory),
  );
}

class ChildSelectScreen extends StatelessWidget {
  const ChildSelectScreen({super.key});

  @override
  Widget build(BuildContext context) => const AppPlaceholderScaffold(
    title: '활동 대상 아동 선택',
    description: '보호자 세션에서 활동할 아동을 선택하는 화면이에요.',
    primaryLabel: '아동 선택 후 시작',
  );
}

class GuardianConfirmScreen extends StatelessWidget {
  const GuardianConfirmScreen({required this.activityId, super.key});

  final String activityId;

  @override
  Widget build(BuildContext context) => AppPlaceholderScaffold(
    title: '보호자 확인',
    description: '아동 활동이 끝난 뒤 보호자가 결과를 확인하는 화면이에요.',
    primaryLabel: '활동 상세 보기',
    onPrimary: () => Navigator.of(
      context,
    ).pushReplacementNamed(AppRoutes.activityDetail(activityId)),
  );
}
