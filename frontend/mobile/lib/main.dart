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

/// 공개 API와 Provider SDK를 사용하는 기본 애플리케이션 구성을 생성한다.
///
/// child·conversation(다음질문)·drawing은 실API(Remote) 리포지토리를 주입하고,
/// activity·report는 백엔드 API가 생길 때까지 Mock 기본값을 유지한다
/// (S15P11B209-384 계약 교차 검증, 2026-07-24).
///
/// 테스트에서는 [DodamApp]의 생성자 주입을 통해 Mock Repository를 사용할 수
/// 있으며, 기본 구성은 인증 세션과 각 도메인 API가 같은 [ApiClient]를 공유한다.
DodamApp createDefaultApp({
  ApiEnvironment? environment,
  AuthSessionStore? authSessionStore,
}) {
  late final ApiClient apiClient;
  final authRepository = RemoteAuthRepository(
    apiClient: () => apiClient,
    deviceIdProvider: SecureDeviceIdProvider(),
    sessionStore: authSessionStore ?? SecureAuthSessionStore(),
  );
  apiClient = ApiClient(
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
