import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../../core/network/network.dart';
import '../data/dto/drawing_dtos.dart';
import '../domain/repositories/drawing_repository.dart';
import '../presentation/models/drawing_stroke.dart';
import 'drawing_event_journal.dart';

typedef StrokeBatchSender =
    Future<StrokeBatchResponseDto> Function(
      int sessionId,
      StrokeBatchRequestDto request,
    );

enum StrokeBatchQueueStatus {
  pending,
  sending,
  success,
  failedRetryable,
  failedPermanent,
}

enum DrawingSaveStatus { localOnly, saving, saved, failed }

final class DrawingSyncPolicy {
  const DrawingSyncPolicy({
    this.eventThreshold = 50,
    this.flushInterval = const Duration(seconds: 3),
    this.autosaveInterval = const Duration(seconds: 30),
    this.maxRetryAttempts = 3,
  });

  final int eventThreshold;
  final Duration flushInterval;

  /// API detail recommends about 30 seconds; the final product interval and
  /// lifecycle triggers remain TODO(API).
  final Duration autosaveInterval;
  final int maxRetryAttempts;
}

final class QueuedStrokeBatch {
  const QueuedStrokeBatch({
    required this.request,
    required this.status,
    this.attempts = 0,
    this.failure,
  });

  final StrokeBatchRequestDto request;
  final StrokeBatchQueueStatus status;
  final int attempts;
  final Object? failure;

  QueuedStrokeBatch copyWith({
    StrokeBatchQueueStatus? status,
    int? attempts,
    Object? failure,
  }) => QueuedStrokeBatch(
    request: request,
    status: status ?? this.status,
    attempts: attempts ?? this.attempts,
    failure: failure,
  );
}

abstract final class StrokeRetryPolicy {
  static bool isSuccessStatus(int statusCode) =>
      statusCode == 200 || statusCode == 201;

  static bool isRetryable(Object error) => switch (error) {
    ApiTransportFailure(type: ApiTransportFailureType.cancelled) => false,
    ApiTransportFailure() => true,
    ApiResponseFailure(statusCode: final code?) => code >= 500 && code < 600,
    _ => false,
  };
}

final class StrokeBatchQueue {
  StrokeBatchQueue({
    required this.sessionId,
    required this.sender,
    required this.policy,
    DateTime Function()? now,
    this.onChanged,
  }) : _now = now ?? DateTime.now;

  final int? sessionId;
  final StrokeBatchSender? sender;
  final DrawingSyncPolicy policy;
  final DateTime Function() _now;
  VoidCallback? onChanged;

  final List<StrokeEventDto> _buffer = [];
  final List<QueuedStrokeBatch> _queue = [];
  final List<QueuedStrokeBatch> _completed = [];
  int _nextBatchSequence = 1;
  bool _draining = false;

  List<StrokeEventDto> get bufferedEvents => List.unmodifiable(_buffer);
  List<QueuedStrokeBatch> get pendingBatches => List.unmodifiable(_queue);
  List<QueuedStrokeBatch> get completedBatches => List.unmodifiable(_completed);
  bool get isSending =>
      _queue.any((batch) => batch.status == StrokeBatchQueueStatus.sending);
  bool get hasFailure => _queue.any(
    (batch) =>
        batch.status == StrokeBatchQueueStatus.failedRetryable ||
        batch.status == StrokeBatchQueueStatus.failedPermanent,
  );

  bool resumeBatchSequence(int nextValue) {
    if (nextValue < 0) throw ArgumentError.value(nextValue, 'nextValue');
    if (_buffer.isNotEmpty || _queue.isNotEmpty || _completed.isNotEmpty) {
      return false;
    }
    _nextBatchSequence = nextValue;
    return true;
  }

  void addEvents(Iterable<StrokeEventDto> events) {
    _buffer.addAll(events);
    onChanged?.call();
    if (_buffer.length >= policy.eventThreshold) unawaited(flush());
  }

  Future<void> flush() async {
    if (_buffer.isNotEmpty) {
      final events = List<StrokeEventDto>.unmodifiable(_buffer);
      _buffer.clear();
      final request = StrokeBatchRequestDto(
        batchSequence: _nextBatchSequence++,
        firstEventSequence: events.first.seq,
        lastEventSequence: events.last.seq,
        clientCreatedAt: _now().toUtc().toIso8601String(),
        events: events,
      );
      _queue.add(
        QueuedStrokeBatch(
          request: request,
          status: StrokeBatchQueueStatus.pending,
        ),
      );
      // The request object is retained unchanged for idempotent retries.
      // TODO(BE): Revalidate the planned 409 for same sequence/different payload.
      onChanged?.call();
    }
    await _drain();
  }

  Future<void> retryHead() async {
    if (_queue.isEmpty) return;
    final head = _queue.first;
    if (head.status != StrokeBatchQueueStatus.failedRetryable ||
        head.attempts >= policy.maxRetryAttempts) {
      return;
    }
    _queue[0] = head.copyWith(status: StrokeBatchQueueStatus.pending);
    onChanged?.call();
    await _drain();
  }

  Future<void> _drain() async {
    if (_draining || sessionId == null || sender == null) return;
    _draining = true;
    try {
      while (_queue.isNotEmpty) {
        final head = _queue.first;
        if (head.status != StrokeBatchQueueStatus.pending) break;
        final sending = head.copyWith(
          status: StrokeBatchQueueStatus.sending,
          attempts: head.attempts + 1,
        );
        _queue[0] = sending;
        onChanged?.call();
        try {
          await sender!(sessionId!, sending.request);
          final success = sending.copyWith(
            status: StrokeBatchQueueStatus.success,
          );
          _completed.add(success);
          _queue.removeAt(0);
          onChanged?.call();
        } on Object catch (error) {
          _queue[0] = sending.copyWith(
            status: StrokeRetryPolicy.isRetryable(error)
                ? StrokeBatchQueueStatus.failedRetryable
                : StrokeBatchQueueStatus.failedPermanent,
            failure: error,
          );
          onChanged?.call();
          // Team-recommended policy: do not send N+1 before N succeeds.
          // TODO(BE): Revalidate against the implemented out-of-order behavior.
          break;
        }
      }
    } finally {
      _draining = false;
    }
  }
}

final class DrawingSyncCoordinator extends ChangeNotifier {
  DrawingSyncCoordinator({
    required this.sessionId,
    required this.repository,
    this.policy = const DrawingSyncPolicy(),
    DrawingEventJournal? journal,
    DateTime Function()? now,
  }) : journal = journal ?? DrawingEventJournal() {
    batchQueue = StrokeBatchQueue(
      sessionId: sessionId,
      sender: repository == null
          ? null
          : (id, request) => repository!.sendStrokeBatch(id, request),
      policy: policy,
      now: now,
      onChanged: null,
    );
    batchQueue.onChanged = _notifyFromQueue;
  }

  final int? sessionId;
  final DrawingRepository? repository;
  final DrawingSyncPolicy policy;
  final DrawingEventJournal journal;
  late final StrokeBatchQueue batchQueue;

  Timer? _flushTimer;
  Timer? _autosaveTimer;
  Future<BinaryUploadDto?> Function()? _snapshotProvider;
  BinaryUploadDto? _lastDraft;
  DraftCanvasStateDto? _lastDraftCanvasState;
  DraftSaveResponseDto? _latestDraftResponse;
  DrawingSaveStatus _draftStatus = DrawingSaveStatus.localOnly;

  int get elapsedMilliseconds => journal.elapsedMilliseconds;

  bool resumeEventSequenceFromDraft(int? lastEventSequence) =>
      lastEventSequence == null ||
      journal.resumeEventSequence(lastEventSequence + 1);

  DrawingSaveStatus get saveStatus {
    if (_draftStatus == DrawingSaveStatus.failed || batchQueue.hasFailure) {
      return DrawingSaveStatus.failed;
    }
    if (_draftStatus == DrawingSaveStatus.saving || batchQueue.isSending) {
      return DrawingSaveStatus.saving;
    }
    if (_draftStatus == DrawingSaveStatus.saved ||
        batchQueue.completedBatches.isNotEmpty) {
      return DrawingSaveStatus.saved;
    }
    return DrawingSaveStatus.localOnly;
  }

  void start({required Future<BinaryUploadDto?> Function() snapshotProvider}) {
    _snapshotProvider = snapshotProvider;
    _flushTimer ??= Timer.periodic(
      policy.flushInterval,
      (_) => unawaited(batchQueue.flush()),
    );
    if (sessionId != null && repository != null) {
      _autosaveTimer ??= Timer.periodic(
        policy.autosaveInterval,
        (_) => unawaited(saveDraftNow()),
      );
    }
  }

  List<StrokeEventDto> recordStroke(DrawingStroke stroke, Size canvasSize) {
    final events = journal.recordStroke(stroke, canvasSize);
    batchQueue.addEvents(events);
    return events;
  }

  StrokeEventDto? recordUndo() {
    final event = journal.recordUndo();
    if (event != null) batchQueue.addEvents([event]);
    return event;
  }

  Future<void> flushEvents() => batchQueue.flush();

  Future<DraftSaveResponseDto?> saveDraftNow() async {
    if (sessionId == null || repository == null || _snapshotProvider == null) {
      return null;
    }
    if (journal.events.isEmpty) return null;
    final lastEventSequence = journal.lastEventSequence;
    // 같은 그림 상태가 이미 저장됐다면 기존 자산을 재사용한다.
    if (_latestDraftResponse?.lastEventSequence == lastEventSequence) {
      return _latestDraftResponse;
    }
    BinaryUploadDto? image;
    try {
      image = await _snapshotProvider!();
    } on Object {
      _draftStatus = DrawingSaveStatus.failed;
      notifyListeners();
      return null;
    }
    if (image == null) return null;
    _lastDraft = image;
    _lastDraftCanvasState = DraftCanvasStateDto(
      lastEventSequence: lastEventSequence,
      toolState: null,
      viewport: null,
      clientSavedAt: DateTime.now().toUtc().toIso8601String(),
    );
    return _uploadLastDraft();
  }

  Future<void> retry() async {
    await batchQueue.retryHead();
    if (_draftStatus == DrawingSaveStatus.failed && _lastDraft != null) {
      await _uploadLastDraft();
    }
  }

  Future<DraftSaveResponseDto?> _uploadLastDraft() async {
    final image = _lastDraft;
    final canvasState = _lastDraftCanvasState;
    if (image == null ||
        canvasState == null ||
        sessionId == null ||
        repository == null) {
      return null;
    }
    _draftStatus = DrawingSaveStatus.saving;
    notifyListeners();
    // Draft v1.0은 획 묶음 순서 복원 계약과 독립적으로 저장한다.
    try {
      final response = await repository!.saveDraft(
        sessionId!,
        image,
        canvasState,
      );
      _latestDraftResponse = response;
      _draftStatus = DrawingSaveStatus.saved;
      notifyListeners();
      return response;
    } on Object {
      _draftStatus = DrawingSaveStatus.failed;
      notifyListeners();
      return null;
    }
  }

  void _notifyFromQueue() => notifyListeners();

  @override
  void dispose() {
    _flushTimer?.cancel();
    _autosaveTimer?.cancel();
    super.dispose();
  }
}
