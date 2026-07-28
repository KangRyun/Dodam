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
import '../widgets/guardian_shell.dart';
import 'app_navigation.dart';
import 'app_routes.dart';

abstract final class AppRouter {
  static Route<void> onGenerateRoute(
    RouteSettings settings, {
    GuardianChildController? childController,
    WidgetBuilder? notificationsTabBuilder,
    WidgetBuilder? settingsTabBuilder,
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
    bool insideShell = false,
  }) {
    final location = settings.name ?? AppRoutes.guardianHome;
    final segments = Uri.tryParse(location)?.pathSegments ?? const <String>[];

    // 탭 안에서 다른 화면으로 이동할 때도 앱 전체와 같은 주입값을 그대로 쓴다.
    // `insideShell: true`를 주는 이유는 탭 안에서 보호자 홈을 열었을 때 셸이
    // 또 생기지 않게 하기 위함이다(탭 속의 탭 방지).
    Route<void> tabRouteFactory(RouteSettings tabSettings) => onGenerateRoute(
      tabSettings,
      childController: childController,
      notificationsTabBuilder: notificationsTabBuilder,
      settingsTabBuilder: settingsTabBuilder,
      authSignIn: authSignIn,
      authCompleteOnboarding: authCompleteOnboarding,
      authSignOut: authSignOut,
      authRestoreSession: authRestoreSession,
      activityRepository: activityRepository,
      drawingRepository: drawingRepository,
      reportRepository: reportRepository,
      drawingCompletionSnapshotProvider: drawingCompletionSnapshotProvider,
      conversationRepository: conversationRepository,
      conversationEndRepository: conversationEndRepository,
      voiceAnswerRepository: voiceAnswerRepository,
      sttResultRepository: sttResultRepository,
      conversationAnswerRepository: conversationAnswerRepository,
      conversationId: conversationId,
      basisAnalysisId: basisAnalysisId,
      insideShell: true,
    );

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
          headerAction: authSignOut == null
              ? null
              : LogoutActionButton(
                  onSignOut: authSignOut,
                  onSignedOut: goLogin,
                ),
          onAddChild: (context) =>
              AppNavigation.pushNamed(context, AppRoutes.childRegister),
          onEditProfiles: (context) =>
              showAppMessage(context, message: '프로필 수정·삭제 화면은 준비 중이에요.'),
          onChildSelected: (context, child) {
            childController.selectChild(child);
            AppNavigation.resetTo(
              context,
              AppRoutes.childModeHome(child.childId.toString()),
            );
          },
        ),
      ['expert', 'profile'] => const ExpertProfileEntryScreen(),
      // 셸 밖에서 부르면 하단 탭을 갖춘 보호자 모드 전체를, 탭 안에서 부르면
      // 홈 화면 자체를 연다.
      ['guardian', 'home'] when childController != null && insideShell =>
        _guardianHome(childController, authSignOut),
      ['guardian', 'home'] when childController != null => GuardianShell(
        routeFactory: tabRouteFactory,
        tabs: [
          GuardianShellTab(
            item: const AppBottomTabItem(
              icon: Icons.home_outlined,
              selectedIcon: Icons.home_rounded,
              label: '홈',
            ),
            builder: (_) => _guardianHome(childController, authSignOut),
          ),
          GuardianShellTab(
            item: const AppBottomTabItem(
              icon: Icons.article_outlined,
              selectedIcon: Icons.article_rounded,
              label: '기록',
            ),
            builder: (_) => activityRepository == null
                ? const _TabPreparingScreen(
                    title: '활동 기록',
                    description: '활동 기록을 불러올 준비가 아직 되지 않았어요.',
                  )
                : ActivityHistoryScreen(
                    childController: childController,
                    repository: activityRepository,
                  ),
          ),
          GuardianShellTab(
            item: const AppBottomTabItem(
              icon: Icons.notifications_none_rounded,
              selectedIcon: Icons.notifications_rounded,
              label: '알림',
            ),
            // 알림함 화면(S15P11B209-499)이 완성되면 이 자리에 주입한다.
            builder:
                notificationsTabBuilder ??
                (_) => const _TabPreparingScreen(
                  title: '알림',
                  description: '알림함은 준비 중이에요. 곧 이곳에서 새 소식을 확인할 수 있어요.',
                ),
          ),
          GuardianShellTab(
            item: const AppBottomTabItem(
              icon: Icons.settings_outlined,
              selectedIcon: Icons.settings_rounded,
              label: '설정',
            ),
            // 설정 메인 화면(S15P11B209-454)이 완성되면 이 자리에 주입한다.
            builder:
                settingsTabBuilder ??
                (_) => const _TabPreparingScreen(
                  title: '설정',
                  description: '설정 화면은 준비 중이에요. 동의·알림·데이터 설정이 이곳에 모일 예정이에요.',
                ),
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
      // 아래 세 경로는 전용 화면(알림 S15P11B209-499 · 설정 S15P11B209-454)이
      // 완성되기 전까지 자리표시자로만 매핑해 둔다. 담당 화면이 붙으면 이 arm만 교체한다.
      ['guardian', 'notifications'] => const AppPlaceholderScaffold(
        // NOTI-03 GET /notifications
        title: '알림',
        description: '알림함은 준비 중이에요. 곧 이곳에서 분석 완료·리포트 소식을 확인할 수 있어요.',
      ),
      ['guardian', 'settings'] => const AppPlaceholderScaffold(
        // USER-01 GET /users/me · USER-04 PATCH /users/me/notification-settings
        title: '설정',
        description: '설정 화면은 준비 중이에요. 동의·알림·데이터 설정이 이곳에 모일 예정이에요.',
      ),
      // 커뮤니티는 웹 전용(CLAUDE.md 6절). 웹 커뮤니티 URL과 webview_flutter가
      // 준비되면 이 자리표시자를 WebView 화면으로 교체한다. COMM-01 GET /posts.
      ['guardian', 'community'] => const AppPlaceholderScaffold(
        title: '커뮤니티',
        description: '커뮤니티는 웹에서 제공돼요. 웹 커뮤니티 연결이 준비되면 이곳에서 바로 열려요.',
      ),
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
          resumeConversation:
              (settings.arguments! as DrawingRouteArguments).resumeConversation,
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

  static Widget _guardianHome(
    GuardianChildController controller,
    AuthSignOut? authSignOut,
  ) => GuardianHomeScreen(
    controller: controller,
    actions: authSignOut == null
        ? const []
        : [LogoutActionButton(onSignOut: authSignOut, onSignedOut: goLogin)],
  );

  static bool _hasChildContext(
    GuardianChildController? controller,
    String childId,
  ) {
    final parsedId = int.tryParse(childId);
    return parsedId != null && controller?.hasSelectedChild(parsedId) == true;
  }

  // 아래 이동들은 "여기서 다시 시작"이라 앱 최상단 스택을 갈아끼운다.
  // 탭 안에서 불러도 탭 하나만 바뀌는 일이 없도록 최상단 Navigator를 쓴다.
  static void goGuardianHome(BuildContext context) =>
      AppNavigation.resetTo(context, AppRoutes.guardianHome);

  static void goProfileSelection(BuildContext context) =>
      AppNavigation.resetTo(context, AppRoutes.profileSelection);

  static void goExpertProfile(BuildContext context) =>
      AppNavigation.resetTo(context, AppRoutes.expertProfile);

  static void goLogin(BuildContext context) =>
      AppNavigation.resetTo(context, AppRoutes.login);
}

/// 담당 화면이 아직 붙지 않은 탭에 세우는 자리표시자.
///
/// 탭의 뿌리이므로 뒤로 갈 곳이 없다 — 뒤로가기 버튼을 숨긴다.
class _TabPreparingScreen extends StatelessWidget {
  const _TabPreparingScreen({required this.title, required this.description});

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => AppPlaceholderScaffold(
    title: title,
    description: description,
    canPop: false,
  );
}

final class DrawingRouteArguments {
  const DrawingRouteArguments({
    required this.sessionId,
    required this.repository,
    this.completionSnapshotProvider,
    this.resumeConversation = false,
  });

  final int sessionId;
  final DrawingRepository repository;
  final Future<BinaryUploadDto?> Function()? completionSnapshotProvider;

  /// 그림 단계를 지난 세션으로 들어올 때 대화를 즉시 이어받게 한다.
  final bool resumeConversation;
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
