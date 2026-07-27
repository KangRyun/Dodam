import 'package:flutter/material.dart';

import '../../design_system/design_system.dart';
import '../../features/activity/domain/repositories/activity_repository.dart';
import '../../features/activity/presentation/screens/activity_screens.dart';
import '../../features/auth/auth.dart';
import '../../features/child_mode/presentation/screens/child_mode_screens.dart';
import '../../features/child/presentation/screens/child_registration_screen.dart';
import '../../features/drawing/data/dto/drawing_dtos.dart';
import '../../features/drawing/domain/repositories/drawing_repository.dart';
import '../../features/conversation/conversation.dart';
import '../../features/guardian/presentation/screens/guardian_screens.dart';
import '../../features/history/presentation/screens/history_screens.dart';
import '../../features/report/presentation/screens/report_screen.dart';
import '../../features/report/domain/repositories/report_repository.dart';
import '../state/guardian_child_controller.dart';
import '../widgets/app_placeholder_scaffold.dart';
import 'app_routes.dart';

abstract final class AppRouter {
  static Route<void> onGenerateRoute(
    RouteSettings settings, {
    GuardianChildController? childController,
    AuthProviderSignIn? authSignIn,
    AuthOnboardingComplete? authCompleteOnboarding,
    AuthSignOut? authSignOut,
    AuthSessionRestore? authRestoreSession,
    ActivityRepository? activityRepository,
    DrawingRepository? drawingRepository,
    ReportRepository? reportRepository,
    Future<BinaryUploadDto?> Function()? drawingCompletionSnapshotProvider,
    ConversationRepository? conversationRepository,
    ConversationEndRepository? conversationEndRepository,
    VoiceAnswerRepository? voiceAnswerRepository,
    SttResultRepository? sttResultRepository,
    ConversationAnswerRepository? conversationAnswerRepository,
    int? conversationId,
    int? basisAnalysisId,
  }) {
    final location = settings.name ?? AppRoutes.guardianHome;
    final segments = Uri.tryParse(location)?.pathSegments ?? const <String>[];

    final screen = switch (segments) {
      ['auth', 'bootstrap'] when authRestoreSession != null =>
        AuthBootstrapScreen(
          restoreSession: authRestoreSession,
          onProfileSelectionRequired: goProfileSelection,
          onExpertAuthenticated: goExpertProfile,
          onLoginRequired: goLogin,
        ),
      ['auth', 'login']
          when authSignIn != null && authCompleteOnboarding != null =>
        AuthenticationFlowScreen(
          onSignIn: authSignIn,
          onCompleteOnboarding: authCompleteOnboarding,
          onProfileSelectionRequired: goProfileSelection,
          onExpertAuthenticated: goExpertProfile,
        ),
      ['profiles', 'select'] when childController != null =>
        ProfileSelectionScreen(
          controller: childController,
          onGuardianSelected: goGuardianHome,
          onChildSelected: (context, child) {
            childController.selectChild(child);
            Navigator.of(context).pushNamedAndRemoveUntil(
              AppRoutes.childModeHome(child.childId.toString()),
              (route) => false,
            );
          },
        ),
      ['expert', 'profile'] => const ExpertProfileEntryScreen(),
      ['guardian', 'home'] when childController != null => GuardianHomeScreen(
        controller: childController,
        actions: authSignOut == null
            ? const []
            : [
                LogoutActionButton(
                  onSignOut: authSignOut,
                  onSignedOut: goLogin,
                ),
              ],
      ),
      ['guardian', 'children', 'select'] when childController != null =>
        ChildSelectScreen(controller: childController),
      ['guardian', 'children', 'register'] when childController != null =>
        ChildRegistrationScreen(controller: childController),
      ['guardian', 'activities']
          when childController != null && activityRepository != null =>
        ActivityHistoryScreen(
          childController: childController,
          repository: activityRepository,
        ),
      ['guardian', 'activities', final activityId, 'confirm'] =>
        GuardianConfirmScreen(activityId: activityId),
      ['guardian', 'activities', final activityId]
          when activityRepository != null =>
        ActivityDetailScreen(
          activityId: activityId,
          repository: activityRepository,
        ),
      ['guardian', 'reports', final reportId] when reportRepository != null =>
        ReportScreen(reportId: reportId, repository: reportRepository),
      ['child', final childId, 'home']
          when _hasChildContext(childController, childId) &&
              drawingRepository != null =>
        ChildModeHomeScreen(
          child: childController!.selectedChild!,
          drawingRepository: drawingRepository,
          completionSnapshotProvider: drawingCompletionSnapshotProvider,
        ),
      ['child', final childId, 'activity', 'drawing']
          when _hasChildContext(childController, childId) &&
              settings.arguments is DrawingRouteArguments =>
        DrawingScreen(
          childId: childId,
          sessionId: (settings.arguments! as DrawingRouteArguments).sessionId,
          drawingRepository:
              (settings.arguments! as DrawingRouteArguments).repository,
          completionSnapshotProvider:
              (settings.arguments! as DrawingRouteArguments)
                  .completionSnapshotProvider,
          conversationRepository: conversationRepository,
          conversationEndRepository: conversationEndRepository,
          voiceAnswerRepository: voiceAnswerRepository,
          sttResultRepository: sttResultRepository,
          conversationAnswerRepository: conversationAnswerRepository,
          conversationId: conversationId,
          basisAnalysisId: basisAnalysisId,
        ),
      ['child', final childId, 'activity', 'emotions']
          when _hasChildContext(childController, childId) =>
        EmotionSelectScreen(
          childId: childId,
          sessionId: settings.arguments is EmotionSelectRouteArguments
              ? (settings.arguments! as EmotionSelectRouteArguments).sessionId
              : null,
          drawingRepository: settings.arguments is EmotionSelectRouteArguments
              ? (settings.arguments! as EmotionSelectRouteArguments).repository
              : null,
          conversationId: settings.arguments is EmotionSelectRouteArguments
              ? (settings.arguments! as EmotionSelectRouteArguments)
                    .conversationId
              : null,
          conversationAlreadyEnded:
              settings.arguments is EmotionSelectRouteArguments &&
              (settings.arguments! as EmotionSelectRouteArguments)
                  .conversationAlreadyEnded,
          conversationEndRepository:
              settings.arguments is EmotionSelectRouteArguments
              ? (settings.arguments! as EmotionSelectRouteArguments)
                    .conversationEndRepository
              : null,
          conversationEndIdempotencyKey:
              settings.arguments is EmotionSelectRouteArguments
              ? (settings.arguments! as EmotionSelectRouteArguments)
                    .conversationEndIdempotencyKey
              : null,
          conversationEndRequest:
              settings.arguments is EmotionSelectRouteArguments
              ? (settings.arguments! as EmotionSelectRouteArguments)
                    .conversationEndRequest
              : null,
          lastQuestionMessageId:
              settings.arguments is EmotionSelectRouteArguments
              ? (settings.arguments! as EmotionSelectRouteArguments)
                    .lastQuestionMessageId
              : null,
          idempotencyKeyProvider:
              settings.arguments is EmotionSelectRouteArguments
              ? (settings.arguments! as EmotionSelectRouteArguments)
                    .idempotencyKeyProvider
              : null,
        ),
      ['child', final childId, 'activity', 'complete']
          when _hasChildContext(childController, childId) =>
        ActivityCompleteScreen(
          childId: childId,
          sessionId: settings.arguments is ActivityCompleteRouteArguments
              ? (settings.arguments! as ActivityCompleteRouteArguments)
                    .sessionId
              : null,
          drawingRepository:
              settings.arguments is ActivityCompleteRouteArguments
              ? (settings.arguments! as ActivityCompleteRouteArguments)
                    .repository
              : null,
        ),
      ['child', _, ...] => const ChildContextGuardScreen(),
      ['guardian', 'home'] => const ChildContextGuardScreen(),
      ['guardian', 'children', 'select'] => const ChildContextGuardScreen(),
      ['guardian', 'children', 'register'] => const ChildContextGuardScreen(),
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

  static void goProfileSelection(BuildContext context) {
    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil(AppRoutes.profileSelection, (route) => false);
  }

  static void goExpertProfile(BuildContext context) {
    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil(AppRoutes.expertProfile, (route) => false);
  }

  static void goLogin(BuildContext context) {
    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil(AppRoutes.login, (route) => false);
  }
}

final class DrawingRouteArguments {
  const DrawingRouteArguments({
    required this.sessionId,
    required this.repository,
    this.completionSnapshotProvider,
  });

  final int sessionId;
  final DrawingRepository repository;
  final Future<BinaryUploadDto?> Function()? completionSnapshotProvider;
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
