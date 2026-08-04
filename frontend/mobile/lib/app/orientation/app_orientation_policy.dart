import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

typedef PreferredOrientationsSetter =
    Future<void> Function(List<DeviceOrientation> orientations);
typedef OrientationErrorReporter =
    void Function(Object error, StackTrace stackTrace);

/// 앱 전체에 적용되는 가로 화면 정책(S15P11B209-878).
///
/// 모든 production route가 같은 정책을 사용하므로 route별 복원 스택은 두지
/// 않는다. 외부 picker·설정 화면을 다녀오며 플랫폼 방향 상태가 달라질 수 있는
/// lifecycle 구간만 추적하고, 복귀 시 두 가로 방향을 다시 허용한다.
final class AppOrientationPolicy with WidgetsBindingObserver {
  AppOrientationPolicy({
    PreferredOrientationsSetter? setPreferredOrientations,
    OrientationErrorReporter? reportError,
  }) : _setPreferredOrientations =
           setPreferredOrientations ?? SystemChrome.setPreferredOrientations,
       _reportError = reportError ?? _logError;

  static const landscapeOrientations = <DeviceOrientation>[
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ];

  final PreferredOrientationsSetter _setPreferredOrientations;
  final OrientationErrorReporter _reportError;

  bool _observing = false;
  bool _disposed = false;
  bool _needsApplication = true;
  bool _awaitingResume = false;
  int _generation = 0;
  Future<_OrientationAttempt>? _inFlight;

  /// lifecycle 관찰을 시작하고 첫 화면 전에 전역 가로 정책을 적용한다.
  ///
  /// 플랫폼 호출 실패는 [false]로 반환하고 기록한다. 예외를 다시 던지지 않아
  /// 앱 시작과 navigation은 계속 진행할 수 있다.
  Future<bool> start() {
    if (_disposed) return Future<bool>.value(false);
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
    return ensureLandscape();
  }

  /// 필요할 때만 가로 정책을 적용한다.
  ///
  /// 같은 generation의 동시 요청은 하나의 플랫폼 호출을 공유한다. 호출 중
  /// background 전환이 발생하면 오래된 완료가 최신 상태를 applied로 만들지
  /// 못하며, 이어진 resume 요청이 새 generation을 적용한다.
  Future<bool> ensureLandscape() async {
    if (_disposed) return false;
    if (!_needsApplication) return true;

    final running = _inFlight;
    if (running != null) {
      final result = await running;
      if (_disposed) return false;
      if (!_needsApplication) return true;
      if (!result.succeeded && result.generation == _generation) return false;
    }

    if (_disposed) return false;
    if (!_needsApplication) return true;

    final generation = _generation;
    final attempt = _apply(generation);
    _inFlight = attempt;
    final result = await attempt;
    if (identical(_inFlight, attempt)) _inFlight = null;
    return result.succeeded &&
        !_disposed &&
        !_needsApplication &&
        result.generation == _generation;
  }

  /// 외부 화면 또는 background 진입으로 플랫폼 상태를 다시 확인해야 함을 표시한다.
  /// inactive → paused → hidden 연속 통지는 한 번의 generation으로 합친다.
  void markPlatformStateUncertain() {
    if (_disposed || _awaitingResume) return;
    _awaitingResume = true;
    _needsApplication = true;
    _generation += 1;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed) return;
    switch (state) {
      case AppLifecycleState.resumed:
        _awaitingResume = false;
        unawaited(ensureLandscape());
        return;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        markPlatformStateUncertain();
        return;
    }
  }

  Future<_OrientationAttempt> _apply(int generation) async {
    try {
      await _setPreferredOrientations(landscapeOrientations);
      if (!_disposed && generation == _generation) {
        _needsApplication = false;
      }
      return _OrientationAttempt(generation: generation, succeeded: true);
    } on Object catch (error, stackTrace) {
      if (!_disposed) _reportError(error, stackTrace);
      return _OrientationAttempt(generation: generation, succeeded: false);
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation += 1;
    if (_observing) {
      WidgetsBinding.instance.removeObserver(this);
      _observing = false;
    }
  }

  static void _logError(Object error, StackTrace stackTrace) {
    developer.log(
      '가로 화면 정책 적용 실패 — 현재 화면을 유지하고 다음 복귀 때 재시도한다',
      name: 'orientation',
      error: error,
      stackTrace: stackTrace,
    );
  }
}

final class _OrientationAttempt {
  const _OrientationAttempt({
    required this.generation,
    required this.succeeded,
  });

  final int generation;
  final bool succeeded;
}
