import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/router/app_routes.dart';
import 'core/network/network.dart';
import 'features/auth/auth.dart';
import 'features/drawing/data/repositories/mock_drawing_repository.dart';
import 'features/drawing/data/repositories/remote_drawing_repository.dart';
import 'features/conversation/conversation.dart';

void main() {
  runApp(createDefaultApp());
}

/// Creates the normal app runtime with the public API-backed Drawing flow.
///
/// Tests and explicit mock entry points can continue constructing [DodamApp]
/// with a [MockDrawingRepository] through its existing constructor injection.
DodamApp createDefaultApp({
  ApiEnvironment? environment,
  AuthSessionStore? authSessionStore,
}) {
  final authRepository = AuthRepositoryImpl(
    providerScenarios: const {
      AuthProvider.kakao: MockAuthScenario.newUserWithoutEmail,
      AuthProvider.google: MockAuthScenario.newGuardian,
      AuthProvider.naver: MockAuthScenario.newGuardian,
    },
    sessionStore: authSessionStore ?? SecureAuthSessionStore(),
  );
  final apiClient = ApiClient(
    environment: environment ?? ApiEnvironment.fromDartDefine(),
    accessTokenProvider: authRepository,
    tokenRefresher: authRepository,
  );
  const useMockDrawing = bool.fromEnvironment(
    'USE_MOCK_DRAWING',
    defaultValue: false,
  );

  return DodamApp(
    authRepository: authRepository,
    // 백엔드 미연결 개발 환경에서만 목 그림 세션 사용
    drawingRepository: useMockDrawing
        ? const MockDrawingRepository()
        : RemoteDrawingRepository(apiClient),
    voiceAnswerRepository: RemoteVoiceAnswerRepository(apiClient),
    initialRoute: AppRoutes.authBootstrap,
  );
}
