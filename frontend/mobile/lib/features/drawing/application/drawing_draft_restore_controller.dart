import 'package:flutter/widgets.dart';

import '../../../core/network/network.dart';
import '../data/dto/drawing_dtos.dart';
import '../domain/repositories/drawing_repository.dart';
import 'drawing_sync_coordinator.dart';

typedef DraftImageProviderFactory = ImageProvider<Object> Function(String url);

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
           imageProviderFactory ??
           ((url) => NetworkImage(url) as ImageProvider<Object>),
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
      _setStatus(DrawingDraftRestoreStatus.found);
    } on ApiResponseFailure catch (failure) {
      if (failure.error?.code == 'DRAWING_DRAFT_NOT_FOUND') {
        _draft = null;
        _setStatus(DrawingDraftRestoreStatus.noDraft);
      } else {
        _setStatus(DrawingDraftRestoreStatus.queryFailed);
      }
    } on Object {
      _setStatus(DrawingDraftRestoreStatus.queryFailed);
    }
  }

  void continueDrawing() {
    final url = _draft?.previewUrl;
    if (url == null || url.isEmpty) {
      _setStatus(DrawingDraftRestoreStatus.imageFailed);
      return;
    }
    _backgroundImage = _imageProviderFactory(url);
    _setStatus(DrawingDraftRestoreStatus.loadingImage);
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

  void retryImage() => continueDrawing();

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
