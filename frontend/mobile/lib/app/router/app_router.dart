import 'dart:async';

import 'package:flutter/material.dart';

import '../../design_system/design_system.dart';
import '../../features/activity/domain/repositories/activity_repository.dart';
import '../../features/activity/presentation/screens/activity_screens.dart';
import '../../features/auth/auth.dart';
import '../../features/child_mode/presentation/screens/child_gallery_screen.dart';
import '../../features/child_mode/presentation/screens/child_mode_screens.dart';
import '../../features/child_mode/domain/dodam_costume.dart';
import '../../features/child/data/dto/child_dtos.dart';
import '../../features/child/domain/repositories/child_profile_image_repository.dart';
import '../../features/child/domain/repositories/child_repository.dart';
import '../../features/child/presentation/screens/child_registration_screen.dart';
import '../../features/community/presentation/screens/community_webview_screen.dart';
import '../../features/drawing/application/drawing_session_start_controller.dart';
import '../../features/drawing/data/dto/drawing_dtos.dart';
import '../../features/drawing/domain/pending_htp_photo.dart';
import '../../features/drawing/domain/repositories/drawing_repository.dart';
import '../../features/drawing/presentation/screens/drawing_activity_selection_screen.dart';
import '../../features/drawing/presentation/screens/input_method_select_screen.dart';
import '../../features/conversation/conversation.dart';
import '../../features/guardian/presentation/screens/guardian_screens.dart';
import '../../features/guardian_pin/domain/repositories/guardian_pin_repository.dart';
import '../../features/guardian_pin/presentation/screens/guardian_pin_gate_screen.dart';
import '../../features/history/presentation/screens/history_screens.dart';
import '../../features/notification/application/notification_badge_controller.dart';
import '../../features/notification/application/push_registration_status_controller.dart';
import '../../features/notification/domain/repositories/notification_inbox_repository.dart';
import '../../features/notification/presentation/screens/notification_list_screen.dart';
import '../../features/report/presentation/screens/report_screen.dart';
import '../../features/report/presentation/screens/report_list_screen.dart';
import '../../features/report/domain/repositories/report_repository.dart';
import '../../features/report/domain/services/report_file_actions.dart';
import '../../features/consent/domain/repositories/consent_repository.dart';
import '../../features/consent/presentation/screens/consent_management_screen.dart';
import '../../features/consent/presentation/screens/consent_terms_screen.dart';
import '../../features/settings/domain/repositories/account_withdrawal_repository.dart';
import '../../features/settings/domain/repositories/data_retention_repository.dart';
import '../../features/settings/domain/repositories/notification_settings_repository.dart';
import '../../features/settings/presentation/screens/account_withdrawal_screen.dart';
import '../../features/settings/presentation/screens/data_retention_screen.dart';
import '../../features/settings/presentation/screens/notification_settings_screen.dart';
import '../../features/settings/presentation/screens/settings_main_screen.dart';
import '../../features/settings/presentation/screens/guardian_profile_screen.dart';
import '../state/guardian_child_controller.dart';
import '../state/guardian_unlock_controller.dart';
import '../widgets/app_placeholder_scaffold.dart';
import '../widgets/guardian_sidebar_shell.dart';
import 'app_navigation.dart';
import 'app_routes.dart';

abstract final class AppRouter {
  static Route<dynamic> onGenerateRoute(
    RouteSettings settings, {
    GuardianChildController? childController,
    ChildRepository? childRepository,
    WidgetBuilder? notificationsTabBuilder,
    WidgetBuilder? settingsTabBuilder,
    AuthProviderSignIn? authSignIn,
    AuthOnboardingComplete? authCompleteOnboarding,
    AuthSignOut? authSignOut,
    AuthSessionRestore? authRestoreSession,
    AuthenticatedUser? Function()? authCurrentUser,
    GuardianProfileLoad? authLoadProfile,
    GuardianProfileUpdate? authUpdateProfile,
    Future<String?> Function()? communityAccessToken,
    ActivityRepository? activityRepository,
    DrawingRepository? drawingRepository,
    ReportRepository? reportRepository,
    ReportFileActions? reportFileActions,
    NotificationInboxRepository? notificationInboxRepository,
    NotificationBadgeController? notificationBadgeController,
    PushRegistrationStatusController? pushRegistrationStatus,
    ValueChanged<String?>? onGuardianTabChanged,
    ConsentRepository? consentRepository,
    AccountWithdrawalRepository? accountWithdrawalRepository,
    DataRetentionRepository? dataRetentionRepository,
    NotificationSettingsRepository? notificationSettingsRepository,
    Future<BinaryUploadDto?> Function()? drawingCompletionSnapshotProvider,
    ConversationRepository? conversationRepository,
    ConversationEndRepository? conversationEndRepository,
    QuestionTtsRepository? questionTtsRepository,
    QuestionAudioPlayerFactory? questionAudioPlayerFactory,
    QuestionSpeechSynthesizer? questionSpeechSynthesizer,
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
    PendingHtpPhotoStore? pendingHtpPhotoStore,
    GuardianUnlockController? guardianUnlock,
    GuardianPinRepository? guardianPinRepository,
    bool guardianPinGateEnabled = false,
    Future<bool> Function(BuildContext context)? onReauthenticateGuardian,
  }) {
    final location = settings.name ?? AppRoutes.guardianHome;
    final segments = Uri.tryParse(location)?.pathSegments ?? const <String>[];

    // 보호자 홈으로 가는 길은 넷(프로필 선택·활동 완료 넘기기·아동 모드 복귀·
    // 오류 화면 재시도)이고 cold start도 여기로 모인다. 모두 이 라우트를 지나므로
    // gate는 라우트 생성 지점 한 곳에만 둔다(S15P11B209-874). 호출처마다 거는
    // 방식은 새 진입점이 생길 때 조용히 빠진다.
    if (_isGuardianHomeRoute(segments) &&
        _guardianPinGateRequired(
          enabled: guardianPinGateEnabled,
          repository: guardianPinRepository,
          unlock: guardianUnlock,
        )) {
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => GuardianPinGateScreen(
          repository: guardianPinRepository!,
          // 배선이 없으면 gate 화면이 재설정 진입점을 숨긴다. 여기서 gate 자체를
          // 건너뛰면 복구 경로가 빠진 구성에서 보호자 홈이 열려 버린다.
          onReauthenticate: onReauthenticateGuardian,
          onUnlocked: (context) {
            guardianUnlock!.unlock();
            // 같은 라우트로 다시 들어가면 이번에는 gate가 통과시킨다.
            AppNavigation.resetTo(context, AppRoutes.guardianHome);
          },
        ),
      );
    }

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
          onGuardianOnboardingCompleted: goGuardianHome,
          onExpertAuthenticated: goExpertProfile,
          // 온보딩 약관 상세 보기용 USER 전문 로더(S15P11B209-884).
          loadConsentTerms: consentRepository == null
              ? null
              : () => consentRepository.getTerms(ConsentTargetScope.user),
        ),
      ['profiles', 'select'] when childController != null =>
        ProfileSelectionScreen(
          controller: childController,
          imageFetcher: childRepository is ChildProfileImageRepository
              ? (childRepository as ChildProfileImageRepository)
                    .downloadProfileImage
              : null,
          onGuardianSelected: goGuardianHome,
          headerAction: authSignOut == null
              ? null
              : LogoutActionButton(
                  onSignOut: authSignOut,
                  onSignedOut: goLogin,
                ),
          onAddChild: (context) =>
              AppNavigation.pushNamed(context, AppRoutes.childRegister),
          onSettings: (context) =>
              AppNavigation.pushNamed(context, AppRoutes.settings),
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
        onVisibleRouteChanged: onGuardianTabChanged,
        destinations: [
          GuardianNavItem(
            icon: Icons.home_outlined,
            selectedIcon: Icons.home_rounded,
            label: '홈',
            // 대시보드 헤더의 알림 버튼도 미열람 배지를 보여주므로 홈 탭이 다시
            // 보일 때 수를 다시 센다. 셸이 IndexedStack으로 홈을 살려 두어 재진입
            // 시 initState가 돌지 않고, 푸시 등록이 실패한 기기는 푸시 수신
            // 시점의 갱신조차 오지 않는다(S15P11B209-842). 주기 폴링은 두지 않고
            // 사용자가 홈으로 돌아오는 순간만 쓴다.
            onSelected: () => unawaited(notificationBadgeController?.refresh()),
            builder: (_) => _guardianHome(
              childController,
              activityRepository,
              notificationInboxRepository,
              notificationBadgeController,
              pushRegistrationStatus,
            ),
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
                // 알림·설정 탭처럼 상단 페이지 타이틀을 둔다. 화면은
                // `embedded`를 유지해 자체 헤더·뒤로가기를 겹치지 않게 한다
                // (S15P11B209-948).
                : Scaffold(
                    backgroundColor: AppColors.canvas,
                    appBar: const AppTopBar(title: '활동 기록'),
                    body: ActivityHistoryScreen(
                      childController: childController,
                      repository: activityRepository,
                      embedded: true,
                    ),
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
            // 이 탭이 보여주는 화면은 `/guardian/notifications`가 여는 것과 같다.
            // 셸 밖의 중복 이동 판정이 "이미 알림함을 보고 있다"를 알 수 있게
            // 라우트 이름을 붙인다(S15P11B209-501). 나머지 탭은 푸시가 겨냥하는
            // 라우트가 따로 없어 비워 둔다.
            routeName: AppRoutes.notifications,
            badgeCount: notificationBadgeController,
            // 알림 탭은 IndexedStack에 살아남아 재진입해도 목록 화면이 다시
            // 만들어지지 않는다. 탭을 누를 때마다 배지를 다시 세어, 어긋난 수를
            // 사용자가 앱을 재개하지 않고도 되돌릴 수 있게 한다.
            onSelected: () => unawaited(notificationBadgeController?.refresh()),
            builder:
                notificationsTabBuilder ??
                (_) => notificationInboxRepository == null
                    ? const _TabPreparingScreen(
                        title: '알림',
                        description: '로그인 후 알림을 확인할 수 있어요.',
                      )
                    : NotificationListScreen(
                        repository: notificationInboxRepository,
                        badgeController: notificationBadgeController,
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
        ChildSelectScreen(
          controller: childController,
          imageFetcher: childRepository is ChildProfileImageRepository
              ? (childRepository as ChildProfileImageRepository)
                    .downloadProfileImage
              : null,
        ),
      ['guardian', 'children', 'register'] when childController != null =>
        ChildRegistrationScreen(
          controller: childController,
          profileImageRepository: childRepository is ChildProfileImageRepository
              ? childRepository as ChildProfileImageRepository
              : null,
        ),
      ['guardian', 'children', final childId, 'edit']
          when childController != null =>
        ChildRegistrationScreen(
          controller: childController,
          profileImageRepository: childRepository is ChildProfileImageRepository
              ? childRepository as ChildProfileImageRepository
              : null,
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
          activityRepository: activityRepository,
          fileActions: reportFileActions,
          voiceAnswerPlaybackRepository: voiceAnswerPlaybackRepository,
          voiceAnswerAudioPlayerFactory: voiceAnswerAudioPlayerFactory,
        ),
      ['guardian', 'notifications'] when notificationInboxRepository != null =>
        NotificationListScreen(
          repository: notificationInboxRepository,
          badgeController: notificationBadgeController,
        ),
      ['guardian', 'settings'] when authSignOut != null => SettingsMainScreen(
        user: authCurrentUser?.call(),
        onSignOut: authSignOut,
      ),
      ['guardian', 'settings', 'profile']
          when authLoadProfile != null && authUpdateProfile != null =>
        GuardianProfileScreen(
          initialUser: authCurrentUser?.call(),
          loadProfile: authLoadProfile,
          updateProfile: authUpdateProfile,
        ),
      ['guardian', 'settings', 'consents']
          when consentRepository != null && childController != null =>
        ConsentManagementScreen(
          repository: consentRepository,
          children: childController.children,
        ),
      // 약관 열람은 동의 현황을 보지 않으므로 아동 컨텍스트가 필요 없다.
      // 아이를 등록하지 않은 계정도 아동 대상 약관 전문을 읽을 수 있어야 한다
      // (S15P11B209-458).
      ['guardian', 'settings', 'terms'] when consentRepository != null =>
        ConsentTermsScreen(repository: consentRepository),
      // 어떤 아이가 단독 보호인지는 서버만 안다. 화면에는 연결된 아이 수만
      // 넘겨 "아이가 있는 계정 / 없는 계정" 안내를 가른다(S15P11B209-460).
      // 목록 조회가 확정되지 않았으면(`confirmedChildCount == null`) "아이가
      // 없다"고 단정하지 않는다 — 서버는 목록 조회 성공 여부와 무관하게 단독
      // 보호 아동을 삭제한다.
      ['guardian', 'settings', 'withdraw']
          when accountWithdrawalRepository != null && authSignOut != null =>
        AccountWithdrawalScreen(
          repository: accountWithdrawalRepository,
          onSignOut: authSignOut,
          connectedChildCount: childController?.confirmedChildCount,
        ),
      // 데이터 보관 기간 조회·편집. 대상 사용자는 토큰에서 해석하므로 아동
      // 컨텍스트가 필요 없다(S15P11B209-456).
      ['guardian', 'settings', 'data-retention']
          when dataRetentionRepository != null =>
        DataRetentionScreen(repository: dataRetentionRepository),
      // 알림 수신 설정 조회·편집. 대상 사용자는 토큰에서 해석한다(S15P11B209-455).
      ['guardian', 'settings', 'notifications']
          when notificationSettingsRepository != null =>
        NotificationSettingsScreen(repository: notificationSettingsRepository),
      // 커뮤니티는 웹 전용(CLAUDE.md 6절). 웹앱을 웹뷰로 띄우고 로그인 토큰을
      // localStorage에 주입한다. URL은 COMMUNITY_WEB_URL dart-define로 교체 가능.
      ['guardian', 'community'] => CommunityWebViewScreen(
        accessTokenProvider: communityAccessToken,
      ),
      // 알림이 가리키는 게시글은 같은 웹뷰를 게시글 상세 주소로 연다
      // (S15P11B209-501, 푸시 계약 §4.3의 `POST` 매핑).
      ['guardian', 'community', 'posts', final postId] =>
        CommunityWebViewScreen(
          url: communityPostUrl(postId),
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
          pendingHtpPhotoStore: pendingHtpPhotoStore,
          // 아동이 고른 캐릭터를 그 아이의 preferredCharacter로 저장해 프로필
          // 이미지에 반영한다(S15P11B209-505).
          onCharacterSelected: childController.updateChildCharacter,
          preparedResolution: settings.arguments is ChildModeHomeRouteArguments
              ? (settings.arguments! as ChildModeHomeRouteArguments)
                    .preparedResolution
              : null,
          autoStartPrepared:
              settings.arguments is ChildModeHomeRouteArguments &&
              (settings.arguments! as ChildModeHomeRouteArguments)
                  .autoStartPrepared,
        ),
      ['child', final childId, 'gallery']
          when _hasChildContext(childController, childId) &&
              activityRepository != null =>
        ChildGalleryScreen(
          child: childController!.selectedChild!,
          repository: activityRepository,
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
          initialActivityCode:
              (settings.arguments! as DrawingActivitySelectionRouteArguments)
                  .initialActivityCode,
          completionSnapshotProvider: drawingCompletionSnapshotProvider,
          htpPhotoUploadEnabled: htpPhotoUploadEnabled,
          pendingHtpPhotoStore: pendingHtpPhotoStore,
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
          existingDrawingSessionId:
              (settings.arguments! as InputMethodSelectRouteArguments)
                  .existingDrawingSessionId,
          restoredActivityContext:
              (settings.arguments! as InputMethodSelectRouteArguments)
                  .restoredActivityContext,
          htpAssessmentId:
              (settings.arguments! as InputMethodSelectRouteArguments)
                  .htpAssessmentId,
          htpPhotoUploadEnabled: htpPhotoUploadEnabled,
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
          questionSpeechSynthesizer: questionSpeechSynthesizer,
          voiceAnswerRepository: voiceAnswerRepository,
          sttResultRepository: sttResultRepository,
          activityRepository: activityRepository,
          conversationAnswerRepository: conversationAnswerRepository,
          questionSkipRepository: questionSkipRepository,
          conversationId: conversationId,
          // 사진 업로드 완료로 넘어온 분석 ID가 있으면 그것을 대화 첫 질문의
          // 기준으로 쓴다(S15P11B209-942).
          basisAnalysisId:
              (settings.arguments! as DrawingRouteArguments)
                  .conversationAnalysisId ??
              basisAnalysisId,
          resumeConversation:
              (settings.arguments! as DrawingRouteArguments).resumeConversation,
          autoRestoreDraft:
              (settings.arguments! as DrawingRouteArguments).autoRestoreDraft,
          startFresh: (settings.arguments! as DrawingRouteArguments).startFresh,
          activityContext:
              (settings.arguments! as DrawingRouteArguments).activityContext,
          inputMethod:
              (settings.arguments! as DrawingRouteArguments).inputMethod,
          companion: (settings.arguments! as DrawingRouteArguments).companion,
          childRepository: childRepository,
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
          activityRepository: activityRepository,
          inputMethod: settings.arguments is EmotionSelectRouteArguments
              ? (settings.arguments! as EmotionSelectRouteArguments).inputMethod
              : null,
          completedDrawingImage:
              settings.arguments is EmotionSelectRouteArguments
              ? (settings.arguments! as EmotionSelectRouteArguments)
                    .completedDrawingImage
              : null,
        ),
      ['child', final childId, 'activity', 'complete']
          when _hasChildContext(childController, childId) =>
        // 완료 접수 뒤의 전달 화면이라 route 인자가 없다 — 세션 식별자도, 리포지토리도
        // 필요하지 않다. 리포트 준비 소식은 보호자 알림이 전한다.
        ActivityCompleteScreen(childId: childId),
      ['child', _, ...] => const ChildContextGuardScreen(),
      ['guardian', 'home'] => const ChildContextGuardScreen(),
      ['guardian', 'children', 'select'] => const ChildContextGuardScreen(),
      ['guardian', 'children', 'register'] => const ChildContextGuardScreen(),
      ['guardian', 'children', _, 'edit'] => const ChildContextGuardScreen(),
      ['guardian', 'reports'] => const ChildContextGuardScreen(),
      _ => UnknownRouteScreen(location: location),
    };

    if (_isDrawingRoute(segments)) {
      return MaterialPageRoute<DrawingRouteResult>(
        settings: settings,
        builder: (_) => screen,
      );
    }
    // 사진 입력 화면은 다음에 열 세션을 pop으로 돌려준다. 호출부가 그 결과로
    // 대화·캔버스를 결정하므로 라우트 타입을 맞춰 둔다(S15P11B209-834).
    if (_isInputMethodRoute(segments)) {
      return MaterialPageRoute<DrawingSessionResolution>(
        settings: settings,
        builder: (_) => screen,
      );
    }
    return MaterialPageRoute<void>(settings: settings, builder: (_) => screen);
  }

  static Widget _guardianHome(
    GuardianChildController controller,
    ActivityRepository? activityRepository,
    NotificationInboxRepository? notificationInboxRepository,
    NotificationBadgeController? notificationBadgeController,
    PushRegistrationStatusController? pushRegistrationStatus,
  ) => GuardianHomeScreen(
    controller: controller,
    activityRepository: activityRepository,
    notificationInboxRepository: notificationInboxRepository,
    notificationBadgeController: notificationBadgeController,
    pushRegistrationStatus: pushRegistrationStatus,
  );

  static bool _isGuardianHomeRoute(List<String> segments) => switch (segments) {
    ['guardian', 'home'] => true,
    _ => false,
  };

  /// gate를 세울지 판정한다.
  ///
  /// rollout flag가 꺼져 있거나 PIN 경계를 주입받지 못했으면 gate를 세우지
  /// 않는다. 반대로 켜져 있는데 서버가 `PIN_UNAVAILABLE`을 돌려주는 상황은 gate
  /// 안에서 오류로 보여 준다 — 여기서 열어 주면 보안 장치가 서버 장애에 맞춰
  /// 사라진다.
  static bool _guardianPinGateRequired({
    required bool enabled,
    required GuardianPinRepository? repository,
    required GuardianUnlockController? unlock,
  }) => enabled && repository != null && unlock != null && !unlock.isUnlocked;

  static bool _hasChildContext(
    GuardianChildController? controller,
    String childId,
  ) {
    final parsedId = int.tryParse(childId);
    return parsedId != null && controller?.hasSelectedChild(parsedId) == true;
  }

  static bool _isInputMethodRoute(List<String> segments) => switch (segments) {
    ['child', _, 'activity', 'input-method'] => true,
    _ => false,
  };

  static bool _isDrawingRoute(List<String> segments) => switch (segments) {
    ['child', _, 'activity', 'drawing'] => true,
    _ => false,
  };

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
    this.existingDrawingSessionId,
    this.restoredActivityContext,
    this.htpAssessmentId,
  });

  final int childId;
  final int drawingTypeId;
  final String title;
  final String description;
  final IconData icon;
  final Color accentColor;
  final DrawingRepository repository;

  /// 이미 만들어진 `UPLOAD` 세션을 그대로 이어 사진만 올릴 때 넘긴다.
  ///
  /// 값이 있으면 화면이 새 세션을 만들지 않고 이 세션으로 업로드·완료한다.
  final int? existingDrawingSessionId;

  /// 복원 모드에서 서버 재조회 없이 쓰는 `activityContext`.
  final DrawingActivityContextDto? restoredActivityContext;

  /// 다음 HTP 주제 세션을 이 화면에서 만들어야 할 때 넘긴다.
  final int? htpAssessmentId;
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
    this.conversationAnalysisId,
    this.companion = DodamCostume.base,
  });

  final int sessionId;
  final DrawingRepository repository;
  final Future<BinaryUploadDto?> Function()? completionSnapshotProvider;

  /// 이 세션이 실제로 쓰는 입력 방식(`CANVAS`|`UPLOAD`).
  final String? inputMethod;

  /// 활동 시작 시 서버 확정 `preferredCharacter`에서 만든 immutable snapshot.
  final DodamCostume companion;

  /// 그림 단계를 지난 세션으로 들어올 때 대화를 즉시 이어받게 한다.
  final bool resumeConversation;

  /// 진입 전 이어 그리기를 확인한 경우 캔버스에서 같은 선택을 다시 묻지 않는다.
  final bool autoRestoreDraft;

  /// 주제 선택 뒤 생성한 새 활동은 Draft 확인 없이 빈 캔버스를 연다.
  final bool startFresh;
  final DrawingActivityContextDto activityContext;

  /// 사진 업로드로 막 완료된 세션의 분석 ID(대화 첫 질문 생성 기준,
  /// S15P11B209-942). 재개 등 그 외 진입에서는 `null`.
  final int? conversationAnalysisId;
}

/// 캔버스가 상위 활동 진입 화면에 전달하는 종료 결과.
final class DrawingRouteResult {
  /// 완료 화면 이동이 아니라 사용자가 뒤로가기로 캔버스를 나간 경우.
  const DrawingRouteResult.backToActivityEntry() : nextResolution = null;

  /// HTP 다음 주제 세션이 만들어져 상위 진입 화면이 열어야 하는 경우.
  ///
  /// 어떤 화면을 열지는 상위 진입 화면이 [DrawingSessionResolution.target]으로
  /// 한 번에 판정한다. 캔버스가 직접 사진 화면을 열면 그 결과를 기다리는 곳이
  /// 없어 업로드 이후 흐름이 끊긴다(S15P11B209-834).
  const DrawingRouteResult.advanceTo(DrawingSessionResolution resolution)
    : nextResolution = resolution;

  /// 다음으로 열어야 하는 세션. 뒤로가기로 나온 경우 `null`.
  final DrawingSessionResolution? nextResolution;
}

final class DrawingActivitySelectionRouteArguments {
  const DrawingActivitySelectionRouteArguments({
    this.replaceActive = false,
    this.initialActivityCode,
  });

  final bool replaceActive;

  /// 값이 있으면 활동 카드 선택을 생략하고 해당 활동의 시작 화면을 연다.
  final String? initialActivityCode;
}

/// 보호자가 정한 활동을 아동 홈까지 전달하고, 실제 캔버스 진입은 아동이 한다.
///
/// [autoStartPrepared]가 참이면 아동 홈을 거치지 않고 곧바로 캔버스를 연다.
/// 이어 그리기처럼 이미 진행 중인 그림을 다시 여는 경우에 사용한다.
final class ChildModeHomeRouteArguments {
  const ChildModeHomeRouteArguments({
    required this.preparedResolution,
    this.autoStartPrepared = false,
  });

  final DrawingSessionResolution preparedResolution;
  final bool autoStartPrepared;
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
