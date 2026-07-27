import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_naver_login/flutter_naver_login.dart';
import 'package:flutter_naver_login/interface/types/naver_login_status.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';

enum ProviderSdkFailureType { cancelled, rejected, configuration }

/// Provider SDK 예외를 인증 계층에서 해석 가능한 제한된 원인으로 정규화한다.
final class ProviderSdkFailure implements Exception {
  const ProviderSdkFailure(this.type, {this.cause});

  final ProviderSdkFailureType type;
  final Object? cause;
}

/// Provider SDK 실패 원인을 Debug 빌드에서만 기록하고 정규화된 실패를 만든다.
///
/// Google Android SDK가 돌려주는 숫자 상태 코드(`[10]` 설정 오류 · `[16]` 재인증
/// 실패)는 [GoogleSignInException.code]가 아니라 description·details에만 실려
/// 오기 때문에, 실기기 실패 원인을 가르려면 이 Field들을 함께 남겨야 한다.
///
/// 아동 민감정보 가드레일에 따라 예외 객체를 통째로 출력하지 않는다. Token과
/// 계정 식별자가 로그로 새지 않도록 진단에 필요한 Field만 골라 기록하고,
/// Release 빌드에서는 [kDebugMode] 분기로 기록 자체를 실행하지 않는다.
ProviderSdkFailure _sdkFailure(
  String provider,
  ProviderSdkFailureType type,
  Object? cause, {
  StackTrace? stackTrace,
}) {
  if (kDebugMode) {
    final detail = StringBuffer('[OAuth][$provider] type=${type.name}');
    if (cause != null) {
      switch (cause) {
        case GoogleSignInException(
          :final code,
          :final description,
          :final details,
        ):
          detail.write(' code=$code description=$description details=$details');
        case KakaoClientException(:final reason):
          detail.write(' reason=$reason');
        case PlatformException(:final code, :final message):
          detail.write(' code=$code message=$message');
        default:
          detail.write(' error=${cause.runtimeType}');
      }
    }
    debugPrint(detail.toString());
    if (stackTrace != null) {
      debugPrintStack(stackTrace: stackTrace);
    }
  }
  return ProviderSdkFailure(type, cause: cause);
}

/// Provider별 Native SDK 호출을 Login Client에서 분리하는 경계다.
abstract interface class ProviderSdkGateway {
  Future<String?> signIn();

  Future<void> signOut();
}

/// Kakao SDK 호출을 로그인 정책과 분리하는 경계다.
abstract interface class KakaoSdkClient {
  Future<void> initialize(String nativeAppKey);

  Future<String> login();

  Future<bool> needsEmailAgreement();

  Future<String?> requestAdditionalConsent(List<String> scopes);

  Future<void> logout();
}

/// Kakao Flutter SDK를 초기화하고 Kakao Access Token을 발급받는다.
final class KakaoProviderSdkGateway implements ProviderSdkGateway {
  factory KakaoProviderSdkGateway({
    String nativeAppKey = const String.fromEnvironment('KAKAO_NATIVE_APP_KEY'),
    KakaoSdkClient? sdkClient,
  }) => KakaoProviderSdkGateway._(
    nativeAppKey,
    sdkClient ?? _DefaultKakaoSdkClient(),
  );

  KakaoProviderSdkGateway._(this._nativeAppKey, this._sdkClient);

  final String _nativeAppKey;
  final KakaoSdkClient _sdkClient;
  Future<void>? _initialization;

  @override
  Future<String?> signIn() async {
    try {
      await _initialize();
      final initialToken = await _sdkClient.login();
      if (!await _sdkClient.needsEmailAgreement()) {
        return initialToken;
      }
      return await _sdkClient.requestAdditionalConsent(const [
            'account_email',
          ]) ??
          initialToken;
    } on KakaoClientException catch (error) {
      throw _sdkFailure(
        'kakao',
        error.reason == ClientErrorCause.cancelled
            ? ProviderSdkFailureType.cancelled
            : ProviderSdkFailureType.rejected,
        error,
      );
    } on ProviderSdkFailure {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw _sdkFailure(
        'kakao',
        ProviderSdkFailureType.rejected,
        error,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _initialize();
      await _sdkClient.logout();
    } on ProviderSdkFailure {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw _sdkFailure(
        'kakao',
        ProviderSdkFailureType.rejected,
        error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _initialize() {
    if (_nativeAppKey.isEmpty ||
        _nativeAppKey.startsWith('your-') ||
        _nativeAppKey.startsWith('missing-')) {
      throw _sdkFailure('kakao', ProviderSdkFailureType.configuration, null);
    }
    return _initialization ??= _sdkClient.initialize(_nativeAppKey);
  }
}

final class _DefaultKakaoSdkClient implements KakaoSdkClient {
  @override
  Future<void> initialize(String nativeAppKey) =>
      KakaoSdk.init(nativeAppKey: nativeAppKey, loggingEnabled: false);

  @override
  Future<String> login() async {
    final token = await ((await isKakaoTalkInstalled())
        ? UserApi.instance.loginWithKakaoTalk()
        : UserApi.instance.loginWithKakaoAccount());
    return token.accessToken;
  }

  @override
  Future<bool> needsEmailAgreement() async =>
      (await UserApi.instance.me()).kakaoAccount?.emailNeedsAgreement == true;

  @override
  Future<String?> requestAdditionalConsent(List<String> scopes) async {
    try {
      return (await UserApi.instance.loginWithNewScopes(scopes)).accessToken;
    } on KakaoClientException catch (error) {
      if (error.reason == ClientErrorCause.cancelled) {
        return null;
      }
      rethrow;
    }
  }

  @override
  Future<void> logout() => UserApi.instance.logout();
}

/// Google Sign-In SDK에서 Backend Audience용 ID Token을 발급받는다.
final class GoogleProviderSdkGateway implements ProviderSdkGateway {
  factory GoogleProviderSdkGateway({
    String serverClientId = const String.fromEnvironment(
      'GOOGLE_SERVER_CLIENT_ID',
    ),
  }) => GoogleProviderSdkGateway._(serverClientId);

  GoogleProviderSdkGateway._(this._serverClientId);

  final String _serverClientId;
  Future<void>? _initialization;

  @override
  Future<String?> signIn() async {
    try {
      await _initialize();
      final account = await GoogleSignIn.instance.authenticate();
      return account.authentication.idToken;
    } on GoogleSignInException catch (error) {
      final type = switch (error.code) {
        GoogleSignInExceptionCode.canceled ||
        GoogleSignInExceptionCode.interrupted =>
          ProviderSdkFailureType.cancelled,
        GoogleSignInExceptionCode.clientConfigurationError ||
        GoogleSignInExceptionCode.providerConfigurationError =>
          ProviderSdkFailureType.configuration,
        _ => ProviderSdkFailureType.rejected,
      };
      throw _sdkFailure('google', type, error);
    } on ProviderSdkFailure {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw _sdkFailure(
        'google',
        ProviderSdkFailureType.rejected,
        error,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _initialize();
      await GoogleSignIn.instance.signOut();
    } on ProviderSdkFailure {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw _sdkFailure(
        'google',
        ProviderSdkFailureType.rejected,
        error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _initialize() {
    if (_serverClientId.isEmpty ||
        _serverClientId.startsWith('your-') ||
        _serverClientId.startsWith('missing-')) {
      throw _sdkFailure('google', ProviderSdkFailureType.configuration, null);
    }
    return _initialization ??= GoogleSignIn.instance.initialize(
      serverClientId: _serverClientId,
    );
  }
}

/// Naver Login SDK에서 Naver Access Token을 발급받는다.
final class NaverProviderSdkGateway implements ProviderSdkGateway {
  factory NaverProviderSdkGateway({
    MethodChannel androidChannel = const MethodChannel(
      'com.dodam.app/naver_oauth',
    ),
    bool? useAndroidBridge,
  }) => NaverProviderSdkGateway._(
    androidChannel,
    useAndroidBridge ??
        (!kIsWeb && defaultTargetPlatform == TargetPlatform.android),
  );

  NaverProviderSdkGateway._(this._androidChannel, this._useAndroidBridge);

  final MethodChannel _androidChannel;
  final bool _useAndroidBridge;

  @override
  Future<String?> signIn() async {
    try {
      if (_useAndroidBridge) {
        return _androidChannel.invokeMethod<String>('login');
      }
      final result = await FlutterNaverLogin.logIn();
      return switch (result.status) {
        NaverLoginStatus.loggedIn => result.accessToken?.accessToken,
        NaverLoginStatus.loggedOut => throw _sdkFailure(
          'naver',
          ProviderSdkFailureType.cancelled,
          null,
        ),
        NaverLoginStatus.error => throw _sdkFailure(
          'naver',
          failureTypeForErrorMessage(result.errorMessage),
          null,
        ),
      };
    } on PlatformException catch (error) {
      final code = error.code.toUpperCase();
      throw _sdkFailure(
        'naver',
        code.contains('CANCEL')
            ? ProviderSdkFailureType.cancelled
            : ProviderSdkFailureType.rejected,
        error,
      );
    } on ProviderSdkFailure {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw _sdkFailure(
        'naver',
        ProviderSdkFailureType.rejected,
        error,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Future<void> signOut() async {
    try {
      if (_useAndroidBridge) {
        await _androidChannel.invokeMethod<void>('logout');
        return;
      }
      await FlutterNaverLogin.logOutAndDeleteToken();
    } on Object catch (error, stackTrace) {
      throw _sdkFailure(
        'naver',
        ProviderSdkFailureType.rejected,
        error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Naver iOS SDK가 오류 상태로 반환하는 사용자 취소를 구분한다.
  @visibleForTesting
  static ProviderSdkFailureType failureTypeForErrorMessage(String? message) {
    final normalized = message?.toLowerCase() ?? '';
    return normalized.contains('cancel')
        ? ProviderSdkFailureType.cancelled
        : ProviderSdkFailureType.rejected;
  }
}
