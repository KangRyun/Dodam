import 'package:flutter/foundation.dart';

import '../../child/data/dto/child_dtos.dart';

typedef CanvasTutorialProgressLoader =
    Future<TutorialProgressDto> Function(int childId);
typedef CanvasTutorialProgressSaver =
    Future<TutorialProgressDto> Function(
      int childId,
      UpdateTutorialRequestDto request,
    );

enum CanvasTutorialStep {
  pen('PEN'),
  eraser('ERASER'),
  color('COLOR'),
  thickness('THICKNESS'),
  undoRedo('UNDO_REDO'),
  complete('COMPLETE');

  const CanvasTutorialStep(this.code);

  final String code;

  static CanvasTutorialStep fromCode(String? code) =>
      values.where((step) => step.code == code).firstOrNull ?? pen;
}

/// Canvas 도구 안내의 서버 진행 상태와 화면 단계를 함께 관리한다.
///
/// 완료·건너뛴 튜토리얼을 다시 보는 경우에는 서버의 종료 상태를 되돌릴 수
/// 없으므로 로컬 재생으로만 처리한다. 네트워크 오류는 안내에만 반영하며 실제
/// Canvas 입력을 잠그지 않는다.
final class CanvasTutorialController extends ChangeNotifier {
  CanvasTutorialController({
    required this.childId,
    required this.loadProgress,
    required this.saveProgress,
  });

  final int childId;
  final CanvasTutorialProgressLoader loadProgress;
  final CanvasTutorialProgressSaver saveProgress;

  CanvasTutorialStep _step = CanvasTutorialStep.pen;
  bool _isVisible = false;
  bool _isBusy = false;
  bool _replayOnly = false;
  bool _loadFailed = false;
  Object? _error;
  UpdateTutorialRequestDto? _pendingRequest;
  VoidCallback? _pendingSuccess;
  bool _disposed = false;

  CanvasTutorialStep get step => _step;
  bool get isVisible => _isVisible;
  bool get isBusy => _isBusy;
  bool get hasError => _error != null;
  Object? get error => _error;

  /// 안내 API의 상태와 무관하게 실제 그림 입력은 항상 허용한다.
  bool get blocksCanvas => false;

  Future<void> load() async {
    if (_isBusy) return;
    _isBusy = true;
    _error = null;
    _loadFailed = false;
    _notify();
    try {
      final progress = await loadProgress(childId);
      switch (progress.tutorialStatus) {
        case 'NOT_STARTED':
          await _save(
            const UpdateTutorialRequestDto(
              tutorialStatus: 'IN_PROGRESS',
              lastStep: 'PEN',
            ),
          );
          _step = CanvasTutorialStep.pen;
          _replayOnly = false;
          _isVisible = true;
        case 'IN_PROGRESS':
          _step = CanvasTutorialStep.fromCode(progress.lastStep);
          _replayOnly = false;
          _isVisible = true;
        case 'COMPLETED' || 'SKIPPED':
          _step = CanvasTutorialStep.pen;
          _replayOnly = true;
          _isVisible = false;
        default:
          throw FormatException(
            'Unsupported tutorial status: ${progress.tutorialStatus}',
          );
      }
    } on Object catch (error) {
      _error = error;
      _loadFailed = true;
      _replayOnly = true;
      _isVisible = true;
    } finally {
      _isBusy = false;
      _notify();
    }
  }

  Future<void> retry() {
    if (_loadFailed) return load();
    final request = _pendingRequest;
    final onSuccess = _pendingSuccess;
    if (request == null || onSuccess == null) return Future<void>.value();
    return _runSave(request, onSuccess: onSuccess);
  }

  void replay() {
    if (_isBusy) return;
    _step = CanvasTutorialStep.pen;
    _error = null;
    _loadFailed = false;
    _replayOnly = true;
    _pendingRequest = null;
    _pendingSuccess = null;
    _isVisible = true;
    _notify();
  }

  Future<void> next() async {
    if (_isBusy || !_isVisible || hasError && _loadFailed) return;
    if (_step == CanvasTutorialStep.complete) {
      await _close('COMPLETED');
      return;
    }
    final nextStep = CanvasTutorialStep.values[_step.index + 1];
    await _moveTo(nextStep);
  }

  Future<void> previous() async {
    if (_isBusy || !_isVisible || _step == CanvasTutorialStep.pen) return;
    await _moveTo(CanvasTutorialStep.values[_step.index - 1]);
  }

  Future<void> skip() => _close('SKIPPED');

  void continueDrawing() {
    if (_isBusy) return;
    _error = null;
    _loadFailed = false;
    _pendingRequest = null;
    _pendingSuccess = null;
    _isVisible = false;
    _notify();
  }

  Future<void> _moveTo(CanvasTutorialStep target) async {
    if (_replayOnly) {
      _step = target;
      _error = null;
      _notify();
      return;
    }
    await _runSave(
      UpdateTutorialRequestDto(
        tutorialStatus: 'IN_PROGRESS',
        lastStep: target.code,
      ),
      onSuccess: () => _step = target,
    );
  }

  Future<void> _close(String status) async {
    if (_isBusy || !_isVisible) return;
    if (_replayOnly) {
      _error = null;
      _isVisible = false;
      _notify();
      return;
    }
    await _runSave(
      UpdateTutorialRequestDto(tutorialStatus: status, lastStep: _step.code),
      onSuccess: () => _isVisible = false,
    );
  }

  Future<void> _runSave(
    UpdateTutorialRequestDto request, {
    required VoidCallback onSuccess,
  }) async {
    _isBusy = true;
    _error = null;
    _pendingRequest = request;
    _pendingSuccess = onSuccess;
    _notify();
    try {
      await _save(request);
      onSuccess();
      _pendingRequest = null;
      _pendingSuccess = null;
    } on Object catch (error) {
      _error = error;
      _loadFailed = false;
    } finally {
      _isBusy = false;
      _notify();
    }
  }

  Future<TutorialProgressDto> _save(UpdateTutorialRequestDto request) =>
      saveProgress(childId, request);

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
