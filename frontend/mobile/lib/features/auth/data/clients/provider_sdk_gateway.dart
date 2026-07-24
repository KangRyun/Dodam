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

/// Provider별 Native SDK 호출을 Login Client에서 분리하는 경계다.
abstract interface class ProviderSdkGateway {
  Future<String?> signIn();

  Future<void> signOut();
}

/// Kakao Flutter SDK를 초기화하고 Kakao Access Token을 발급받는다.
final class KakaoProviderSdkGateway implements ProviderSdkGateway {
  factory KakaoProviderSdkGateway({
    String nativeAppKey = const String.fromEnvironment('KAKAO_NATIVE_APP_KEY'),
  }) => KakaoProviderSdkGateway._(nativeAppKey);

  KakaoProviderSdkGateway._(this._nativeAppKey);

  final String _nativeAppKey;
  Future<void>? _initialization;

  @override
  Future<String?> signIn() async {
    try {
      await _initialize();
      final token = await ((await isKakaoTalkInstalled())
          ? UserApi.instance.loginWithKakaoTalk()
          : UserApi.instance.loginWithKakaoAccount());
      return token.accessToken;
    } on KakaoClientException catch (error) {
      throw ProviderSdkFailure(
        error.reason == ClientErrorCause.cancelled
            ? ProviderSdkFailureType.cancelled
            : ProviderSdkFailureType.rejected,
        cause: error,
      );
    } on ProviderSdkFailure {
      rethrow;
    } on Object catch (error) {
      throw ProviderSdkFailure(ProviderSdkFailureType.rejected, cause: error);
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _initialize();
      await UserApi.instance.logout();
    } on ProviderSdkFailure {
      rethrow;
    } on Object catch (error) {
      throw ProviderSdkFailure(ProviderSdkFailureType.rejected, cause: error);
    }
  }

  Future<void> _initialize() {
    if (_nativeAppKey.isEmpty ||
        _nativeAppKey.startsWith('your-') ||
        _nativeAppKey.startsWith('missing-')) {
      throw const ProviderSdkFailure(ProviderSdkFailureType.configuration);
    }
    return _initialization ??= KakaoSdk.init(
      nativeAppKey: _nativeAppKey,
      loggingEnabled: false,
    );
  }
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
      throw ProviderSdkFailure(type, cause: error);
    } on ProviderSdkFailure {
      rethrow;
    } on Object catch (error) {
      throw ProviderSdkFailure(ProviderSdkFailureType.rejected, cause: error);
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _initialize();
      await GoogleSignIn.instance.signOut();
    } on ProviderSdkFailure {
      rethrow;
    } on Object catch (error) {
      throw ProviderSdkFailure(ProviderSdkFailureType.rejected, cause: error);
    }
  }

  Future<void> _initialize() {
    if (_serverClientId.isEmpty ||
        _serverClientId.startsWith('your-') ||
        _serverClientId.startsWith('missing-')) {
      throw const ProviderSdkFailure(ProviderSdkFailureType.configuration);
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
        NaverLoginStatus.loggedOut => throw const ProviderSdkFailure(
          ProviderSdkFailureType.cancelled,
        ),
        NaverLoginStatus.error => throw ProviderSdkFailure(
          failureTypeForErrorMessage(result.errorMessage),
        ),
      };
    } on PlatformException catch (error) {
      final code = error.code.toUpperCase();
      throw ProviderSdkFailure(
        code.contains('CANCEL')
            ? ProviderSdkFailureType.cancelled
            : ProviderSdkFailureType.rejected,
        cause: error,
      );
    } on ProviderSdkFailure {
      rethrow;
    } on Object catch (error) {
      throw ProviderSdkFailure(ProviderSdkFailureType.rejected, cause: error);
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
    } on Object catch (error) {
      throw ProviderSdkFailure(ProviderSdkFailureType.rejected, cause: error);
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
