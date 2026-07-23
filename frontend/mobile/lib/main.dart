import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/router/app_routes.dart';
import 'core/network/network.dart';
import 'features/auth/auth.dart';
import 'features/drawing/data/repositories/remote_drawing_repository.dart';

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

  return DodamApp(
    authRepository: authRepository,
    drawingRepository: RemoteDrawingRepository(apiClient),
    initialRoute: AppRoutes.authBootstrap,
  );
}
