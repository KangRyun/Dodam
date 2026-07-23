import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android와 iOS 애플리케이션 식별자는 com.dodam.app이다', () {
    final androidGradle =
        File('android/app/build.gradle.kts').readAsStringSync();
    final iosProject =
        File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();

    expect(androidGradle, contains('namespace = "com.dodam.app"'));
    expect(androidGradle, contains('applicationId = "com.dodam.app"'));
    expect(
      iosProject,
      contains('PRODUCT_BUNDLE_IDENTIFIER = com.dodam.app;'),
    );
  });

  test('OAuth Native 설정은 외부 값 참조와 Provider URL Scheme을 제공한다', () {
    final androidGradle =
        File('android/app/build.gradle.kts').readAsStringSync();
    final androidManifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final androidActivity =
        File(
          'android/app/src/main/kotlin/com/dodam/app/MainActivity.kt',
        ).readAsStringSync();
    final iosInfo = File('ios/Runner/Info.plist').readAsStringSync();
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
    expect(gitignore, contains('/android/oauth.properties'));
    expect(gitignore, contains('/ios/Flutter/OAuth.xcconfig'));
  });

  test('Repository에는 실제 OAuth Credential 값이 포함되지 않는다', () {
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
}
