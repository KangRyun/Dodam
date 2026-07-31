import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../../../core/network/network.dart';
import '../data/dto/drawing_dtos.dart';
import '../domain/repositories/drawing_repository.dart';
import 'drawing_sync_coordinator.dart';

typedef DraftImageProviderFactory =
    ImageProvider<Object> Function(Uint8List bytes);

enum DrawingDraftRestoreStatus {
  unavailable,
  loading,
  noDraft,
  found,
  loadingImage,
  restored,
  queryFailed,
  imageFailed,
  newDrawing,
}

final class DrawingDraftRestoreController extends ChangeNotifier {
  DrawingDraftRestoreController({
    required this.sessionId,
    required this.repository,
    required this.syncCoordinator,
    DraftImageProviderFactory? imageProviderFactory,
  }) : _imageProviderFactory =
           imageProviderFactory ?? ((bytes) => MemoryImage(bytes)),
       _status = sessionId == null || repository == null
           ? DrawingDraftRestoreStatus.unavailable
           : DrawingDraftRestoreStatus.loading;

  final int? sessionId;
  final DrawingRepository? repository;
  final DrawingSyncCoordinator syncCoordinator;
  final DraftImageProviderFactory _imageProviderFactory;

  DrawingDraftRestoreStatus _status;
  DraftRecoveryDto? _draft;
  ImageProvider<Object>? _backgroundImage;
  Object? _failure;
  bool _canRetry = false;
  Future<void>? _loadInFlight;
  Future<void>? _imageInFlight;
  int _generation = 0;
  bool _disposed = false;

  DrawingDraftRestoreStatus get status => _status;
  DraftRecoveryDto? get draft => _draft;
  ImageProvider<Object>? get backgroundImage => _backgroundImage;
  Object? get failure => _failure;
  bool get canRetry => _canRetry;
  bool get canDraw => switch (_status) {
    DrawingDraftRestoreStatus.unavailable ||
    DrawingDraftRestoreStatus.noDraft ||
    DrawingDraftRestoreStatus.restored ||
    DrawingDraftRestoreStatus.newDrawing => true,
    _ => false,
  };

  Future<void> load({bool autoRestore = false}) {
    if (_disposed) return Future.value();
    final existing = _loadInFlight;
    if (existing != null) return existing;
    final id = sessionId;
    final dataSource = repository;
    if (id == null || dataSource == null) return Future.value();
    final generation = ++_generation;
    final future = _load(
      generation: generation,
      capturedSessionId: id,
      dataSource: dataSource,
      autoRestore: autoRestore,
    );
    _loadInFlight = future;
    return future.whenComplete(() {
      if (identical(_loadInFlight, future)) _loadInFlight = null;
    });
  }

  Future<void> _load({
    required int generation,
    required int capturedSessionId,
    required DrawingRepository dataSource,
    required bool autoRestore,
  }) async {
    _failure = null;
    _canRetry = false;
    _setStatus(DrawingDraftRestoreStatus.loading);
    try {
      final result = await dataSource.getDraft(capturedSessionId);
      if (!_isCurrent(generation, capturedSessionId)) return;
      if (result == null) {
        _draft = null;
        _setStatus(DrawingDraftRestoreStatus.noDraft);
        return;
      }
      _draft = result;
      syncCoordinator.resumeEventSequenceFromDraft(
        result.canvasState.lastEventSequence,
      );
      // 이벤트 시퀀스뿐 아니라 획 배치 시퀀스도 복원해야 이어그리기 첫 배치가
      // 이미 저장된 batchSequence=1과 충돌(DRAWING_409_019)하지 않는다.
      syncCoordinator.resumeBatchSequenceFromDraft(
        result.canvasState.lastEventSequence,
      );
      _setStatus(DrawingDraftRestoreStatus.found);
      if (autoRestore) {
        await _loadPreview(
          generation: generation,
          capturedSessionId: capturedSessionId,
          capturedDraft: result,
          dataSource: dataSource,
        );
      }
    } on ApiResponseFailure catch (failure) {
      if (!_isCurrent(generation, capturedSessionId)) return;
      if (failure.error?.code == 'DRAWING_404_004') {
        _draft = null;
        _setStatus(DrawingDraftRestoreStatus.noDraft);
      } else {
        _failure = failure;
        _canRetry = ApiFailurePresentation.of(failure).canRetry;
        _setStatus(DrawingDraftRestoreStatus.queryFailed);
      }
    } on Object catch (error) {
      if (!_isCurrent(generation, capturedSessionId)) return;
      _failure = error;
      _canRetry = _isRetryable(error);
      _setStatus(DrawingDraftRestoreStatus.queryFailed);
    }
  }

  Future<void> continueDrawing() {
    if (_disposed) return Future.value();
    final existing = _imageInFlight;
    if (existing != null) return existing;
    final capturedDraft = _draft;
    final capturedSessionId = sessionId;
    final dataSource = repository;
    if (capturedDraft == null ||
        capturedSessionId == null ||
        dataSource == null) {
      _canRetry = false;
      _setStatus(DrawingDraftRestoreStatus.imageFailed);
      return Future.value();
    }
    final generation = ++_generation;
    final future = _loadPreview(
      generation: generation,
      capturedSessionId: capturedSessionId,
      capturedDraft: capturedDraft,
      dataSource: dataSource,
    );
    _imageInFlight = future;
    return future.whenComplete(() {
      if (identical(_imageInFlight, future)) _imageInFlight = null;
    });
  }

  Future<void> _loadPreview({
    required int generation,
    required int capturedSessionId,
    required DraftRecoveryDto capturedDraft,
    required DrawingRepository dataSource,
  }) async {
    final url = capturedDraft.previewUrl;
    if (url.isEmpty) {
      if (_isCurrentDraft(generation, capturedSessionId, capturedDraft)) {
        _failure = const FormatException('Draft preview URL is empty.');
        _canRetry = false;
        _setStatus(DrawingDraftRestoreStatus.imageFailed);
      }
      return;
    }
    _failure = null;
    _canRetry = false;
    _setStatus(DrawingDraftRestoreStatus.loadingImage);
    try {
      final bytes = await dataSource.downloadDraftPreview(url);
      if (!_isCurrentDraft(generation, capturedSessionId, capturedDraft)) {
        return;
      }
      _backgroundImage = _imageProviderFactory(bytes);
      _safeNotify();
    } on Object catch (error) {
      if (!_isCurrentDraft(generation, capturedSessionId, capturedDraft)) {
        return;
      }
      _failure = error;
      _canRetry = _isRetryable(error);
      _backgroundImage = null;
      _setStatus(DrawingDraftRestoreStatus.imageFailed);
    }
  }

  /// 대화 단계에서 완성 그림을 배경으로만 복원한다.
  ///
  /// 입력 가능 여부는 화면의 단계 잠금이 결정하며 이 메서드는 파일 조회만 맡는다.
  Future<void> loadReadOnlyImage(String fileUrl) async {
    if (_disposed) return;
    final dataSource = repository;
    if (fileUrl.isEmpty || dataSource == null) return;
    final capturedSessionId = sessionId;
    if (capturedSessionId == null) return;
    final generation = ++_generation;
    _failure = null;
    _canRetry = false;
    _setStatus(DrawingDraftRestoreStatus.loadingImage);
    try {
      final bytes = await dataSource.downloadDraftPreview(fileUrl);
      if (!_isCurrent(generation, capturedSessionId)) return;
      _backgroundImage = _imageProviderFactory(bytes);
      _safeNotify();
    } on Object catch (error) {
      if (!_isCurrent(generation, capturedSessionId)) return;
      _failure = error;
      _canRetry = _isRetryable(error);
      _backgroundImage = null;
      _setStatus(DrawingDraftRestoreStatus.imageFailed);
    }
  }

  void markImageLoaded() {
    if (_disposed) return;
    if (_status == DrawingDraftRestoreStatus.loadingImage) {
      _setStatus(DrawingDraftRestoreStatus.restored);
    }
  }

  void markImageFailed() {
    if (_disposed) return;
    if (_status == DrawingDraftRestoreStatus.loadingImage) {
      _failure = const FormatException('Draft preview could not be decoded.');
      _canRetry = false;
      _backgroundImage = null;
      _setStatus(DrawingDraftRestoreStatus.imageFailed);
    }
  }

  Future<void> retryImage() => continueDrawing();

  void startNewDrawing() {
    if (_disposed) return;
    _generation += 1;
    _loadInFlight = null;
    _imageInFlight = null;
    _failure = null;
    _canRetry = false;
    _draft = null;
    _backgroundImage = null;
    // 이 화면 안에서는 기존 active session을 폐기할 안전한 원자 계약이 없다.
    // Child home의 "새로 그리기"는 replaceActive 세션 생성 성공 뒤 서버가 기존
    // 세션을 ABANDONED로 바꾸므로, 여기서는 복구 요청만 무효화하고 삭제하지 않는다.
    _setStatus(DrawingDraftRestoreStatus.newDrawing);
  }

  bool _isCurrent(int generation, int capturedSessionId) =>
      !_disposed && generation == _generation && capturedSessionId == sessionId;

  bool _isCurrentDraft(
    int generation,
    int capturedSessionId,
    DraftRecoveryDto capturedDraft,
  ) =>
      _isCurrent(generation, capturedSessionId) &&
      identical(_draft, capturedDraft) &&
      _draft?.assetVersion == capturedDraft.assetVersion &&
      _draft?.canvasState.lastEventSequence ==
          capturedDraft.canvasState.lastEventSequence;

  bool _isRetryable(Object error) =>
      error is! FormatException && ApiFailurePresentation.of(error).canRetry;

  void _setStatus(DrawingDraftRestoreStatus value) {
    if (_disposed) return;
    _status = value;
    _safeNotify();
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation += 1;
    _loadInFlight = null;
    _imageInFlight = null;
    super.dispose();
  }
}
