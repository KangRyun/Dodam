import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/router/app_routes.dart';
import 'core/network/network.dart';
import 'features/auth/auth.dart';
import 'features/drawing/data/repositories/remote_drawing_repository.dart';

void main() {
  runApp(createDefaultApp());
}

/// 공개 API와 Provider SDK를 사용하는 기본 애플리케이션 구성을 생성한다.
///
/// 테스트에서는 [DodamApp]의 생성자 주입을 통해 Mock Repository를 사용할 수
/// 있으며, 기본 구성은 인증 세션과 Drawing API가 같은 [ApiClient]를 공유한다.
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
    drawingRepository: RemoteDrawingRepository(apiClient),
    initialRoute: AppRoutes.authBootstrap,
  );
}
