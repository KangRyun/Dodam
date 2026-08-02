import 'dart:developer' as developer;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/router/app_routes.dart';
import 'core/network/network.dart';
import 'features/activity/data/repositories/remote_activity_repository.dart';
import 'features/auth/auth.dart';
import 'features/child/data/repositories/remote_child_consent_repository.dart';
import 'features/child/data/repositories/remote_child_repository.dart';
import 'features/consent/data/repositories/remote_consent_repository.dart';
import 'features/conversation/conversation.dart';
import 'features/drawing/data/repositories/mock_drawing_repository.dart';
import 'features/drawing/data/repositories/remote_drawing_repository.dart';
import 'features/notification/data/repositories/remote_push_token_repository.dart';
import 'features/notification/data/repositories/remote_notification_inbox_repository.dart';
import 'features/notification/data/services/device_push_permission_service.dart';
import 'features/notification/data/services/firebase_push_gateway.dart';
import 'features/notification/data/services/local_push_presenter.dart';
import 'features/notification/data/services/push_background_handler.dart';
import 'features/notification/domain/services/push_setup.dart';
import 'features/report/data/repositories/remote_report_repository.dart';
import 'features/settings/data/repositories/remote_account_withdrawal_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 푸시는 선택 기능이라 초기화가 실패해도 앱은 떠야 한다(계약 §0-6).
  final pushReady = await _initializePush();
  runApp(createDefaultApp(pushEnabled: pushReady));
}

/// Firebase를 준비하고 백그라운드 수신 경로를 등록한다.
///
/// 자격증명 누락·플랫폼 미지원 등으로 실패하면 `false`를 돌려주고, 앱은 푸시만
/// 꺼진 채로 정상 동작한다.
Future<bool> _initializePush() async {
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(handlePushInBackground);
    developer.log('Firebase 초기화 완료 — 푸시 사용', name: 'push');
    return true;
  } on Object catch (error, stackTrace) {
    // 조용히 끄면 "알림이 안 온다"를 추적할 방법이 없다.
    developer.log(
      'Firebase 초기화 실패 — 푸시를 끈 채로 계속한다',
      name: 'push',
      error: error,
      stackTrace: stackTrace,
    );
    return false;
  }
}

/// 공개 API와 Provider SDK를 사용하는 기본 애플리케이션 구성을 생성한다.
///
/// child·conversation(다음질문)·drawing·report는 실API(Remote) 리포지토리를
/// 주입하고, activity는 백엔드 API가 생길 때까지 Mock 기본값을 유지한다
/// (S15P11B209-384 계약 교차 검증 2026-07-24, report는 S15P11B209-496에서 연동).
///
/// 테스트에서는 [DodamApp]의 생성자 주입을 통해 Mock Repository를 사용할 수
/// 있으며, 기본 구성은 인증 세션과 각 도메인 API가 같은 [ApiClient]를 공유한다.
DodamApp createDefaultApp({
  ApiEnvironment? environment,
  AuthSessionStore? authSessionStore,
  bool pushEnabled = false,
}) {
  late final ApiClient apiClient;
  final deviceIdProvider = SecureDeviceIdProvider();
  final authRepository = RemoteAuthRepository(
    apiClient: () => apiClient,
    deviceIdProvider: deviceIdProvider,
    sessionStore: authSessionStore ?? SecureAuthSessionStore(),
  );
  apiClient = ApiClient(
    environment: environment ?? ApiEnvironment.fromDartDefine(),
    accessTokenProvider: authRepository,
    tokenRefresher: authRepository,
  );
  const useMockDrawing = bool.fromEnvironment(
    'USE_MOCK_DRAWING',
    defaultValue: false,
  );
  // S15P11B209-702: 백엔드 사진 업로드 API가 검증되기 전까지 기본 꺼짐.
  // 실기기 확인은 flutter run --dart-define=HTP_PHOTO_UPLOAD_ENABLED=true 로 켠다.
  const htpPhotoUploadEnabled = bool.fromEnvironment(
    'HTP_PHOTO_UPLOAD_ENABLED',
    defaultValue: false,
  );

  return DodamApp(
    htpPhotoUploadEnabled: htpPhotoUploadEnabled,
    authRepository: authRepository,
    activityRepository: RemoteActivityRepository(apiClient),
    childRepository: RemoteChildRepository(apiClient),
    childConsentRepository: RemoteChildConsentRepository(apiClient),
    consentRepository: RemoteConsentRepository(apiClient),
    accountWithdrawalRepository: RemoteAccountWithdrawalRepository(apiClient),
    conversationRepository: RemoteConversationRepository(apiClient),
    conversationEndRepository: RemoteConversationEndRepository(apiClient),
    questionTtsRepository: RemoteQuestionTtsRepository(apiClient),
    questionAudioPlayerFactory: DeviceQuestionAudioPlayer.new,
    voiceAnswerPlaybackRepository: RemoteVoiceAnswerPlaybackRepository(
      apiClient,
    ),
    voiceAnswerAudioPlayerFactory: DeviceVoiceAnswerAudioPlayer.new,
    conversationAnswerRepository: RemoteConversationAnswerRepository(apiClient),
    questionSkipRepository: RemoteQuestionSkipRepository(apiClient),
    // 백엔드 미연결 개발 환경에서만 목 그림 세션 사용
    drawingRepository: useMockDrawing
        ? const MockDrawingRepository()
        : RemoteDrawingRepository(apiClient),
    voiceAnswerRepository: RemoteVoiceAnswerRepository(apiClient),
    sttResultRepository: RemoteSttResultRepository(apiClient),
    reportRepository: RemoteReportRepository(apiClient),
    notificationInboxRepository: RemoteNotificationInboxRepository(apiClient),
    // Firebase 준비에 실패하면 주입하지 않아 푸시 경로 자체가 꺼진다.
    pushSetup: pushEnabled
        ? PushSetup(
            gateway: FirebasePushGateway(),
            presenter: LocalPushPresenter(),
            tokenRepository: RemotePushTokenRepository(
              apiClient: apiClient,
              // 인증과 같은 설치 식별자를 써야 서버의 upsert가 성립한다.
              deviceIdProvider: deviceIdProvider,
            ),
            permissionService: DevicePushPermissionService(),
            // 실기기 검증용. 기본 꺼짐 —
            // flutter run --dart-define=PUSH_LOG_TOKEN=true
            exposeTokenInLogs: const bool.fromEnvironment('PUSH_LOG_TOKEN'),
          )
        : null,
    initialRoute: AppRoutes.authBootstrap,
  );
}
