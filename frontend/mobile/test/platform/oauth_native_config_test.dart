import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android와 iOS 애플리케이션 식별자는 com.dodam.app이다', () {
    final androidGradle = File(
      'android/app/build.gradle.kts',
    ).readAsStringSync();
    final iosProject = File(
      'ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();

    expect(androidGradle, contains('namespace = "com.dodam.app"'));
    expect(androidGradle, contains('applicationId = "com.dodam.app"'));
    expect(iosProject, contains('PRODUCT_BUNDLE_IDENTIFIER = com.dodam.app;'));
  });

  test('OAuth Native 설정은 외부 값 참조와 Provider URL Scheme을 제공한다', () {
    final androidGradle = File(
      'android/app/build.gradle.kts',
    ).readAsStringSync();
    final androidManifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final androidActivity = File(
      'android/app/src/main/kotlin/com/dodam/app/MainActivity.kt',
    ).readAsStringSync();
    final iosInfo = File('ios/Runner/Info.plist').readAsStringSync();
    final sceneDelegate = File(
      'ios/Runner/SceneDelegate.swift',
    ).readAsStringSync();
    final gitignore = File('.gitignore').readAsStringSync();

    expect(androidGradle, contains('KAKAO_NATIVE_APP_KEY'));
    expect(androidGradle, contains('NAVER_CLIENT_SECRET'));
    expect(androidManifest, contains(r'${kakaoScheme}'));
    expect(androidManifest, contains('AuthCodeHandlerActivity'));
    expect(androidManifest, contains(r'${naverClientId}'));
    expect(androidActivity, contains('FlutterFragmentActivity'));
    expect(iosInfo, contains(r'kakao$(KAKAO_NATIVE_APP_KEY)'));
    expect(iosInfo, contains(r'$(GOOGLE_REVERSED_CLIENT_ID)'));
    expect(iosInfo, contains(r'$(NAVER_URL_SCHEME)'));
    expect(sceneDelegate, contains('NidOAuth.shared.handleURL'));
    expect(gitignore, contains('/android/oauth.properties'));
    expect(gitignore, contains('/ios/Flutter/OAuth.xcconfig'));
    expect(gitignore, contains('/oauth_defines.json'));
  });

  test('OAuth 설정 예시는 실제 값 대신 명시적인 placeholder를 사용한다', () {
    final trackedExamples = [
      File('android/oauth.properties.example').readAsStringSync(),
      File('ios/Flutter/OAuth.xcconfig.example').readAsStringSync(),
    ].join('\n');

    expect(trackedExamples, contains('KAKAO_NATIVE_APP_KEY=your-'));
    expect(trackedExamples, contains('GOOGLE_IOS_CLIENT_ID=your-'));
    expect(trackedExamples, contains('GOOGLE_SERVER_CLIENT_ID=your-'));
    expect(trackedExamples, contains('NAVER_CLIENT_ID=your-'));
    expect(trackedExamples, contains('NAVER_CLIENT_SECRET=your-'));
    expect(trackedExamples, isNot(contains('apps.googleusercontent.com')));
  });

  test('README는 모바일 OAuth 로컬 설정과 iOS 빌드 제한을 안내한다', () {
    final readme = File('README.md').readAsStringSync();

    expect(readme, contains('android/oauth.properties.example'));
    expect(readme, contains('ios/Flutter/OAuth.xcconfig.example'));
    expect(readme, contains('com.dodam.app'));
    expect(readme, contains('macOS와 Xcode'));
    expect(readme, contains('Kakao·Naver Access Token과 Google ID Token'));
    expect(readme, contains('dart run tool/configure_oauth.dart'));
    expect(readme, contains('--dart-define-from-file=oauth_defines.json'));
  });

  test('모든 앱 빌드는 누락된 OAuth 설정을 허용하지 않는다', () {
    final androidGradle = File(
      'android/app/build.gradle.kts',
    ).readAsStringSync();
    final iosDebugConfig = File(
      'ios/Flutter/Debug.xcconfig',
    ).readAsStringSync();
    final iosReleaseConfig = File(
      'ios/Flutter/Release.xcconfig',
    ).readAsStringSync();

    expect(androidGradle, contains('preDebugBuild'));
    expect(androidGradle, contains('preReleaseBuild'));
    expect(androidGradle, contains('preProfileBuild'));
    expect(androidGradle, contains('requireOAuthValue'));
    expect(iosDebugConfig, contains('#include "OAuth.xcconfig"'));
    expect(iosDebugConfig, isNot(contains('#include? "OAuth.xcconfig"')));
    expect(iosReleaseConfig, contains('#include "OAuth.xcconfig"'));
    expect(iosReleaseConfig, isNot(contains('#include? "OAuth.xcconfig"')));
  });

  test('네이버 Android SDK는 Custom Tab callback 호환 버전을 사용한다', () {
    final androidGradle = File(
      'android/app/build.gradle.kts',
    ).readAsStringSync();

    expect(
      androidGradle,
      contains('implementation("com.navercorp.nid:oauth:5.11.2")'),
    );
  });

  test('네이버 OAuth Activity는 앱 전용 task affinity를 공유한다', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(
      manifest,
      contains(
        'android:name="com.navercorp.nid.oauth.activity.NidOAuthBridgeActivity"',
      ),
    );
    expect(
      manifest,
      contains(
        'android:name="com.navercorp.nid.oauth.activity.NidOAuthCustomTabActivity"',
      ),
    );
    expect(
      RegExp(
        r'android:taskAffinity="\$\{applicationId\}"',
      ).allMatches(manifest).length,
      3,
    );
  });

  test('Android Naver bridge는 초기화 완료와 lifecycle을 관리한다', () {
    final mainActivity = File(
      'android/app/src/main/kotlin/com/dodam/app/MainActivity.kt',
    ).readAsStringSync();

    expect(mainActivity, contains('NidOAuthInitializingCallback'));
    expect(mainActivity, contains('pendingLoginResult?.let'));
    expect(mainActivity, contains('cleanUpFlutterEngine'));
    expect(mainActivity, contains('NidOAuth.oauthLoginCallback = null'));
    expect(mainActivity, contains('NidOAuth.disconnect('));
  });

  test('Android 호환 Naver Plugin은 SDK를 중복 초기화하거나 설정값을 기록하지 않는다', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final pluginSource = File(
      'packages/flutter_naver_login/android/src/main/kotlin/'
      'com/example/flutter_naver_login/FlutterNaverLoginPlugin.kt',
    ).readAsStringSync();

    expect(pubspec, contains('path: packages/flutter_naver_login'));
    expect(pluginSource, isNot(contains('showDevelopersLog')));
    expect(pluginSource, isNot(contains('clientSecret')));
    expect(pluginSource, isNot(contains('MethodChannel')));
  });
}
