import 'dart:convert';
import 'dart:io';

enum OAuthTarget { android, ios, all }

const androidOAuthVariableNames = [
  'KAKAO_NATIVE_APP_KEY',
  'GOOGLE_SERVER_CLIENT_ID',
  'NAVER_CLIENT_ID',
  'NAVER_CLIENT_SECRET',
  'NAVER_APP_NAME',
];

const dartDefineOAuthVariableNames = [
  'KAKAO_NATIVE_APP_KEY',
  'GOOGLE_SERVER_CLIENT_ID',
];

const iosOAuthVariableNames = [
  'KAKAO_NATIVE_APP_KEY',
  'GOOGLE_IOS_CLIENT_ID',
  'GOOGLE_SERVER_CLIENT_ID',
  'GOOGLE_REVERSED_CLIENT_ID',
  'NAVER_CLIENT_ID',
  'NAVER_CLIENT_SECRET',
  'NAVER_APP_NAME',
  'NAVER_URL_SCHEME',
];

void validateOAuthValues(
  Map<String, String> values,
  Iterable<String> requiredNames,
) {
  final invalidNames = requiredNames.where((name) {
    final value = values[name]?.trim() ?? '';
    return value.isEmpty ||
        value.startsWith('your-') ||
        value.startsWith('missing-') ||
        value.contains(r'$(') ||
        value.contains('\n') ||
        value.contains('\r');
  }).toList();

  if (invalidNames.isNotEmpty) {
    throw StateError('OAuth 설정이 누락되었거나 유효하지 않습니다: ${invalidNames.join(', ')}');
  }
}

String renderAndroidOAuthProperties(Map<String, String> values) =>
    '${androidOAuthVariableNames.map((name) => '$name=${values[name]!.trim()}').join('\n')}\n';

String renderIosOAuthXcconfig(Map<String, String> values) =>
    '${iosOAuthVariableNames.map((name) => '$name=${values[name]!.trim()}').join('\n')}\n';

String renderOAuthDartDefines(Map<String, String> values) =>
    '${const JsonEncoder.withIndent('  ').convert({for (final name in dartDefineOAuthVariableNames) name: values[name]!.trim()})}\n';

Future<List<String>> writeOAuthConfiguration({
  required Directory projectRoot,
  required Map<String, String> values,
  required OAuthTarget target,
}) async {
  final writtenFiles = <String>[];
  validateOAuthValues(values, dartDefineOAuthVariableNames);
  final dartDefinesFile = File(
    '${projectRoot.path}${Platform.pathSeparator}oauth_defines.json',
  );
  await dartDefinesFile.writeAsString(renderOAuthDartDefines(values));
  writtenFiles.add(dartDefinesFile.path);

  if (target == OAuthTarget.android || target == OAuthTarget.all) {
    validateOAuthValues(values, androidOAuthVariableNames);
    final androidFile = File(
      '${projectRoot.path}${Platform.pathSeparator}android'
      '${Platform.pathSeparator}oauth.properties',
    );
    await androidFile.parent.create(recursive: true);
    await androidFile.writeAsString(renderAndroidOAuthProperties(values));
    writtenFiles.add(androidFile.path);
  }

  if (target == OAuthTarget.ios || target == OAuthTarget.all) {
    validateOAuthValues(values, iosOAuthVariableNames);
    final iosFile = File(
      '${projectRoot.path}${Platform.pathSeparator}ios'
      '${Platform.pathSeparator}Flutter'
      '${Platform.pathSeparator}OAuth.xcconfig',
    );
    await iosFile.parent.create(recursive: true);
    await iosFile.writeAsString(renderIosOAuthXcconfig(values));
    writtenFiles.add(iosFile.path);
  }

  return writtenFiles;
}

OAuthTarget parseTarget(List<String> arguments) {
  final platformArgument = arguments
      .where((argument) => argument.startsWith('--platform='))
      .firstOrNull;
  final platform = platformArgument?.substring('--platform='.length) ?? 'all';

  return switch (platform) {
    'android' => OAuthTarget.android,
    'ios' => OAuthTarget.ios,
    'all' => OAuthTarget.all,
    _ => throw const FormatException(
      '--platform은 android, ios, all 중 하나여야 합니다.',
    ),
  };
}

Future<void> main(List<String> arguments) async {
  try {
    final target = parseTarget(arguments);
    await writeOAuthConfiguration(
      projectRoot: Directory.current,
      values: Platform.environment,
      target: target,
    );
    stdout.writeln('OAuth 설정 파일 생성 완료.');
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    exitCode = 64;
  } on StateError catch (error) {
    stderr.writeln(error.message);
    exitCode = 64;
  }
}
