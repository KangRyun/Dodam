import 'package:flutter/material.dart';

import '../../design_system/design_system.dart';
import '../../features/activity/presentation/screens/activity_screens.dart';
import '../../features/child_mode/presentation/screens/child_mode_screens.dart';
import '../../features/guardian/presentation/screens/guardian_screens.dart';
import '../../features/history/presentation/screens/history_screens.dart';
import '../../features/report/presentation/screens/report_screen.dart';
import '../state/guardian_child_controller.dart';
import '../widgets/app_placeholder_scaffold.dart';
import 'app_routes.dart';

abstract final class AppRouter {
  static Route<void> onGenerateRoute(
    RouteSettings settings, {
    GuardianChildController? childController,
  }) {
    final location = settings.name ?? AppRoutes.guardianHome;
    final segments = Uri.tryParse(location)?.pathSegments ?? const <String>[];

    final screen = switch (segments) {
      ['guardian', 'home'] when childController != null => GuardianHomeScreen(
        controller: childController,
      ),
      ['guardian', 'children', 'select'] when childController != null =>
        ChildSelectScreen(controller: childController),
      ['guardian', 'activities'] => const ActivityHistoryScreen(),
      ['guardian', 'activities', final activityId, 'confirm'] =>
        GuardianConfirmScreen(activityId: activityId),
      ['guardian', 'activities', final activityId] => ActivityDetailScreen(
        activityId: activityId,
      ),
      ['guardian', 'reports', final reportId] => ReportScreen(
        reportId: reportId,
      ),
      ['child', final childId, 'home']
          when _hasChildContext(childController, childId) =>
        ChildModeHomeScreen(child: childController!.selectedChild!),
      ['child', final childId, 'activity', 'drawing']
          when _hasChildContext(childController, childId) =>
        DrawingScreen(childId: childId),
      ['child', final childId, 'activity', 'emotions']
          when _hasChildContext(childController, childId) =>
        EmotionSelectScreen(childId: childId),
      ['child', final childId, 'activity', 'complete']
          when _hasChildContext(childController, childId) =>
        ActivityCompleteScreen(childId: childId),
      ['child', _, ...] => const ChildContextGuardScreen(),
      ['guardian', 'home'] => const ChildContextGuardScreen(),
      ['guardian', 'children', 'select'] => const ChildContextGuardScreen(),
      _ => UnknownRouteScreen(location: location),
    };

    return MaterialPageRoute<void>(settings: settings, builder: (_) => screen);
  }

  static bool _hasChildContext(
    GuardianChildController? controller,
    String childId,
  ) {
    final parsedId = int.tryParse(childId);
    return parsedId != null && controller?.hasSelectedChild(parsedId) == true;
  }

  static void goGuardianHome(BuildContext context) {
    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil(AppRoutes.guardianHome, (route) => false);
  }
}

class ChildContextGuardScreen extends StatelessWidget {
  const ChildContextGuardScreen({super.key});

  @override
  Widget build(BuildContext context) => AppPlaceholderScaffold(
    title: '아동을 먼저 선택해 주세요',
    description: '보호자 홈에서 활동할 아동을 선택한 뒤 다시 시작해 주세요.',
    canPop: false,
    body: AppErrorView(
      title: '선택된 아동이 없어요',
      message: '아동 모드는 보호자 세션에서 선택한 아동 정보가 필요해요.',
      retryLabel: '보호자 홈으로 이동',
      onRetry: () => AppRouter.goGuardianHome(context),
    ),
  );
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
