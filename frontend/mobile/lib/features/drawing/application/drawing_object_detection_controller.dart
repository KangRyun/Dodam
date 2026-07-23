import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/dto/drawing_dtos.dart';

typedef DraftSaveForDetection = Future<DraftSaveResponseDto?> Function();
typedef ObjectDetectionRequester =
    Future<ObjectDetectionResponseDto> Function(int drawingAssetId);

enum DrawingObjectDetectionStatus {
  idle,
  waiting,
  saving,
  requesting,
  succeeded,
  failed,
}

/// 그림 입력 중단부터 최신 자동 저장본의 객체 탐지까지 조율한다.
final class DrawingObjectDetectionController extends ChangeNotifier {
  DrawingObjectDetectionController({
    required this.saveDraft,
    required this.requestDetection,
    this.debounceDuration = const Duration(seconds: 3),
  });

  final DraftSaveForDetection saveDraft;
  final ObjectDetectionRequester requestDetection;
  final Duration debounceDuration;

  final Set<int> _requestedAssetIds = {};
  Timer? _debounceTimer;
  int _inputGeneration = 0;
  int? _latestDrawingAssetId;
  DrawingObjectDetectionStatus _status = DrawingObjectDetectionStatus.idle;
  ObjectDetectionResponseDto? _validResult;
  Object? _failure;

  DrawingObjectDetectionStatus get status => _status;
  int? get latestDrawingAssetId => _latestDrawingAssetId;
  ObjectDetectionResponseDto? get validResult => _validResult;
  Object? get failure => _failure;

  /// 새 그림 입력은 대기 중 요청과 이전 비동기 결과를 무효화한다.
  void onDrawingInputStarted() {
    _inputGeneration += 1;
    _debounceTimer?.cancel();
    _latestDrawingAssetId = null;
    _validResult = null;
    _failure = null;
    _setStatus(DrawingObjectDetectionStatus.idle);
  }

  /// 마지막 입력 이후 3초 동안 추가 입력이 없을 때 탐지 흐름을 시작한다.
  void onDrawingInputEnded() {
    _debounceTimer?.cancel();
    final generation = _inputGeneration;
    _setStatus(DrawingObjectDetectionStatus.waiting);
    _debounceTimer = Timer(
      debounceDuration,
      () => unawaited(_saveAndDetect(generation)),
    );
  }

  Future<void> _saveAndDetect(int generation) async {
    if (generation != _inputGeneration) return;
    _setStatus(DrawingObjectDetectionStatus.saving);

    DraftSaveResponseDto? draft;
    try {
      draft = await saveDraft();
    } on Object catch (error) {
      _handleFailure(generation, error);
      return;
    }
    if (generation != _inputGeneration) return;
    if (draft == null) {
      _handleFailure(generation, StateError('DRAFT_SAVE_FAILED'));
      return;
    }

    final assetId = draft.drawingAssetId;
    _latestDrawingAssetId = assetId;
    if (_requestedAssetIds.contains(assetId)) {
      _setStatus(DrawingObjectDetectionStatus.idle);
      return;
    }

    // 요청 전에 기록해 같은 자동 저장본의 동시·반복 요청을 막는다.
    _requestedAssetIds.add(assetId);
    _setStatus(DrawingObjectDetectionStatus.requesting);
    try {
      final result = await requestDetection(assetId);
      if (generation != _inputGeneration) return;
      if (result.drawingAssetId != _latestDrawingAssetId) {
        _handleFailure(generation, StateError('STALE_ANALYSIS_RESULT'));
        return;
      }
      _validResult = result;
      _failure = null;
      _setStatus(DrawingObjectDetectionStatus.succeeded);
    } on Object catch (error) {
      _handleFailure(generation, error);
    }
  }

  void _handleFailure(int generation, Object error) {
    if (generation != _inputGeneration) return;
    _failure = error;
    _setStatus(DrawingObjectDetectionStatus.failed);
  }

  void _setStatus(DrawingObjectDetectionStatus value) {
    if (_status == value) return;
    _status = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }
}
