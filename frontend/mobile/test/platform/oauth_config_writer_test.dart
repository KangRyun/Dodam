import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/configure_oauth.dart';

void main() {
  const completeValues = {
    'KAKAO_NATIVE_APP_KEY': 'test-kakao-key',
    'GOOGLE_IOS_CLIENT_ID': 'test-google-ios-client-id',
    'GOOGLE_SERVER_CLIENT_ID': 'test-google-server-client-id',
    'GOOGLE_REVERSED_CLIENT_ID': 'test-google-reversed-client-id',
    'NAVER_CLIENT_ID': 'test-naver-client-id',
    'NAVER_CLIENT_SECRET': 'test-naver-client-secret',
    'NAVER_APP_NAME': 'Dodam',
    'NAVER_URL_SCHEME': 'dodamnaver',
  };

  test('placeholder 또는 누락된 OAuth 설정을 거부한다', () {
    expect(
      () => validateOAuthValues({
        ...completeValues,
        'KAKAO_NATIVE_APP_KEY': 'your-kakao-native-app-key',
        'NAVER_CLIENT_ID': '',
      }, androidOAuthVariableNames),
      throwsA(
        isA<StateError>()
            .having(
              (error) => error.message,
              'message',
              contains('KAKAO_NATIVE_APP_KEY'),
            )
            .having(
              (error) => error.message,
              'message',
              contains('NAVER_CLIENT_ID'),
            )
            .having(
              (error) => error.message,
              'message',
              isNot(contains('your-kakao-native-app-key')),
            ),
      ),
    );
  });

  test('플랫폼별 로컬 설정 파일을 생성한다', () async {
    final projectRoot = await Directory.systemTemp.createTemp(
      'dodam-oauth-config-',
    );
    addTearDown(() => projectRoot.delete(recursive: true));

    final writtenFiles = await writeOAuthConfiguration(
      projectRoot: projectRoot,
      values: completeValues,
      target: OAuthTarget.all,
    );

    final androidFile = File(
      '${projectRoot.path}${Platform.pathSeparator}android'
      '${Platform.pathSeparator}oauth.properties',
    );
    final iosFile = File(
      '${projectRoot.path}${Platform.pathSeparator}ios'
      '${Platform.pathSeparator}Flutter'
      '${Platform.pathSeparator}OAuth.xcconfig',
    );
    final dartDefinesFile = File(
      '${projectRoot.path}${Platform.pathSeparator}oauth_defines.json',
    );

    expect(
      writtenFiles,
      containsAll([dartDefinesFile.path, androidFile.path, iosFile.path]),
    );
    expect(await androidFile.readAsString(), contains('NAVER_APP_NAME=Dodam'));
    expect(
      await androidFile.readAsString(),
      isNot(contains('GOOGLE_IOS_CLIENT_ID')),
    );
    expect(
      await iosFile.readAsString(),
      contains('GOOGLE_IOS_CLIENT_ID=test-google-ios-client-id'),
    );
    expect(
      await dartDefinesFile.readAsString(),
      contains('"GOOGLE_SERVER_CLIENT_ID": "test-google-server-client-id"'),
    );
  });
}
