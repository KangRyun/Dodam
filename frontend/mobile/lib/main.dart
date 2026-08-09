import 'dart:developer' as developer;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/orientation/app_orientation_policy.dart';
import 'app/router/app_routes.dart';
import 'core/network/network.dart';
import 'features/activity/data/repositories/remote_activity_repository.dart';
import 'features/auth/auth.dart';
import 'features/child/data/repositories/remote_child_consent_repository.dart';
import 'features/child/data/repositories/remote_child_repository.dart';
import 'features/consent/data/repositories/remote_consent_repository.dart';
import 'features/conversation/conversation.dart';
import 'features/drawing/data/device_photo_permission_service.dart';
import 'features/drawing/data/repositories/mock_drawing_repository.dart';
import 'features/drawing/data/repositories/remote_drawing_repository.dart';
import 'features/guardian_pin/data/repositories/remote_guardian_pin_repository.dart';
import 'features/notification/data/repositories/remote_push_token_repository.dart';
import 'features/notification/data/repositories/remote_notification_inbox_repository.dart';
import 'features/notification/data/services/device_push_permission_service.dart';
import 'features/notification/data/services/firebase_push_gateway.dart';
import 'features/notification/data/services/local_push_presenter.dart';
import 'features/notification/data/services/push_background_handler.dart';
import 'features/notification/domain/services/push_setup.dart';
import 'features/permission/application/permission_onboarding_controller.dart';
import 'features/permission/data/secure_permission_onboarding_store.dart';
import 'features/report/data/repositories/remote_report_repository.dart';
import 'features/settings/data/repositories/remote_account_withdrawal_repository.dart';
import 'features/settings/data/repositories/remote_data_retention_repository.dart';
import 'features/settings/data/repositories/remote_notification_settings_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 모든 production route는 같은 전역 가로 정책을 사용한다. 실패해도 정책이
  // 내부에서 기록하고 false를 반환하므로 앱 시작은 계속된다(S15P11B209-878).
  final orientationPolicy = AppOrientationPolicy();
  await orientationPolicy.start();
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
  // 사진 업로드 백엔드 API(S15P11B209-700)가 완료되어 HTP 사진 업로드를 기본
  // 노출한다. 필요 시 --dart-define=HTP_PHOTO_UPLOAD_ENABLED=false 로 끌 수 있다.
  const htpPhotoUploadEnabled = bool.fromEnvironment(
    'HTP_PHOTO_UPLOAD_ENABLED',
    defaultValue: true,
  );
  // 보호자 홈 진입 PIN gate(S15P11B209-874). 기본 켜짐 —
  // 켤 조건으로 걸어 두었던 것(운영 서버에 `GUARDIAN_PIN_PEPPER` 주입 + PIN API가
  // `PIN_UNAVAILABLE` 없이 응답)을 2026-08-09 실측으로 확인했다:
  //   GET /api/v1/users/me/guardian-pin → 401(인증 필요). 기능이 죽어 있으면
  //   여기서 PIN_UNAVAILABLE 이 온다.
  // 아이가 아동 모드에서 빠져나와 보호자 화면(리포트·설정)에 닿는 길을 막는 장치라,
  // 기본값이 꺼짐이면 아무도 켜지 않은 채로 남는다.
  // 문제가 생기면 --dart-define=GUARDIAN_PIN_GATE_ENABLED=false 로 끈다.
  const guardianPinGateEnabled = bool.fromEnvironment(
    'GUARDIAN_PIN_GATE_ENABLED',
    defaultValue: true,
  );

  return DodamApp(
    htpPhotoUploadEnabled: htpPhotoUploadEnabled,
    guardianPinGateEnabled: guardianPinGateEnabled,
    // 로그인 직후 한 번만 세우는 권한 안내. 요청은 각 기능이 이미 쓰는 서비스에
    // 그대로 위임하므로, 건너뛰거나 거부해도 기존 개별 요청 경로가 살아 있다.
    permissionOnboarding: PermissionOnboardingController(
      store: SecurePermissionOnboardingStore(),
      microphonePermissionService: DeviceMicrophonePermissionService(),
      photoPermissionService: const DevicePhotoPermissionService(),
      pushPermissionService: DevicePushPermissionService(),
    ),
    guardianPinRepository: RemoteGuardianPinRepository(apiClient),
    authRepository: authRepository,
    activityRepository: RemoteActivityRepository(apiClient),
    childRepository: RemoteChildRepository(apiClient),
    childConsentRepository: RemoteChildConsentRepository(apiClient),
    consentRepository: RemoteConsentRepository(apiClient),
    accountWithdrawalRepository: RemoteAccountWithdrawalRepository(apiClient),
    dataRetentionRepository: RemoteDataRetentionRepository(apiClient),
    notificationSettingsRepository: RemoteNotificationSettingsRepository(
      apiClient,
    ),
    conversationRepository: RemoteConversationRepository(apiClient),
    conversationEndRepository: RemoteConversationEndRepository(apiClient),
    questionTtsRepository: RemoteQuestionTtsRepository(apiClient),
    questionAudioPlayerFactory: DeviceQuestionAudioPlayer.new,
    questionSpeechSynthesizer: DeviceQuestionSpeechSynthesizer(),
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
