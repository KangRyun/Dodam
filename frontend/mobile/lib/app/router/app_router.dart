import 'package:flutter/material.dart';

import '../../design_system/design_system.dart';
import '../../features/activity/presentation/screens/activity_screens.dart';
import '../../features/child_mode/presentation/screens/child_mode_screens.dart';
import '../../features/guardian/presentation/screens/guardian_screens.dart';
import '../../features/history/presentation/screens/history_screens.dart';
import '../../features/report/presentation/screens/report_screen.dart';
import '../widgets/app_placeholder_scaffold.dart';
import 'app_routes.dart';

abstract final class AppRouter {
  static Route<void> onGenerateRoute(RouteSettings settings) {
    final location = settings.name ?? AppRoutes.guardianHome;
    final segments = Uri.tryParse(location)?.pathSegments ?? const <String>[];

    final screen = switch (segments) {
      ['guardian', 'home'] => const GuardianHomeScreen(),
      ['guardian', 'children', 'select'] => const ChildSelectScreen(),
      ['guardian', 'activities'] => const ActivityHistoryScreen(),
      ['guardian', 'activities', final activityId, 'confirm'] =>
        GuardianConfirmScreen(activityId: activityId),
      ['guardian', 'activities', final activityId] => ActivityDetailScreen(
        activityId: activityId,
      ),
      ['guardian', 'reports', final reportId] => ReportScreen(
        reportId: reportId,
      ),
      ['child', final childId, 'home'] => ChildModeHomeScreen(childId: childId),
      ['child', final childId, 'activity', 'drawing'] => DrawingScreen(
        childId: childId,
      ),
      ['child', final childId, 'activity', 'emotions'] => EmotionSelectScreen(
        childId: childId,
      ),
      ['child', final childId, 'activity', 'complete'] =>
        ActivityCompleteScreen(childId: childId),
      _ => UnknownRouteScreen(location: location),
    };

    return MaterialPageRoute<void>(settings: settings, builder: (_) => screen);
  }

  static void goGuardianHome(BuildContext context) {
    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil(AppRoutes.guardianHome, (route) => false);
  }
}

class UnknownRouteScreen extends StatelessWidget {
  const UnknownRouteScreen({required this.location, super.key});

  final String location;

  @override
  Widget build(BuildContext context) => AppPlaceholderScaffold(
    title: '페이지를 찾을 수 없어요',
    description: '요청한 화면이 없거나 이동 경로가 올바르지 않아요.',
    body: AppErrorView(
      title: '페이지를 찾을 수 없어요',
      message: '보호자 홈으로 돌아가 다시 시작해 주세요.',
      retryLabel: '보호자 홈으로 이동',
      onRetry: () => AppRouter.goGuardianHome(context),
    ),
  );
}
