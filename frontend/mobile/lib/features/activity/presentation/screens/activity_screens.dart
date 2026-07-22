import 'package:flutter/material.dart';

import '../../../../app/router/app_routes.dart';
import '../../../../app/widgets/app_placeholder_scaffold.dart';

class DrawingScreen extends StatelessWidget {
  const DrawingScreen({required this.childId, super.key});

  final String childId;

  @override
  Widget build(BuildContext context) => AppPlaceholderScaffold(
    title: '그림 활동',
    description: 'Galaxy Tab 가로 화면에 맞춘 Canvas가 들어갈 자리예요.',
    childFriendly: true,
    primaryLabel: '그림 완성',
    onPrimary: () =>
        Navigator.of(context).pushNamed(AppRoutes.emotionSelect(childId)),
  );
}

class EmotionSelectScreen extends StatelessWidget {
  const EmotionSelectScreen({required this.childId, super.key});

  final String childId;

  @override
  Widget build(BuildContext context) => AppPlaceholderScaffold(
    title: '감정 선택',
    description: '그림을 그리며 느낀 감정을 고르는 화면이에요.',
    childFriendly: true,
    primaryLabel: '선택 완료',
    onPrimary: () => Navigator.of(
      context,
    ).pushReplacementNamed(AppRoutes.activityComplete(childId)),
  );
}

class ActivityCompleteScreen extends StatelessWidget {
  const ActivityCompleteScreen({required this.childId, super.key});

  final String childId;

  @override
  Widget build(BuildContext context) => const AppPlaceholderScaffold(
    title: '활동 완료',
    description: '참 잘했어요. 이제 보호자에게 태블릿을 전달해 주세요.',
    childFriendly: true,
    canPop: false,
  );
}
