import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

class _NoAnimations implements AccessibilityFeatures {
  const _NoAnimations();

  @override
  bool get autoPlayAnimatedImages => true;

  @override
  bool get autoPlayVideos => true;

  @override
  bool get deterministicCursor => false;

  @override
  bool get supportsAnnounce => true;

  @override
  bool get accessibleNavigation => false;

  @override
  bool get boldText => false;

  @override
  bool get disableAnimations => true;

  @override
  bool get highContrast => false;

  @override
  bool get invertColors => false;

  @override
  bool get onOffSwitchLabels => false;

  @override
  bool get reduceMotion => false;
}

/// 로그인 화면 브랜드 패널의 무한 플로팅 애니메이션이 `pumpAndSettle`을
/// 막지 않도록, 테스트 동안 reduce-motion(애니메이션 비활성)을 적용한다.
void useReducedMotionForTests() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    binding.platformDispatcher.accessibilityFeaturesTestValue =
        const _NoAnimations();
  });
  tearDown(() {
    binding.platformDispatcher.clearAccessibilityFeaturesTestValue();
  });
}
