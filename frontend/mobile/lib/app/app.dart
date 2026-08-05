import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

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
import '../features/drawing/data/disk_pending_htp_photo_store.dart';
import '../features/drawing/data/dto/drawing_dtos.dart';
import '../features/drawing/data/repositories/mock_drawing_repository.dart';
import '../features/drawing/domain/pending_htp_photo.dart';
import '../features/drawing/domain/repositories/drawing_repository.dart';
import '../features/conversation/conversation.dart';
import '../features/guardian_pin/data/repositories/mock_guardian_pin_repository.dart';
import '../features/guardian_pin/domain/repositories/guardian_pin_repository.dart';
import '../features/guardian_pin/presentation/widgets/guardian_reauth_sheet.dart';
import '../features/notification/application/notification_badge_controller.dart';
import '../features/notification/application/push_registration_status_controller.dart';
import '../features/notification/domain/entities/push_message.dart';
import '../features/notification/domain/failures/push_token_registration_failure.dart';
import '../features/notification/domain/repositories/notification_inbox_repository.dart';
import '../features/notification/domain/services/push_coordinator.dart';
import '../features/notification/domain/services/push_setup.dart';
import '../features/report/data/repositories/mock_report_repository.dart';
import '../features/report/data/services/platform_report_file_actions.dart';
import '../features/report/domain/repositories/report_repository.dart';
import '../features/report/domain/services/report_file_actions.dart';
import '../features/report/presentation/services/report_snapshot_pdf.dart';
import '../features/settings/data/repositories/mock_account_withdrawal_repository.dart';
import '../features/settings/data/repositories/mock_data_retention_repository.dart';
import '../features/settings/data/repositories/mock_notification_settings_repository.dart';
import '../features/settings/domain/repositories/account_withdrawal_repository.dart';
import '../features/settings/domain/repositories/data_retention_repository.dart';
import '../features/settings/domain/repositories/notification_settings_repository.dart';
import '../features/settings/domain/repositories/guardian_profile_repository.dart';
import 'router/app_navigation.dart';
import 'router/app_router.dart';
import 'router/app_routes.dart';
import 'router/current_route_observer.dart';
import 'router/notification_route_resolver.dart';
import 'state/guardian_child_controller.dart';
import 'state/guardian_unlock_controller.dart';

class DodamApp extends StatefulWidget {
  const DodamApp({
    this.activityRepository = const MockActivityRepository(),
    this.childRepository = const MockChildRepository(),
    this.childConsentRepository = const MockChildConsentRepository(),
    this.consentRepository = const MockConsentRepository(),
    this.accountWithdrawalRepository = const MockAccountWithdrawalRepository(),
    this.dataRetentionRepository = const MockDataRetentionRepository(),
    this.notificationSettingsRepository =
        const MockNotificationSettingsRepository(),
    this.drawingRepository = const MockDrawingRepository(),
    this.reportRepository = const MockReportRepository(),
    this.reportFileActions = const PlatformReportFileActions(),
    this.reportPdfComposer,
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
    this.pendingHtpPhotoStore,
    this.guardianPinRepository,
    this.guardianPinGateEnabled = false,
    this.initialRoute = AppRoutes.guardianHome,
    super.key,
  });

  final ActivityRepository activityRepository;
  final ChildRepository childRepository;

  /// 아동 대상 약관 조회·동의 기록 경계. 실 연동 시 원격 구현을 주입한다.
  final ChildConsentRepository childConsentRepository;
  final ConsentRepository consentRepository;

  /// USER-05 회원 탈퇴 경계. 실 연동 시 원격 구현을 주입한다.
  final AccountWithdrawalRepository accountWithdrawalRepository;

  /// 데이터 보관 기간 조회·편집 경계(S15P11B209-456). 실 연동 시 원격 구현을 주입한다.
  final DataRetentionRepository dataRetentionRepository;

  /// 알림 수신 설정 조회·수정 경계(S15P11B209-455).
  final NotificationSettingsRepository notificationSettingsRepository;
  final DrawingRepository drawingRepository;
  final ReportRepository reportRepository;
  final ReportFileActions reportFileActions;

  /// 리포트 화면을 PDF 로 굽는 경계다. 테스트는 실제 캡처 없이 저장 흐름만 확인한다.
  final ReportPdfComposer? reportPdfComposer;
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

  /// HTP 선촬영 사진 보관 저장소(S15P11B209-872). 주입하지 않으면 기기 문서
  /// 디렉터리 기반 디스크 저장소를 쓴다(테스트는 메모리 구현을 주입).
  final PendingHtpPhotoStore? pendingHtpPhotoStore;

  /// 보호자 PIN 경계(S15P11B209-874). 주입하지 않으면 메모리 Mock을 쓴다.
  final GuardianPinRepository? guardianPinRepository;

  /// 보호자 홈 진입 앞에 PIN gate를 세울지(S15P11B209-874, 기본 꺼짐).
  ///
  /// 서버에 `GUARDIAN_PIN_PEPPER`가 주입돼 PIN API가 `PIN_UNAVAILABLE` 없이
  /// 응답하는 것이 확인된 뒤에 켠다. 확인 전에는 꺼 두는 것이 올바른 대응이다 —
  /// gate 안에서 장애를 우회시키면 보안 장치가 사라진다.
  final bool guardianPinGateEnabled;
  final String initialRoute;

  @override
  State<DodamApp> createState() => _DodamAppState();
}

class _DodamAppState extends State<DodamApp> with WidgetsBindingObserver {
  /// HTP 선촬영 사진 저장소. 주입이 없으면 기기 문서 디렉터리 기반 디스크
  /// 저장소를 쓴다(S15P11B209-872).
  late final PendingHtpPhotoStore _pendingHtpPhotoStore =
      widget.pendingHtpPhotoStore ??
      DiskPendingHtpPhotoStore(rootDirectory: getApplicationDocumentsDirectory);
  late final GuardianChildController _childController;

  /// 보호자 PIN 경계. 주입이 없으면 메모리 Mock을 쓴다(S15P11B209-874).
  late final GuardianPinRepository _guardianPinRepository =
      widget.guardianPinRepository ?? MockGuardianPinRepository();

  /// 보호자 PIN gate의 세션 단위 잠금 해제 상태.
  final _guardianUnlock = GuardianUnlockController();
  late final AuthRepository _authRepository;
  late final SocialLoginService _socialLoginService;
  late final KakaoLoginClient _kakaoLoginClient;
  late final GoogleLoginClient _googleLoginClient;
  late final NaverLoginClient _naverLoginClient;
  late final KakaoLoginCoordinator _kakaoLoginCoordinator;
  late final GoogleLoginCoordinator _googleLoginCoordinator;
  late final NaverLoginCoordinator _naverLoginCoordinator;
  final _navigatorKey = GlobalKey<NavigatorState>();

  /// 아동 모드로 들어가면 보호자 잠금을 되돌린다(재잠금 트리거 b). 아이가 쓰던
  /// 기기를 그대로 넘겨받아도 보호자 화면은 PIN을 다시 묻는다.
  late final _routeObserver = CurrentRouteObserver(
    onChildModeEntered: _guardianUnlock.lock,
  );
  PushCoordinator? _pushCoordinator;
  NotificationBadgeController? _notificationBadgeController;

  /// 디바이스 Token 등록이 거절돼 이 계정이 푸시를 받지 못하는 상태인지.
  /// 보호자 화면이 구독해 안내를 띄운다.
  final _pushRegistrationStatus = PushRegistrationStatusController();
  AuthSession? _currentSession;

  /// 로그아웃 정리가 진행 중인지. 로그아웃 진입점이 두 곳이라 재진입을 막는다.
  bool _isSigningOut = false;

  /// 보호자 셸이 지금 보여주는 탭의 라우트 이름. 셸이 알려 준다.
  String? _guardianTabRoute;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _childController = GuardianChildController(
      widget.childRepository,
      widget.childConsentRepository,
    );
    final inboxRepository = widget.notificationInboxRepository;
    if (inboxRepository != null) {
      _notificationBadgeController = NotificationBadgeController(
        inboxRepository,
      );
    }
    if (widget.initialRoute != AppRoutes.authBootstrap) {
      _childController.loadChildren();
      // 인증 부트스트랩을 거치지 않는 구성(데모·직접 진입)은 여기가 앱 진입이다.
      _refreshNotificationBadge();
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
      isGuardianSessionActive: () => _hasGuardianSession,
      onInboxChanged: _refreshNotificationBadge,
      onTokenRegistrationResult: _handlePushTokenRegistrationResult,
    );
  }

  void _refreshNotificationBadge() {
    unawaited(_notificationBadgeController?.refresh());
  }

  /// 디바이스 Token 등록 결과를 보호자 화면에 전달한다.
  ///
  /// 등록이 거절된 계정에는 서버가 푸시를 보내지 않는다. 푸시 수신에 기대던 배지
  /// 갱신이 아예 오지 않으므로, 실패를 알게 된 지금 한 번 서버 값을 읽어 배지가
  /// 0에서 멈춰 있지 않게 한다. 주기 폴링은 두지 않는다(배터리·트래픽) —
  /// 나머지는 홈·알림 탭 재진입과 알림 팝업 열기가 담당한다(S15P11B209-842).
  void _handlePushTokenRegistrationResult(
    PushTokenRegistrationFailure? failure,
  ) {
    _pushRegistrationStatus.report(failure);
    if (failure != null) _refreshNotificationBadge();
  }

  /// 포그라운드로 돌아오면 미열람 수를 다시 센다. 백그라운드에서 받은 푸시는
  /// 앱이 떠 있을 때의 수신 스트림을 타지 않아 배지가 뒤처진다.
  ///
  /// 화면이 가려지는 순간 보호자 잠금을 되돌리고, 보호자 화면을 보던 중이었다면
  /// 그 자리에서 gate로 돌려보낸다(재잠금 트리거 a, S15P11B209-874).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _relockGuardian();
      return;
    }
    if (state != AppLifecycleState.resumed) return;
    _refreshNotificationBadge();
  }

  /// 보호자 잠금을 되돌리고, 떠 있던 보호자 화면을 gate로 바꿔 둔다.
  ///
  /// 잠그기만 하면 이미 떠 있는 화면은 그대로 남는다 — gate는 라우트를 다시
  /// 만들 때만 서기 때문이다. 보호자 홈 위에 쌓인 화면(리포트·설정 등)도 같은
  /// 보호자 영역이라 함께 되돌린다.
  ///
  /// 되돌리기를 복귀(`resumed`)가 아니라 나가는 순간(`paused`)에 하는 이유:
  /// 복귀 뒤에 옮기면 앱 전환기 미리보기와 복귀 직후 첫 프레임에 보호자 화면이
  /// 그대로 남는다. 실기기 확인에서도 복귀 시점 이동은 gate를 다시 세우지
  /// 못했다.
  ///
  /// 아동 모드·로그인처럼 보호자 영역 밖일 때는 건드리지 않는다. 그 화면들은
  /// 보호자 홈으로 돌아오는 길에 gate를 지난다. flag가 꺼져 있으면 잠금도 이동도
  /// 하지 않는다 — gate가 없는 구성에서 이동만 일어나면 안 된다.
  void _relockGuardian() {
    if (!widget.guardianPinGateEnabled) return;
    final wasUnlocked = _guardianUnlock.isUnlocked;
    _guardianUnlock.lock();
    if (!wasUnlocked) return;
    if (_routeObserver.currentRouteName?.startsWith('/guardian') != true) {
      return;
    }
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;
    AppNavigation.resetToOn(navigator, AppRoutes.guardianHome);
  }

  /// 푸시가 가리키는 화면을 열어도 되는 세션인지.
  ///
  /// [_onGuardianSessionReady]가 푸시를 켤 때 쓴 조건과 같다. 켤 때만 보고 끌 때를
  /// 보지 않으면 세션이 끝난 뒤 도착한 탭이 그대로 이동한다. 판정은 코디네이터가
  /// 아동 모드 게이트와 같은 자리에서 하고(`push_coordinator.dart`), 세션 상태는
  /// 앱 계층만 알 수 있어 여기서 넘긴다.
  bool get _hasGuardianSession {
    final session = _currentSession;
    return session != null &&
        !session.requiresOnboarding &&
        session.user.role == UserRole.guardian;
  }

  /// 푸시가 가리키는 화면으로 이동한다.
  ///
  /// 연결 자원이 없으면 알림함 목록으로 보낸다(계약 §4.3). 알림함 카드 클릭과
  /// 같은 매핑 함수를 쓰고, 이동도 같은 진입점을 지난다(S15P11B209-501).
  ///
  /// `Navigator`를 직접 부르면 이미 보고 있는 화면이 한 장 더 쌓인다 — 연결
  /// 자원이 없는 푸시를 알림함에서 누르는 경우가 그렇다. 카드 탭 쪽은 같은
  /// 상황에서 이동하지 않으므로, 판정기를 공유해 두 경로를 맞춘다.
  ///
  /// 세션 없이 도착한 탭은 여기까지 오지 않는다 — 코디네이터가 아동 모드 게이트
  /// 옆에서 [_hasGuardianSession]으로 먼저 걸러낸다.
  void _openPushTarget(PushMessage message) {
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;

    AppNavigation.pushNamedOn(
      navigator,
      resolvePushRoute(message),
      currentRouteName: _visibleRouteName,
    );
  }

  /// 중복 이동 판정이 "지금 보고 있는 화면"으로 삼을 라우트.
  ///
  /// 보호자 셸은 탭을 바꿔도 라우트를 쌓지 않아 관찰자에게는 늘
  /// `/guardian/home`이다. 그래서 알림 탭을 보는 중에 연결 자원 없는 푸시가 오면
  /// 이미 보고 있는 알림함이 한 장 더 쌓였다(S15P11B209-501). 셸이 알려 준 탭
  /// 라우트를 그 자리에 대신 넣어 두 경로의 판정을 맞춘다.
  ///
  /// 셸 위에 다른 화면이 올라가 있으면 그 화면이 "지금 화면"이 맞으므로, 셸이
  /// 최상단일 때만 바꿔치기한다.
  String? get _visibleRouteName {
    final current = _routeObserver.currentRouteName;
    if (current != AppRoutes.guardianHome) return current;
    return _guardianTabRoute ?? current;
  }

  // Provider별 SDK 로그인. 세션 표시는 건드리지 않는다 — 채택 여부는 호출자가
  // 정한다(로그인 화면은 결과를 그대로 받고, 재인증은 계정을 대조한 뒤 받는다).
  Future<AuthState> _providerSignIn(AuthProvider provider) =>
      switch (provider) {
        AuthProvider.kakao => _kakaoLoginCoordinator.signIn(),
        AuthProvider.google => _googleLoginCoordinator.signIn(),
        AuthProvider.naver => _naverLoginCoordinator.signIn(),
      };

  // Provider별 로그인 실행
  Future<AuthState> _signIn(AuthProvider provider) async {
    final state = await _providerSignIn(provider);
    _currentSession = state.session;
    await _onGuardianSessionReady(state.session);
    return state;
  }

  /// PIN 재설정 앞에 세우는 본인확인(S15P11B209-874).
  ///
  /// 백엔드 `DELETE users/me/guardian-pin`은 현재 PIN도 별도 확인도 요구하지
  /// 않고 로그인 세션만으로 PIN을 지운다. 그대로 노출하면 기기를 넘겨받은 아이가
  /// 재설정을 눌러 새 PIN을 정하고 gate를 지나간다. 그래서 소셜 재로그인을 태우고
  /// **같은 계정**일 때만 초기화를 허용한다.
  ///
  /// 알려진 한계: 기기에 소셜 세션이 남아 있으면 제공자 SDK가 SSO로 조용히
  /// 통과시킬 수 있어 이 재인증이 항상 강한 본인확인은 아니다. 그래도 (a) 제공자
  /// SDK를 반드시 태우고 (b) 계정 동일성을 검사해 "무확인 초기화"와 "남의 계정
  /// PIN 삭제"는 막는다. 더 강한 확인(이메일 OTP 등)은 백엔드(S879)에 reset 전용
  /// 검증이 생겨야 가능하다.
  Future<bool> _reauthenticateGuardian(BuildContext context) async {
    final beforeId = _currentSession?.user.id;
    if (beforeId == null) return false;

    final selected = await showGuardianReauthSheet(context);
    if (selected == null) return false;

    final AuthState state;
    try {
      state = await _providerSignIn(_authProviderFor(selected));
    } on Object {
      // 실패 원인에는 제공자 토큰이 섞일 수 있어 남기지 않는다.
      return false;
    }

    final session = state.session;
    // 취소·실패는 저장된 세션을 건드리지 않는다. 여기서 세션을 비우면 재인증을
    // 그만둔 보호자가 로그아웃된 것처럼 보인다.
    if (session == null) return false;

    // 다른 계정으로 로그인됐다면 토큰 저장소는 이미 그 계정 것이다. 표시 세션도
    // 실제와 맞춰 둬야 이후 요청이 엉뚱한 계정으로 나가지 않는다. 다만 초기화는
    // 허용하지 않는다 — 그 계정의 PIN을 다시 세우려면 한 번 더 본인확인을 지난다.
    _currentSession = session;
    await _onGuardianSessionReady(session);
    return session.user.id == beforeId;
  }

  static AuthProvider _authProviderFor(SocialLoginProvider provider) =>
      switch (provider) {
        SocialLoginProvider.kakao => AuthProvider.kakao,
        SocialLoginProvider.google => AuthProvider.google,
        SocialLoginProvider.naver => AuthProvider.naver,
      };

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
    // 보호자 세션이 확정된 뒤라야 알림함 조회에 토큰이 실린다.
    _refreshNotificationBadge();

    if (_pushCoordinator == null) {
      developer.log('pushSetup 미주입 — 푸시 비활성', name: 'push');
      return;
    }
    await _pushCoordinator?.start();
  }

  // 인증 세션과 보호자 선택 상태 초기화
  //
  // 로그아웃 버튼은 두 곳에 있다(보호자 홈 헤더의 LogoutActionButton, 설정 화면).
  // 각 위젯은 자기 화면 안에서만 중복 탭을 막으므로, 여기서 한 번 더 막는다.
  // 재진입하면 정리 작업이 두 번 실행돼 이미 만료된 세션으로 서버를 호출한다 —
  // 기기 Token 해제가 401로 실패하던 경로가 그것이다(S15P11B209-869).
  Future<void> _signOut() async {
    if (_isSigningOut) return;
    _isSigningOut = true;
    try {
      await _runSignOut();
    } finally {
      _isSigningOut = false;
    }
  }

  Future<void> _runSignOut() async {
    final provider = _currentSession?.user.provider;
    // 아래 정리에는 await가 여럿이고 그 사이에도 푸시 탭이 들어온다. 세션 표시를
    // 먼저 내려야 정리 도중 도착한 탭이 이동으로 이어지지 않는다. Token 해제
    // API의 인증은 저장소에 남은 토큰이 담당하므로(바로 아래 signOut이 지운다)
    // 이 참조를 먼저 비워도 해제 호출에는 영향이 없다.
    _currentSession = null;
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
    _childController.clear();
    _notificationBadgeController?.clear();
    // 등록 상태는 직전 계정의 것이다. 다음 로그인이 다시 판정한다.
    _pushRegistrationStatus.clear();
  }

  Future<AuthenticatedUser> _loadProfile() async {
    final repository = _authRepository;
    if (repository is! GuardianProfileRepository) return _currentSession!.user;
    final user = await (repository as GuardianProfileRepository)
        .getCurrentUserProfile();
    final session = _currentSession;
    if (session != null && mounted) {
      setState(() => _currentSession = session.copyWith(user: user));
    }
    return user;
  }

  Future<AuthenticatedUser> _updateProfile(String nickname) async {
    final repository = _authRepository;
    if (repository is! GuardianProfileRepository) {
      throw StateError('보호자 프로필 수정 기능을 사용할 수 없습니다.');
    }
    final user = await (repository as GuardianProfileRepository)
        .updateCurrentUserProfile(nickname: nickname);
    final session = _currentSession;
    if (session != null && mounted) {
      setState(() => _currentSession = session.copyWith(user: user));
    }
    return user;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notificationBadgeController?.dispose();
    _pushRegistrationStatus.dispose();
    _childController.dispose();
    _guardianUnlock.dispose();
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
      authLoadProfile: _loadProfile,
      authUpdateProfile: _updateProfile,
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
      reportPdfComposer: widget.reportPdfComposer,
      notificationInboxRepository: widget.notificationInboxRepository,
      notificationBadgeController: _notificationBadgeController,
      pushRegistrationStatus: _pushRegistrationStatus,
      onGuardianTabChanged: (routeName) => _guardianTabRoute = routeName,
      consentRepository: widget.consentRepository,
      accountWithdrawalRepository: widget.accountWithdrawalRepository,
      dataRetentionRepository: widget.dataRetentionRepository,
      notificationSettingsRepository: widget.notificationSettingsRepository,
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
      pendingHtpPhotoStore: _pendingHtpPhotoStore,
      guardianUnlock: _guardianUnlock,
      guardianPinRepository: _guardianPinRepository,
      guardianPinGateEnabled: widget.guardianPinGateEnabled,
      onReauthenticateGuardian: _reauthenticateGuardian,
    ),
  );
}
