import 'package:flutter/material.dart';

import '../design_system/design_system.dart';
import '../features/auth/auth.dart';
import '../features/activity/data/repositories/mock_activity_repository.dart';
import '../features/activity/domain/repositories/activity_repository.dart';
import '../features/child/data/repositories/mock_child_repository.dart';
import '../features/child/domain/repositories/child_repository.dart';
import '../features/drawing/data/dto/drawing_dtos.dart';
import '../features/drawing/data/repositories/mock_drawing_repository.dart';
import '../features/drawing/domain/repositories/drawing_repository.dart';
import '../features/conversation/conversation.dart';
import '../features/report/data/repositories/mock_report_repository.dart';
import '../features/report/domain/repositories/report_repository.dart';
import 'router/app_router.dart';
import 'router/app_routes.dart';
import 'state/guardian_child_controller.dart';

class DodamApp extends StatefulWidget {
  const DodamApp({
    this.activityRepository = const MockActivityRepository(),
    this.childRepository = const MockChildRepository(),
    this.drawingRepository = const MockDrawingRepository(),
    this.reportRepository = const MockReportRepository(),
    this.drawingCompletionSnapshotProvider,
    this.authSessionStore,
    this.authRepository,
    this.conversationRepository = const MockConversationRepository(),
    this.conversationId = 8001,
    this.basisAnalysisId = 7001,
    this.initialRoute = AppRoutes.guardianHome,
    super.key,
  });

  final ActivityRepository activityRepository;
  final ChildRepository childRepository;
  final DrawingRepository drawingRepository;
  final ReportRepository reportRepository;
  final Future<BinaryUploadDto?> Function()? drawingCompletionSnapshotProvider;
  final AuthSessionStore? authSessionStore;
  final AuthRepositoryImpl? authRepository;
  final ConversationRepository? conversationRepository;
  final int? conversationId;
  final int? basisAnalysisId;
  final String initialRoute;

  @override
  State<DodamApp> createState() => _DodamAppState();
}

class _DodamAppState extends State<DodamApp> {
  late final GuardianChildController _childController;
  late final AuthRepositoryImpl _authRepository;
  late final SocialLoginService _socialLoginService;
  late final KakaoLoginCoordinator _kakaoLoginCoordinator;
  late final GoogleLoginCoordinator _googleLoginCoordinator;
  late final NaverLoginCoordinator _naverLoginCoordinator;

  @override
  void initState() {
    super.initState();
    _childController = GuardianChildController(widget.childRepository);
    _childController.loadChildren();

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
    _kakaoLoginCoordinator = KakaoLoginCoordinator(
      KakaoLoginClientImpl(),
      _socialLoginService,
    );
    _googleLoginCoordinator = GoogleLoginCoordinator(
      GoogleLoginClientImpl(),
      _socialLoginService,
    );
    _naverLoginCoordinator = NaverLoginCoordinator(
      NaverLoginClientImpl(),
      _socialLoginService,
    );
  }

  // Provider별 로그인 실행
  Future<AuthState> _signIn(AuthProvider provider) => switch (provider) {
    AuthProvider.kakao => _kakaoLoginCoordinator.signIn(),
    AuthProvider.google => _googleLoginCoordinator.signIn(),
    AuthProvider.naver => _naverLoginCoordinator.signIn(),
  };

  Future<AuthSession> _completeOnboarding(NewUserOnboardingInput input) =>
      _authRepository.completeOnboarding(input);

  // 저장 세션 복원 및 만료된 Access Token 갱신
  Future<AuthSession?> _restoreSession() async {
    var session = await _authRepository.restoreSession();
    if (session == null) return null;
    if (!session.tokens.isAccessTokenExpired()) return session;

    final refreshed = await _authRepository.refreshAccessToken();
    if (!refreshed) return null;
    session = await _authRepository.restoreSession();
    return session;
  }

  // 인증 세션과 보호자 선택 상태 초기화
  Future<void> _signOut() async {
    await _authRepository.signOut();
    _childController.clearSelection();
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
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.leaf,
        surface: AppColors.surface,
      ),
      scaffoldBackgroundColor: AppColors.canvas,
    ),
    initialRoute: widget.initialRoute,
    onGenerateRoute: (settings) => AppRouter.onGenerateRoute(
      settings,
      childController: _childController,
      authSignIn: _signIn,
      authCompleteOnboarding: _completeOnboarding,
      authSignOut: _signOut,
      authRestoreSession: _restoreSession,
      activityRepository: widget.activityRepository,
      drawingRepository: widget.drawingRepository,
      reportRepository: widget.reportRepository,
      drawingCompletionSnapshotProvider:
          widget.drawingCompletionSnapshotProvider,
      conversationRepository: widget.conversationRepository,
      conversationId: widget.conversationId,
      basisAnalysisId: widget.basisAnalysisId,
    ),
  );
}
