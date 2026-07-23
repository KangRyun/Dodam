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
}
