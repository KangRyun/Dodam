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

  DrawingDraftRestoreStatus get status => _status;
  DraftRecoveryDto? get draft => _draft;
  ImageProvider<Object>? get backgroundImage => _backgroundImage;
  bool get canDraw => switch (_status) {
    DrawingDraftRestoreStatus.unavailable ||
    DrawingDraftRestoreStatus.noDraft ||
    DrawingDraftRestoreStatus.restored ||
    DrawingDraftRestoreStatus.newDrawing => true,
    _ => false,
  };

  Future<void> load() async {
    final id = sessionId;
    final dataSource = repository;
    if (id == null || dataSource == null) return;
    _setStatus(DrawingDraftRestoreStatus.loading);
    try {
      final result = await dataSource.getDraft(id);
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
    } on ApiResponseFailure catch (failure) {
      if (failure.error?.code == 'DRAWING_404_004') {
        _draft = null;
        _setStatus(DrawingDraftRestoreStatus.noDraft);
      } else {
        _setStatus(DrawingDraftRestoreStatus.queryFailed);
      }
    } on Object {
      _setStatus(DrawingDraftRestoreStatus.queryFailed);
    }
  }

  Future<void> continueDrawing() async {
    final url = _draft?.previewUrl;
    final dataSource = repository;
    if (url == null || url.isEmpty || dataSource == null) {
      _setStatus(DrawingDraftRestoreStatus.imageFailed);
      return;
    }
    _setStatus(DrawingDraftRestoreStatus.loadingImage);
    try {
      final bytes = await dataSource.downloadDraftPreview(url);
      _backgroundImage = _imageProviderFactory(bytes);
      notifyListeners();
    } on Object {
      _backgroundImage = null;
      _setStatus(DrawingDraftRestoreStatus.imageFailed);
    }
  }

  void markImageLoaded() {
    if (_status == DrawingDraftRestoreStatus.loadingImage) {
      _setStatus(DrawingDraftRestoreStatus.restored);
    }
  }

  void markImageFailed() {
    if (_status == DrawingDraftRestoreStatus.loadingImage) {
      _backgroundImage = null;
      _setStatus(DrawingDraftRestoreStatus.imageFailed);
    }
  }

  Future<void> retryImage() => continueDrawing();

  void startNewDrawing() {
    _backgroundImage = null;
    // TODO(API): Define whether starting over should delete the server Draft.
    _setStatus(DrawingDraftRestoreStatus.newDrawing);
  }

  void _setStatus(DrawingDraftRestoreStatus value) {
    _status = value;
    notifyListeners();
  }
}
