import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';

import '../core/network/auth/access_token_provider.dart';
import '../core/network/auth/token_refresher.dart';
import '../design_system/design_system.dart';
import '../features/auth/auth.dart';
import '../features/activity/data/repositories/mock_activity_repository.dart';
import '../features/activity/domain/repositories/activity_repository.dart';
import '../features/child/data/repositories/mock_child_consent_repository.dart';
import '../features/child/data/repositories/mock_child_repository.dart';
import '../features/child/domain/repositories/child_consent_repository.dart';
import '../features/child/domain/repositories/child_repository.dart';
import '../features/consent/data/repositories/mock_consent_repository.dart';
import '../features/consent/domain/repositories/consent_repository.dart';
import '../features/drawing/data/dto/drawing_dtos.dart';
import '../features/drawing/data/repositories/mock_drawing_repository.dart';
import '../features/drawing/domain/repositories/drawing_repository.dart';
import '../features/conversation/conversation.dart';
import '../features/notification/application/notification_badge_controller.dart';
import '../features/notification/application/push_registration_status_controller.dart';
import '../features/notification/domain/entities/push_message.dart';
import '../features/notification/domain/failures/push_token_registration_failure.dart';
import '../features/notification/domain/repositories/notification_inbox_repository.dart';
import '../features/notification/domain/services/push_coordinator.dart';
import '../features/notification/domain/services/push_setup.dart';
import '../features/report/data/repositories/mock_report_repository.dart';
import '../features/report/data/services/platform_report_file_actions.dart';
import '../features/report/domain/repositories/report_repository.dart';
import '../features/report/domain/services/report_file_actions.dart';
import '../features/settings/data/repositories/mock_account_withdrawal_repository.dart';
import '../features/settings/data/repositories/mock_data_retention_repository.dart';
import '../features/settings/domain/repositories/account_withdrawal_repository.dart';
import '../features/settings/domain/repositories/data_retention_repository.dart';
import '../features/settings/domain/repositories/guardian_profile_repository.dart';
import 'router/app_navigation.dart';
import 'router/app_router.dart';
import 'router/app_routes.dart';
import 'router/current_route_observer.dart';
import 'router/notification_route_resolver.dart';
import 'state/guardian_child_controller.dart';

class DodamApp extends StatefulWidget {
  const DodamApp({
    this.activityRepository = const MockActivityRepository(),
    this.childRepository = const MockChildRepository(),
    this.childConsentRepository = const MockChildConsentRepository(),
    this.consentRepository = const MockConsentRepository(),
    this.accountWithdrawalRepository = const MockAccountWithdrawalRepository(),
    this.dataRetentionRepository = const MockDataRetentionRepository(),
    this.drawingRepository = const MockDrawingRepository(),
    this.reportRepository = const MockReportRepository(),
    this.reportFileActions = const PlatformReportFileActions(),
    this.drawingCompletionSnapshotProvider,
    this.authSessionStore,
    this.authRepository,
    this.conversationRepository = const MockConversationRepository(),
    this.conversationEndRepository = const MockConversationEndRepository(),
    this.questionTtsRepository,
    this.questionAudioPlayerFactory,
    this.voiceAnswerPlaybackRepository,
    this.voiceAnswerAudioPlayerFactory,
    this.voiceAnswerRepository,
    this.sttResultRepository,
    this.conversationAnswerRepository,
    this.questionSkipRepository,
    this.conversationId,
    this.basisAnalysisId,
    this.pushSetup,
    this.notificationInboxRepository,
    this.htpPhotoUploadEnabled = false,
    this.initialRoute = AppRoutes.guardianHome,
    super.key,
  });

  final ActivityRepository activityRepository;
  final ChildRepository childRepository;

  /// 아동 대상 약관 조회·동의 기록 경계. 실 연동 시 원격 구현을 주입한다.
  final ChildConsentRepository childConsentRepository;
  final ConsentRepository consentRepository;

  /// USER-05 회원 탈퇴 경계. 실 연동 시 원격 구현을 주입한다.
  final AccountWithdrawalRepository accountWithdrawalRepository;

  /// 데이터 보관 기간 조회·편집 경계(S15P11B209-456). 실 연동 시 원격 구현을 주입한다.
  final DataRetentionRepository dataRetentionRepository;
  final DrawingRepository drawingRepository;
  final ReportRepository reportRepository;
  final ReportFileActions reportFileActions;
  final Future<BinaryUploadDto?> Function()? drawingCompletionSnapshotProvider;
  final AuthSessionStore? authSessionStore;
  final AuthRepository? authRepository;
  final ConversationRepository? conversationRepository;
  final ConversationEndRepository? conversationEndRepository;
  final QuestionTtsRepository? questionTtsRepository;
  final QuestionAudioPlayerFactory? questionAudioPlayerFactory;
  final VoiceAnswerPlaybackRepository? voiceAnswerPlaybackRepository;
  final VoiceAnswerAudioPlayerFactory? voiceAnswerAudioPlayerFactory;
  final VoiceAnswerRepository? voiceAnswerRepository;
  final SttResultRepository? sttResultRepository;
  final ConversationAnswerRepository? conversationAnswerRepository;

  /// 질문 건너뛰기 기록 경계. 주지 않으면 화면이 Mock으로 폴백한다.
  final QuestionSkipRepository? questionSkipRepository;
  final int? conversationId;
  final int? basisAnalysisId;

  /// 푸시 구성 요소다. 주지 않으면 푸시 기능이 꺼진 채로 동작한다.
  final PushSetup? pushSetup;
  final NotificationInboxRepository? notificationInboxRepository;

  /// HTP 사진으로 시작하기 옵션 노출 여부(S15P11B209-702, 기본 꺼짐).
  final bool htpPhotoUploadEnabled;
  final String initialRoute;

  @override
  State<DodamApp> createState() => _DodamAppState();
}

class _DodamAppState extends State<DodamApp> with WidgetsBindingObserver {
  late final GuardianChildController _childController;
  late final AuthRepository _authRepository;
  late final SocialLoginService _socialLoginService;
  late final KakaoLoginClient _kakaoLoginClient;
  late final GoogleLoginClient _googleLoginClient;
  late final NaverLoginClient _naverLoginClient;
  late final KakaoLoginCoordinator _kakaoLoginCoordinator;
  late final GoogleLoginCoordinator _googleLoginCoordinator;
  late final NaverLoginCoordinator _naverLoginCoordinator;
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _routeObserver = CurrentRouteObserver();
  PushCoordinator? _pushCoordinator;
  NotificationBadgeController? _notificationBadgeController;

  /// 디바이스 Token 등록이 거절돼 이 계정이 푸시를 받지 못하는 상태인지.
  /// 보호자 화면이 구독해 안내를 띄운다.
  final _pushRegistrationStatus = PushRegistrationStatusController();
  AuthSession? _currentSession;

  /// 보호자 셸이 지금 보여주는 탭의 라우트 이름. 셸이 알려 준다.
  String? _guardianTabRoute;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _childController = GuardianChildController(
      widget.childRepository,
      widget.childConsentRepository,
    );
    final inboxRepository = widget.notificationInboxRepository;
    if (inboxRepository != null) {
      _notificationBadgeController = NotificationBadgeController(
        inboxRepository,
      );
    }
    if (widget.initialRoute != AppRoutes.authBootstrap) {
      _childController.loadChildren();
      // 인증 부트스트랩을 거치지 않는 구성(데모·직접 진입)은 여기가 앱 진입이다.
      _refreshNotificationBadge();
    }

    _authRepository =
        widget.authRepository ??
        AuthRepositoryImpl(
          providerScenarios: const {
            AuthProvider.kakao: MockAuthScenario.newUserWithoutEmail,
            AuthProvider.google: MockAuthScenario.newGuardian,
            AuthProvider.naver: MockAuthScenario.newGuardian,
          },
          sessionStore: widget.authSessionStore,
        );
    _socialLoginService = SocialLoginService(_authRepository);
    final usesRemoteAuth = _authRepository is RemoteAuthRepository;
    _kakaoLoginClient = usesRemoteAuth
        ? KakaoSdkLoginClient()
        : KakaoLoginClientImpl();
    _googleLoginClient = usesRemoteAuth
        ? GoogleSdkLoginClient()
        : GoogleLoginClientImpl();
    _naverLoginClient = usesRemoteAuth
        ? NaverSdkLoginClient()
        : NaverLoginClientImpl();
    _kakaoLoginCoordinator = KakaoLoginCoordinator(
      _kakaoLoginClient,
      _socialLoginService,
    );
    _googleLoginCoordinator = GoogleLoginCoordinator(
      _googleLoginClient,
      _socialLoginService,
    );
    _naverLoginCoordinator = NaverLoginCoordinator(
      _naverLoginClient,
      _socialLoginService,
    );
    _pushCoordinator = widget.pushSetup?.createCoordinator(
      onOpen: _openPushTarget,
      isChildModeActive: () => _routeObserver.isChildModeActive,
      isGuardianSessionActive: () => _hasGuardianSession,
      onInboxChanged: _refreshNotificationBadge,
      onTokenRegistrationResult: _handlePushTokenRegistrationResult,
    );
  }

  void _refreshNotificationBadge() {
    unawaited(_notificationBadgeController?.refresh());
  }

  /// 디바이스 Token 등록 결과를 보호자 화면에 전달한다.
  ///
  /// 등록이 거절된 계정에는 서버가 푸시를 보내지 않는다. 푸시 수신에 기대던 배지
  /// 갱신이 아예 오지 않으므로, 실패를 알게 된 지금 한 번 서버 값을 읽어 배지가
  /// 0에서 멈춰 있지 않게 한다. 주기 폴링은 두지 않는다(배터리·트래픽) —
  /// 나머지는 홈·알림 탭 재진입과 알림 팝업 열기가 담당한다(S15P11B209-842).
  void _handlePushTokenRegistrationResult(
    PushTokenRegistrationFailure? failure,
  ) {
    _pushRegistrationStatus.report(failure);
    if (failure != null) _refreshNotificationBadge();
  }

  /// 포그라운드로 돌아오면 미열람 수를 다시 센다. 백그라운드에서 받은 푸시는
  /// 앱이 떠 있을 때의 수신 스트림을 타지 않아 배지가 뒤처진다.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    _refreshNotificationBadge();
  }

  /// 푸시가 가리키는 화면을 열어도 되는 세션인지.
  ///
  /// [_onGuardianSessionReady]가 푸시를 켤 때 쓴 조건과 같다. 켤 때만 보고 끌 때를
  /// 보지 않으면 세션이 끝난 뒤 도착한 탭이 그대로 이동한다. 판정은 코디네이터가
  /// 아동 모드 게이트와 같은 자리에서 하고(`push_coordinator.dart`), 세션 상태는
  /// 앱 계층만 알 수 있어 여기서 넘긴다.
  bool get _hasGuardianSession {
    final session = _currentSession;
    return session != null &&
        !session.requiresOnboarding &&
        session.user.role == UserRole.guardian;
  }

  /// 푸시가 가리키는 화면으로 이동한다.
  ///
  /// 연결 자원이 없으면 알림함 목록으로 보낸다(계약 §4.3). 알림함 카드 클릭과
  /// 같은 매핑 함수를 쓰고, 이동도 같은 진입점을 지난다(S15P11B209-501).
  ///
  /// `Navigator`를 직접 부르면 이미 보고 있는 화면이 한 장 더 쌓인다 — 연결
  /// 자원이 없는 푸시를 알림함에서 누르는 경우가 그렇다. 카드 탭 쪽은 같은
  /// 상황에서 이동하지 않으므로, 판정기를 공유해 두 경로를 맞춘다.
  ///
  /// 세션 없이 도착한 탭은 여기까지 오지 않는다 — 코디네이터가 아동 모드 게이트
  /// 옆에서 [_hasGuardianSession]으로 먼저 걸러낸다.
  void _openPushTarget(PushMessage message) {
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;

    AppNavigation.pushNamedOn(
      navigator,
      resolvePushRoute(message),
      currentRouteName: _visibleRouteName,
    );
  }

  /// 중복 이동 판정이 "지금 보고 있는 화면"으로 삼을 라우트.
  ///
  /// 보호자 셸은 탭을 바꿔도 라우트를 쌓지 않아 관찰자에게는 늘
  /// `/guardian/home`이다. 그래서 알림 탭을 보는 중에 연결 자원 없는 푸시가 오면
  /// 이미 보고 있는 알림함이 한 장 더 쌓였다(S15P11B209-501). 셸이 알려 준 탭
  /// 라우트를 그 자리에 대신 넣어 두 경로의 판정을 맞춘다.
  ///
  /// 셸 위에 다른 화면이 올라가 있으면 그 화면이 "지금 화면"이 맞으므로, 셸이
  /// 최상단일 때만 바꿔치기한다.
  String? get _visibleRouteName {
    final current = _routeObserver.currentRouteName;
    if (current != AppRoutes.guardianHome) return current;
    return _guardianTabRoute ?? current;
  }

  // Provider별 로그인 실행
  Future<AuthState> _signIn(AuthProvider provider) async {
    final state = await switch (provider) {
      AuthProvider.kakao => _kakaoLoginCoordinator.signIn(),
      AuthProvider.google => _googleLoginCoordinator.signIn(),
      AuthProvider.naver => _naverLoginCoordinator.signIn(),
    };
    _currentSession = state.session;
    await _onGuardianSessionReady(state.session);
    return state;
  }

  Future<AuthSession> _completeOnboarding(NewUserOnboardingInput input) async {
    final session = await _authRepository.completeOnboarding(input);
    _currentSession = session;
    await _onGuardianSessionReady(session);
    return session;
  }

  // 저장 세션 복원 및 만료된 Access Token 갱신
  Future<AuthSession?> _restoreSession() async {
    var session = await _authRepository.restoreSession();
    if (session == null) {
      _currentSession = null;
      return null;
    }
    if (session.tokens.isAccessTokenExpired()) {
      final repository = _authRepository;
      if (repository is! TokenRefresher) {
        _currentSession = null;
        return null;
      }
      final refreshed = await (repository as TokenRefresher)
          .refreshAccessToken();
      if (!refreshed) {
        _currentSession = null;
        return null;
      }
      session = await _authRepository.restoreSession();
    }
    _currentSession = session;
    await _onGuardianSessionReady(session);
    return session;
  }

  /// 보호자 세션이 확정된 뒤에 필요한 준비를 모은다.
  ///
  /// 푸시 Token 등록은 로그인 이후여야 한다. 세션 없이 등록하면 서버가 어느
  /// 사용자의 기기인지 알 수 없다.
  Future<void> _onGuardianSessionReady(AuthSession? session) async {
    if (session == null ||
        session.requiresOnboarding ||
        session.user.role != UserRole.guardian) {
      developer.log(
        '보호자 세션 아님 — 푸시 시작 안 함 '
        '(session=${session != null}, onboarding=${session?.requiresOnboarding}, '
        'role=${session?.user.role?.name})',
        name: 'push',
      );
      return;
    }
    await _childController.loadChildren();
    // 보호자 세션이 확정된 뒤라야 알림함 조회에 토큰이 실린다.
    _refreshNotificationBadge();

    if (_pushCoordinator == null) {
      developer.log('pushSetup 미주입 — 푸시 비활성', name: 'push');
      return;
    }
    await _pushCoordinator?.start();
  }

  // 인증 세션과 보호자 선택 상태 초기화
  Future<void> _signOut() async {
    final provider = _currentSession?.user.provider;
    // 아래 정리에는 await가 여럿이고 그 사이에도 푸시 탭이 들어온다. 세션 표시를
    // 먼저 내려야 정리 도중 도착한 탭이 이동으로 이어지지 않는다. Token 해제
    // API의 인증은 저장소에 남은 토큰이 담당하므로(바로 아래 signOut이 지운다)
    // 이 참조를 먼저 비워도 해제 호출에는 영향이 없다.
    _currentSession = null;
    await _pushCoordinator?.stop();
    await _authRepository.signOut();
    try {
      switch (provider) {
        case AuthProvider.kakao:
          await _kakaoLoginClient.signOut();
        case AuthProvider.google:
          await _googleLoginClient.signOut();
        case AuthProvider.naver:
          await _naverLoginClient.signOut();
        case null:
          break;
      }
    } on Object {
      // 서비스 세션은 이미 제거했으므로 Provider 로그아웃 실패로 되돌리지 않는다.
    }
    _childController.clear();
    _notificationBadgeController?.clear();
    // 등록 상태는 직전 계정의 것이다. 다음 로그인이 다시 판정한다.
    _pushRegistrationStatus.clear();
  }

  Future<AuthenticatedUser> _loadProfile() async {
    final repository = _authRepository;
    if (repository is! GuardianProfileRepository) return _currentSession!.user;
    final user = await (repository as GuardianProfileRepository)
        .getCurrentUserProfile();
    final session = _currentSession;
    if (session != null && mounted) {
      setState(() => _currentSession = session.copyWith(user: user));
    }
    return user;
  }

  Future<AuthenticatedUser> _updateProfile(String nickname) async {
    final repository = _authRepository;
    if (repository is! GuardianProfileRepository) {
      throw StateError('보호자 프로필 수정 기능을 사용할 수 없습니다.');
    }
    final user = await (repository as GuardianProfileRepository)
        .updateCurrentUserProfile(nickname: nickname);
    final session = _currentSession;
    if (session != null && mounted) {
      setState(() => _currentSession = session.copyWith(user: user));
    }
    return user;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notificationBadgeController?.dispose();
    _pushRegistrationStatus.dispose();
    _childController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '도담',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      fontFamily: AppFontFamily.body,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.leaf,
        surface: AppColors.surface,
      ),
      scaffoldBackgroundColor: AppColors.canvas,
    ),
    navigatorKey: _navigatorKey,
    navigatorObservers: [_routeObserver],
    initialRoute: widget.initialRoute,
    onGenerateRoute: (settings) => AppRouter.onGenerateRoute(
      settings,
      childController: _childController,
      childRepository: widget.childRepository,
      authSignIn: _signIn,
      authCompleteOnboarding: _completeOnboarding,
      authSignOut: _signOut,
      authRestoreSession: _restoreSession,
      authCurrentUser: () => _currentSession?.user,
      authLoadProfile: _loadProfile,
      authUpdateProfile: _updateProfile,
      // 커뮤니티 웹뷰에 주입할 로그인 토큰. 원격 인증일 때만 값이 있고,
      // Mock 인증에서는 null이라 토큰 없이 웹앱을 로드한다.
      communityAccessToken: () async {
        final repository = _authRepository;
        if (repository is AccessTokenProvider) {
          return (repository as AccessTokenProvider).readAccessToken();
        }
        return null;
      },
      activityRepository: widget.activityRepository,
      drawingRepository: widget.drawingRepository,
      reportRepository: widget.reportRepository,
      reportFileActions: widget.reportFileActions,
      notificationInboxRepository: widget.notificationInboxRepository,
      notificationBadgeController: _notificationBadgeController,
      pushRegistrationStatus: _pushRegistrationStatus,
      onGuardianTabChanged: (routeName) => _guardianTabRoute = routeName,
      consentRepository: widget.consentRepository,
      accountWithdrawalRepository: widget.accountWithdrawalRepository,
      dataRetentionRepository: widget.dataRetentionRepository,
      drawingCompletionSnapshotProvider:
          widget.drawingCompletionSnapshotProvider,
      conversationRepository: widget.conversationRepository,
      conversationEndRepository: widget.conversationEndRepository,
      questionTtsRepository: widget.questionTtsRepository,
      questionAudioPlayerFactory: widget.questionAudioPlayerFactory,
      voiceAnswerPlaybackRepository: widget.voiceAnswerPlaybackRepository,
      voiceAnswerAudioPlayerFactory: widget.voiceAnswerAudioPlayerFactory,
      voiceAnswerRepository: widget.voiceAnswerRepository,
      sttResultRepository: widget.sttResultRepository,
      conversationAnswerRepository: widget.conversationAnswerRepository,
      questionSkipRepository: widget.questionSkipRepository,
      conversationId: widget.conversationId,
      basisAnalysisId: widget.basisAnalysisId,
      htpPhotoUploadEnabled: widget.htpPhotoUploadEnabled,
    ),
  );
}
