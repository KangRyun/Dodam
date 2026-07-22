import 'package:flutter/material.dart';

import '../../../../app/router/app_routes.dart';
import '../../../../app/widgets/app_placeholder_scaffold.dart';

class ChildModeHomeScreen extends StatelessWidget {
  const ChildModeHomeScreen({required this.childId, super.key});

  final String childId;

  @override
  Widget build(BuildContext context) => AppPlaceholderScaffold(
    title: '아동 활동 시작',
    description: '선택한 아동이 편안하게 그림 활동을 시작하는 화면이에요.',
    childFriendly: true,
    canPop: false,
    primaryLabel: '그림 그리기 시작',
    onPrimary: () =>
        Navigator.of(context).pushNamed(AppRoutes.drawing(childId)),
  );
}
