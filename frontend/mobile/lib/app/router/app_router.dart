import 'package:flutter/material.dart';

import '../../design_system/design_system.dart';
import '../../features/activity/domain/repositories/activity_repository.dart';
import '../../features/activity/presentation/screens/activity_screens.dart';
import '../../features/auth/auth.dart';
import '../../features/child_mode/presentation/screens/child_mode_screens.dart';
import '../../features/child/data/dto/child_dtos.dart';
import '../../features/child/presentation/screens/child_registration_screen.dart';
import '../../features/community/presentation/screens/community_webview_screen.dart';
import '../../features/drawing/data/dto/drawing_dtos.dart';
import '../../features/drawing/domain/repositories/drawing_repository.dart';
import '../../features/drawing/presentation/screens/drawing_activity_selection_screen.dart';
import '../../features/drawing/presentation/screens/input_method_select_screen.dart';
import '../../features/conversation/conversation.dart';
import '../../features/guardian/presentation/screens/guardian_screens.dart';
import '../../features/history/presentation/screens/history_screens.dart';
import '../../features/notification/domain/repositories/notification_inbox_repository.dart';
import '../../features/notification/presentation/screens/notification_list_screen.dart';
import '../../features/report/presentation/screens/report_screen.dart';
import '../../features/report/presentation/screens/report_list_screen.dart';
import '../../features/report/domain/repositories/report_repository.dart';
import '../../features/report/domain/services/report_file_actions.dart';
import '../../features/consent/domain/repositories/consent_repository.dart';
import '../../features/consent/presentation/screens/consent_management_screen.dart';
import '../../features/settings/presentation/screens/settings_main_screen.dart';
import '../state/guardian_child_controller.dart';
import '../widgets/app_placeholder_scaffold.dart';
import '../widgets/guardian_sidebar_shell.dart';
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
    AuthenticatedUser? Function()? authCurrentUser,
    Future<String?> Function()? communityAccessToken,
    ActivityRepository? activityRepository,
    DrawingRepository? drawingRepository,
    ReportRepository? reportRepository,
    ReportFileActions? reportFileActions,
    NotificationInboxRepository? notificationInboxRepository,
    ConsentRepository? consentRepository,
    Future<BinaryUploadDto?> Function()? drawingCompletionSnapshotProvider,
    ConversationRepository? conversationRepository,
    ConversationEndRepository? conversationEndRepository,
    QuestionTtsRepository? questionTtsRepository,
    QuestionAudioPlayerFactory? questionAudioPlayerFactory,
    VoiceAnswerPlaybackRepository? voiceAnswerPlaybackRepository,
    VoiceAnswerAudioPlayerFactory? voiceAnswerAudioPlayerFactory,
    VoiceAnswerRepository? voiceAnswerRepository,
    SttResultRepository? sttResultRepository,
    ConversationAnswerRepository? conversationAnswerRepository,
    QuestionSkipRepository? questionSkipRepository,
    int? conversationId,
    int? basisAnalysisId,
    bool insideShell = false,
    bool htpPhotoUploadEnabled = false,
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
          headerAction: authSignOut == null
              ? null
              : LogoutActionButton(
                  onSignOut: authSignOut,
                  onSignedOut: goLogin,
                ),
          onAddChild: (context) =>
              AppNavigation.pushNamed(context, AppRoutes.childRegister),
          onEditChild: (context, child) => AppNavigation.pushNamed(
            context,
            AppRoutes.childEdit(child.childId.toString()),
            arguments: child,
          ),
          onChildSelected: (context, child) {
            childController.selectChild(child);
            AppNavigation.resetTo(
              context,
              AppRoutes.childModeHome(child.childId.toString()),
            );
          },
        ),
      ['expert', 'profile'] => const ExpertProfileEntryScreen(),
      // 태블릿 보호자 모드: 좌측 사이드바 셸. 홈은 대시보드, 기록/알림/설정은
      // 각 담당 화면(없으면 자리표시자), 커뮤니티는 웹 전용이라 자리표시자.
      ['guardian', 'home'] when childController != null => GuardianSidebarShell(
        onSwitchProfile: goProfileSelection,
        destinations: [
          GuardianNavItem(
            icon: Icons.home_outlined,
            selectedIcon: Icons.home_rounded,
            label: '홈',
            builder: (_) => _guardianHome(childController, activityRepository),
          ),
          GuardianNavItem(
            icon: Icons.article_outlined,
            selectedIcon: Icons.article_rounded,
            label: '기록',
            builder: (_) => activityRepository == null
                ? const _TabPreparingScreen(
                    title: '활동 기록',
                    description: '활동 기록을 불러올 준비가 아직 되지 않았어요.',
                  )
                : ActivityHistoryScreen(
                    childController: childController,
                    repository: activityRepository,
                    embedded: true,
                  ),
          ),
          GuardianNavItem(
            icon: Icons.forum_outlined,
            selectedIcon: Icons.forum_rounded,
            label: '커뮤니티',
            builder: (_) =>
                CommunityWebView(accessTokenProvider: communityAccessToken),
          ),
          GuardianNavItem(
            icon: Icons.notifications_none_rounded,
            selectedIcon: Icons.notifications_rounded,
            label: '알림',
            builder:
                notificationsTabBuilder ??
                (_) => notificationInboxRepository == null
                    ? const _TabPreparingScreen(
                        title: '알림',
                        description: '로그인 후 알림을 확인할 수 있어요.',
                      )
                    : NotificationListScreen(
                        repository: notificationInboxRepository,
                      ),
          ),
          GuardianNavItem(
            icon: Icons.settings_outlined,
            selectedIcon: Icons.settings_rounded,
            label: '설정',
            builder:
                settingsTabBuilder ??
                (_) => authSignOut != null
                    ? SettingsMainScreen(
                        user: authCurrentUser?.call(),
                        onSignOut: authSignOut,
                      )
                    : const _TabPreparingScreen(
                        title: '설정',
                        description: '로그인 정보를 확인한 뒤 설정을 이용할 수 있어요.',
                      ),
          ),
        ],
      ),
      ['guardian', 'children', 'select'] when childController != null =>
        ChildSelectScreen(controller: childController),
      ['guardian', 'children', 'register'] when childController != null =>
        ChildRegistrationScreen(controller: childController),
      ['guardian', 'children', final childId, 'edit']
          when childController != null =>
        ChildRegistrationScreen(
          controller: childController,
          child: settings.arguments is ChildSummaryDto
              ? settings.arguments! as ChildSummaryDto
              : childController.children.cast<ChildSummaryDto?>().firstWhere(
                  (child) => child?.childId.toString() == childId,
                  orElse: () => null,
                ),
        ),
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
          voiceAnswerPlaybackRepository: voiceAnswerPlaybackRepository,
          voiceAnswerAudioPlayerFactory: voiceAnswerAudioPlayerFactory,
        ),
      ['guardian', 'reports']
          when childController != null && reportRepository != null =>
        ReportListScreen(
          childController: childController,
          repository: reportRepository,
        ),
      ['guardian', 'reports', final reportId] when reportRepository != null =>
        ReportScreen(
          reportId: reportId,
          repository: reportRepository,
          fileActions: reportFileActions,
        ),
      ['guardian', 'notifications'] when notificationInboxRepository != null =>
        NotificationListScreen(repository: notificationInboxRepository),
      ['guardian', 'settings'] when authSignOut != null => SettingsMainScreen(
        user: authCurrentUser?.call(),
        onSignOut: authSignOut,
      ),
      ['guardian', 'settings', 'consents']
          when consentRepository != null && childController != null =>
        ConsentManagementScreen(
          repository: consentRepository,
          children: childController.children,
        ),
      // 커뮤니티는 웹 전용(CLAUDE.md 6절). 웹앱을 웹뷰로 띄우고 로그인 토큰을
      // localStorage에 주입한다. URL은 COMMUNITY_WEB_URL dart-define로 교체 가능.
      ['guardian', 'community'] => CommunityWebViewScreen(
        accessTokenProvider: communityAccessToken,
      ),
      ['child', final childId, 'home']
          when _hasChildContext(childController, childId) &&
              drawingRepository != null =>
        ChildModeHomeScreen(
          child: childController!.selectedChild!,
          drawingRepository: drawingRepository,
          completionSnapshotProvider: drawingCompletionSnapshotProvider,
          htpPhotoUploadEnabled: htpPhotoUploadEnabled,
        ),
      ['child', final childId, 'activity', 'select']
          when _hasChildContext(childController, childId) &&
              drawingRepository != null &&
              settings.arguments is DrawingActivitySelectionRouteArguments =>
        DrawingActivitySelectionScreen(
          childId: int.parse(childId),
          repository: drawingRepository,
          replaceActive:
              (settings.arguments! as DrawingActivitySelectionRouteArguments)
                  .replaceActive,
          completionSnapshotProvider: drawingCompletionSnapshotProvider,
        ),
      ['child', final childId, 'activity', 'input-method']
          when _hasChildContext(childController, childId) &&
              settings.arguments is InputMethodSelectRouteArguments =>
        InputMethodSelectScreen(
          childId:
              (settings.arguments! as InputMethodSelectRouteArguments).childId,
          drawingTypeId:
              (settings.arguments! as InputMethodSelectRouteArguments)
                  .drawingTypeId,
          title: (settings.arguments! as InputMethodSelectRouteArguments).title,
          description: (settings.arguments! as InputMethodSelectRouteArguments)
              .description,
          icon: (settings.arguments! as InputMethodSelectRouteArguments).icon,
          accentColor: (settings.arguments! as InputMethodSelectRouteArguments)
              .accentColor,
          repository: (settings.arguments! as InputMethodSelectRouteArguments)
              .repository,
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
          questionTtsRepository: questionTtsRepository,
          questionAudioPlayerFactory: questionAudioPlayerFactory,
          voiceAnswerRepository: voiceAnswerRepository,
          sttResultRepository: sttResultRepository,
          activityRepository: activityRepository,
          conversationAnswerRepository: conversationAnswerRepository,
          questionSkipRepository: questionSkipRepository,
          conversationId: conversationId,
          basisAnalysisId: basisAnalysisId,
          resumeConversation:
              (settings.arguments! as DrawingRouteArguments).resumeConversation,
          autoRestoreDraft:
              (settings.arguments! as DrawingRouteArguments).autoRestoreDraft,
          startFresh: (settings.arguments! as DrawingRouteArguments).startFresh,
          activityContext:
              (settings.arguments! as DrawingRouteArguments).activityContext,
          inputMethod:
              (settings.arguments! as DrawingRouteArguments).inputMethod,
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
          activityContext: settings.arguments is EmotionSelectRouteArguments
              ? (settings.arguments! as EmotionSelectRouteArguments)
                    .activityContext
              : const DrawingActivityContextDto.general(),
          inputMethod: settings.arguments is EmotionSelectRouteArguments
              ? (settings.arguments! as EmotionSelectRouteArguments).inputMethod
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
      ['guardian', 'children', _, 'edit'] => const ChildContextGuardScreen(),
      ['guardian', 'reports'] => const ChildContextGuardScreen(),
      _ => UnknownRouteScreen(location: location),
    };

    return MaterialPageRoute<void>(settings: settings, builder: (_) => screen);
  }

  static Widget _guardianHome(
    GuardianChildController controller,
    ActivityRepository? activityRepository,
  ) => GuardianHomeScreen(
    controller: controller,
    activityRepository: activityRepository,
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

final class InputMethodSelectRouteArguments {
  const InputMethodSelectRouteArguments({
    required this.childId,
    required this.drawingTypeId,
    required this.title,
    required this.description,
    required this.icon,
    required this.accentColor,
    required this.repository,
  });

  final int childId;
  final int drawingTypeId;
  final String title;
  final String description;
  final IconData icon;
  final Color accentColor;
  final DrawingRepository repository;
}

final class DrawingRouteArguments {
  const DrawingRouteArguments({
    required this.sessionId,
    required this.repository,
    this.completionSnapshotProvider,
    this.resumeConversation = false,
    this.autoRestoreDraft = false,
    this.startFresh = false,
    this.activityContext = const DrawingActivityContextDto.general(),
    this.inputMethod,
  });

  final int sessionId;
  final DrawingRepository repository;
  final Future<BinaryUploadDto?> Function()? completionSnapshotProvider;

  /// 이 세션이 실제로 쓰는 입력 방식(`CANVAS`|`UPLOAD`).
  final String? inputMethod;

  /// 그림 단계를 지난 세션으로 들어올 때 대화를 즉시 이어받게 한다.
  final bool resumeConversation;

  /// 진입 전 이어 그리기를 확인한 경우 캔버스에서 같은 선택을 다시 묻지 않는다.
  final bool autoRestoreDraft;

  /// 주제 선택 뒤 생성한 새 활동은 Draft 확인 없이 빈 캔버스를 연다.
  final bool startFresh;
  final DrawingActivityContextDto activityContext;
}

final class DrawingActivitySelectionRouteArguments {
  const DrawingActivitySelectionRouteArguments({this.replaceActive = false});

  final bool replaceActive;
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
