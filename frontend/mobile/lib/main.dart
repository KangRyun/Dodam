import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/router/app_routes.dart';
import 'core/network/network.dart';
import 'features/auth/auth.dart';
import 'features/child/data/repositories/remote_child_repository.dart';
import 'features/conversation/data/repositories/remote_conversation_repository.dart';
import 'features/drawing/data/repositories/remote_drawing_repository.dart';

void main() {
  runApp(createDefaultApp());
}

/// Creates the normal app runtime with public API-backed repositories
/// (child, conversation, drawing).
///
/// Activity and report stay on mock repositories until their backend APIs
/// exist (S15P11B209-384 contract check, 2026-07-24). Tests and explicit mock
/// entry points can continue constructing [DodamApp] with mock repositories
/// through its existing constructor injection.
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
    childRepository: RemoteChildRepository(apiClient),
    conversationRepository: RemoteConversationRepository(apiClient),
    drawingRepository: RemoteDrawingRepository(apiClient),
    initialRoute: AppRoutes.authBootstrap,
  );
}
