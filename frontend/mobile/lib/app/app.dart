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
import '../features/notification/domain/entities/push_message.dart';
import '../features/notification/domain/repositories/notification_inbox_repository.dart';
import '../features/notification/domain/services/push_coordinator.dart';
import '../features/notification/domain/services/push_setup.dart';
import '../features/report/data/repositories/mock_report_repository.dart';
import '../features/report/data/services/platform_report_file_actions.dart';
import '../features/report/domain/repositories/report_repository.dart';
import '../features/report/domain/services/report_file_actions.dart';
import 'router/app_router.dart';
import 'router/app_routes.dart';
import 'router/current_route_observer.dart';
import 'router/push_route_resolver.dart';
import 'state/guardian_child_controller.dart';

class DodamApp extends StatefulWidget {
  const DodamApp({
    this.activityRepository = const MockActivityRepository(),
    this.childRepository = const MockChildRepository(),
    this.childConsentRepository = const MockChildConsentRepository(),
    this.consentRepository = const MockConsentRepository(),
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

class _DodamAppState extends State<DodamApp> {
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
  AuthSession? _currentSession;

  @override
  void initState() {
    super.initState();
    _childController = GuardianChildController(
      widget.childRepository,
      widget.childConsentRepository,
    );
    if (widget.initialRoute != AppRoutes.authBootstrap) {
      _childController.loadChildren();
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
    );
  }

  /// 푸시가 가리키는 화면으로 이동한다.
  ///
  /// 대응 화면이 없으면 아무 데도 보내지 않는다. 서버가 준 자원과 무관한 화면을
  /// 여는 것보다 앱만 열린 채 두는 편이 낫다(계약 §4.3). 알림함 화면
  /// (S15P11B209-499)이 붙으면 그쪽으로 보낸다.
  void _openPushTarget(PushMessage message) {
    final route = resolvePushRoute(message);
    if (route == null) return;

    _navigatorKey.currentState?.pushNamed(route);
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

    if (_pushCoordinator == null) {
      developer.log('pushSetup 미주입 — 푸시 비활성', name: 'push');
      return;
    }
    await _pushCoordinator?.start();
  }

  // 인증 세션과 보호자 선택 상태 초기화
  Future<void> _signOut() async {
    final provider = _currentSession?.user.provider;
    // Token 해제 API는 인증이 필요하므로 세션을 지우기 전에 부른다.
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
    _currentSession = null;
    _childController.clear();
  }

  @override
  void dispose() {
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
      consentRepository: widget.consentRepository,
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
