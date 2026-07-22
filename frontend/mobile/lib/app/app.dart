import 'package:flutter/material.dart';

import '../design_system/design_system.dart';
import '../features/auth/auth.dart';
import '../features/child/data/repositories/mock_child_repository.dart';
import '../features/child/domain/repositories/child_repository.dart';
import 'router/app_router.dart';
import 'router/app_routes.dart';
import 'state/guardian_child_controller.dart';

class DodamApp extends StatefulWidget {
  const DodamApp({
    this.childRepository = const MockChildRepository(),
    this.initialRoute = AppRoutes.guardianHome,
    super.key,
  });

  final ChildRepository childRepository;
  final String initialRoute;

  @override
  State<DodamApp> createState() => _DodamAppState();
}

class _DodamAppState extends State<DodamApp> {
  late final GuardianChildController _childController;
  late final SocialLoginService _socialLoginService;
  late final KakaoLoginCoordinator _kakaoLoginCoordinator;
  late final GoogleLoginCoordinator _googleLoginCoordinator;
  late final NaverLoginCoordinator _naverLoginCoordinator;

  @override
  void initState() {
    super.initState();
    _childController = GuardianChildController(widget.childRepository);
    _childController.loadChildren();

    final authRepository = AuthRepositoryImpl();
    _socialLoginService = SocialLoginService(authRepository);
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
    ),
  );
}
