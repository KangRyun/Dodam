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
      final conversion = StrokeBatchEventConverter.convert(_buffer);
      if (conversion.events.isNotEmpty) {
        final events = List<StrokeBatchEventDto>.unmodifiable(
          conversion.events,
        );
        final request = StrokeBatchRequestDto(
          batchSequence: _nextBatchSequence++,
          firstEventSequence: events.first.sequence,
          lastEventSequence: events.last.sequence,
          clientCreatedAt: _now().toUtc().toIso8601String(),
          events: events,
          metrics: StrokeMetricsDto(
            undoCountDelta: conversion.undoCount,
            redoCountDelta: conversion.redoCount,
            eraseCountDelta: conversion.eraseCount,
          ),
        );
        _buffer.removeRange(0, conversion.consumedRawEventCount);
        _queue.add(
          QueuedStrokeBatch(
            request: request,
            status: StrokeBatchQueueStatus.pending,
          ),
        );
        // The complete request, including clientCreatedAt, is retained
        // unchanged for payload-checksum based retries.
        onChanged?.call();
      }
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

final class StrokeBatchConversion {
  const StrokeBatchConversion({
    required this.events,
    required this.consumedRawEventCount,
    required this.undoCount,
    required this.redoCount,
    required this.eraseCount,
  });

  final List<StrokeBatchEventDto> events;
  final int consumedRawEventCount;
  final int undoCount;
  final int redoCount;
  final int eraseCount;
}

abstract final class StrokeBatchEventConverter {
  static StrokeBatchConversion convert(List<StrokeEventDto> rawEvents) {
    final converted = <StrokeBatchEventDto>[];
    var undoCount = 0;
    var redoCount = 0;
    var eraseCount = 0;
    var index = 0;
    var previousSequence = 0;

    while (index < rawEvents.length) {
      final event = rawEvents[index];
      if (event.seq <= previousSequence) {
        throw StateError('Stroke event sequence must be strictly increasing.');
      }

      if (event.type == DrawingEventTypes.undo ||
          event.type == DrawingEventTypes.redo) {
        converted.add(
          StrokeBatchEventDto(
            sequence: event.seq,
            eventType: event.type,
            points: const [],
          ),
        );
        if (event.type == DrawingEventTypes.undo) {
          undoCount += 1;
        } else {
          redoCount += 1;
        }
        previousSequence = event.seq;
        index += 1;
        continue;
      }

      if (event.type != DrawingEventTypes.strokeStart) {
        throw StateError(
          'Stroke batch must start with STROKE_START, UNDO, or REDO.',
        );
      }

      final startIndex = index;
      var cursor = index + 1;
      while (cursor < rawEvents.length &&
          rawEvents[cursor].type == DrawingEventTypes.strokeMove) {
        if (rawEvents[cursor].seq <= rawEvents[cursor - 1].seq) {
          throw StateError(
            'Stroke event sequence must be strictly increasing.',
          );
        }
        cursor += 1;
      }

      if (cursor == rawEvents.length) {
        return StrokeBatchConversion(
          events: List.unmodifiable(converted),
          consumedRawEventCount: startIndex,
          undoCount: undoCount,
          redoCount: redoCount,
          eraseCount: eraseCount,
        );
      }

      final end = rawEvents[cursor];
      if (end.type != DrawingEventTypes.strokeEnd) {
        throw StateError(
          'Incomplete stroke cannot be followed by another event.',
        );
      }
      if (end.seq <= rawEvents[cursor - 1].seq) {
        throw StateError('Stroke event sequence must be strictly increasing.');
      }

      final stroke = _convertStroke(rawEvents.sublist(startIndex, cursor + 1));
      converted.add(stroke);
      if (stroke.tool == 'ERASER') eraseCount += 1;
      previousSequence = end.seq;
      index = cursor + 1;
    }

    return StrokeBatchConversion(
      events: List.unmodifiable(converted),
      consumedRawEventCount: index,
      undoCount: undoCount,
      redoCount: redoCount,
      eraseCount: eraseCount,
    );
  }

  static StrokeBatchEventDto _convertStroke(List<StrokeEventDto> events) {
    final start = events.first;
    final end = events.last;
    if ((start.tool != 'PEN' && start.tool != 'ERASER') ||
        (start.tool == 'PEN' && start.color == null) ||
        start.thickness == null ||
        start.thickness! <= 0) {
      throw StateError('STROKE_START must contain valid stroke attributes.');
    }

    final firstTime = start.t;
    var previousTime = firstTime;
    final points = <StrokePointDto>[];
    for (final event in events) {
      if (event.x == null || event.y == null || event.t < previousTime) {
        throw StateError(
          'Stroke points must have ordered coordinates and time.',
        );
      }
      points.add(
        StrokePointDto(
          x: event.x!,
          y: event.y!,
          t: event.t - firstTime,
          pressure: event.pressure,
        ),
      );
      previousTime = event.t;
    }

    return StrokeBatchEventDto(
      sequence: end.seq,
      eventType: 'STROKE',
      tool: start.tool,
      color: start.color,
      width: start.thickness,
      points: List.unmodifiable(points),
    );
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

  /// Draft 복원 시 획 배치 시퀀스를 서버에 이미 저장된 배치들 뒤로 옮긴다.
  ///
  /// 배치 시퀀스는 배치마다 1씩 증가하고 배치당 이벤트가 1개 이상이므로, 지금까지의
  /// 배치 수는 항상 `lastEventSequence` 이하다. 따라서 `lastEventSequence + 1`부터
  /// 시작하면 서버에 저장된 어떤 배치 번호와도 겹치지 않아 이어그리기 후 첫 배치가
  /// 재사용 충돌(DRAWING_409_019)로 실패하지 않는다. 서버는 배치 시퀀스의 갭을
  /// 허용하므로(유일성·checksum만 검사) 번호를 건너뛰어도 안전하다.
  bool resumeBatchSequenceFromDraft(int? lastEventSequence) =>
      lastEventSequence == null ||
      batchQueue.resumeBatchSequence(lastEventSequence + 1);

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

  /// 자동 저장과 주기 전송을 멈춘다.
  ///
  /// 그림 단계가 끝난 뒤에는 서버가 초안·획 저장을 받지 않으므로(409) 타이머를
  /// 남겨두면 실패만 반복한다.
  void stop() {
    _flushTimer?.cancel();
    _flushTimer = null;
    _autosaveTimer?.cancel();
    _autosaveTimer = null;
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

  StrokeEventDto? recordRedo() {
    final event = journal.recordRedo();
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
