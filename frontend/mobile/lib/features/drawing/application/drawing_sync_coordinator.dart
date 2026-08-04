import 'dart:async';
import 'dart:math';
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

const int kMaxDraftPreviewBytes = 10 * 1024 * 1024;

final class _DraftPreviewTooLargeFailure implements Exception {
  const _DraftPreviewTooLargeFailure();
}

String _createDraftIdempotencyKey() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((value) => value.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
      '${hex.substring(20)}';
}

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
    this.maxDraftProcessingRetries = 2,
    this.draftProcessingBackoff = const Duration(milliseconds: 300),
  });

  final int eventThreshold;
  final Duration flushInterval;

  /// API detail recommends about 30 seconds. Lifecycle and route boundaries
  /// trigger an explicit save independently of this periodic interval.
  final Duration autosaveInterval;
  final int maxRetryAttempts;

  /// Backend가 같은 요청을 처리 중이라고 응답할 때 추가로 시도할 최대 횟수.
  ///
  /// 최초 요청을 포함하면 기본값은 총 3회이며, 상한 뒤에는 동일 snapshot을
  /// 수동 재시도용으로 보존한다.
  final int maxDraftProcessingRetries;
  final Duration draftProcessingBackoff;
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

final class _DraftSaveAttempt {
  const _DraftSaveAttempt({
    required this.idempotencyKey,
    required this.preview,
    required this.canvasState,
    required this.generation,
    required this.documentRevision,
  });

  final String idempotencyKey;
  final BinaryUploadDto preview;
  final DraftCanvasStateDto canvasState;
  final int generation;

  /// 이 시도가 담고 있는 문서 변경 횟수다. 이벤트를 만들지 않는 변경까지 세므로
  /// 저장 성공 시 어디까지 반영됐는지 이벤트 순서만으로 판단하지 않아도 된다.
  final int documentRevision;
}

BinaryUploadDto _immutablePreview(BinaryUploadDto preview) => BinaryUploadDto(
  bytes: List<int>.unmodifiable(preview.bytes),
  fileName: preview.fileName,
  mimeType: preview.mimeType,
);

DraftCanvasStateDto _immutableCanvasState(DraftCanvasStateDto canvasState) =>
    DraftCanvasStateDto(
      lastEventSequence: canvasState.lastEventSequence,
      toolState: _immutableJsonMap(canvasState.toolState),
      viewport: _immutableJsonMap(canvasState.viewport),
      clientSavedAt: canvasState.clientSavedAt,
    );

Map<String, dynamic>? _immutableJsonMap(Map<String, dynamic>? source) =>
    source == null
    ? null
    : Map<String, dynamic>.unmodifiable({
        for (final entry in source.entries)
          entry.key: _immutableJsonValue(entry.value),
      });

Object? _immutableJsonValue(Object? value) => switch (value) {
  Map<String, dynamic>() => _immutableJsonMap(value),
  Map() => Map<Object?, Object?>.unmodifiable({
    for (final entry in value.entries)
      entry.key: _immutableJsonValue(entry.value),
  }),
  List() => List<Object?>.unmodifiable(value.map(_immutableJsonValue)),
  _ => value,
};

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
  Future<void>? _drainFuture;
  bool _disposed = false;

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
  Object? get failure => _queue
      .where(
        (batch) =>
            batch.status == StrokeBatchQueueStatus.failedRetryable ||
            batch.status == StrokeBatchQueueStatus.failedPermanent,
      )
      .firstOrNull
      ?.failure;
  bool get canRetryFailure =>
      !_disposed &&
      _queue.firstOrNull?.status == StrokeBatchQueueStatus.failedRetryable &&
      (_queue.firstOrNull?.attempts ?? policy.maxRetryAttempts) <
          policy.maxRetryAttempts;

  bool resumeBatchSequence(int nextValue) {
    if (nextValue < 0) throw ArgumentError.value(nextValue, 'nextValue');
    if (_buffer.isNotEmpty || _queue.isNotEmpty || _completed.isNotEmpty) {
      return false;
    }
    _nextBatchSequence = nextValue;
    return true;
  }

  void addEvents(Iterable<StrokeEventDto> events) {
    if (_disposed) return;
    _buffer.addAll(events);
    onChanged?.call();
    if (_buffer.length >= policy.eventThreshold) unawaited(flush());
  }

  Future<void> flush() async {
    if (_disposed) return;
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
    if (_disposed) return;
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

  Future<void> _drain() {
    if (_disposed) return Future.value();
    final existing = _drainFuture;
    if (existing != null) return existing;
    if (sessionId == null || sender == null) return Future.value();
    final completer = Completer<void>();
    _drainFuture = completer.future;
    unawaited(
      _drainLoop().then(
        (_) => completer.complete(),
        onError: completer.completeError,
      ),
    );
    return completer.future.whenComplete(() {
      if (!_disposed && identical(_drainFuture, completer.future)) {
        _drainFuture = null;
      }
    });
  }

  Future<void> _drainLoop() async {
    while (!_disposed && _queue.isNotEmpty) {
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
        if (_disposed) return;
        final success = sending.copyWith(
          status: StrokeBatchQueueStatus.success,
        );
        _completed.add(success);
        _queue.removeAt(0);
        onChanged?.call();
      } on Object catch (error) {
        if (_disposed) return;
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
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    onChanged = null;
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
    String Function()? idempotencyKeyProvider,
  }) : journal = journal ?? DrawingEventJournal(),
       _now = now ?? DateTime.now,
       _idempotencyKeyProvider =
           idempotencyKeyProvider ?? _createDraftIdempotencyKey {
    batchQueue = StrokeBatchQueue(
      sessionId: sessionId,
      sender: repository == null
          ? null
          : (id, request) => repository!.sendStrokeBatch(id, request),
      policy: policy,
      now: _now,
      onChanged: null,
    );
    batchQueue.onChanged = _notifyFromQueue;
  }

  final int? sessionId;
  final DrawingRepository? repository;
  final DrawingSyncPolicy policy;
  final DrawingEventJournal journal;
  final DateTime Function() _now;
  final String Function() _idempotencyKeyProvider;
  late final StrokeBatchQueue batchQueue;

  Timer? _flushTimer;
  Timer? _autosaveTimer;
  Future<BinaryUploadDto?> Function()? _snapshotProvider;
  DraftSaveResponseDto? _latestDraftResponse;
  DrawingSaveStatus _draftStatus = DrawingSaveStatus.localOnly;
  Object? _draftFailure;
  bool _draftFailureRetryable = false;
  _DraftSaveAttempt? _failedAttempt;
  Future<DraftSaveResponseDto?>? _saveInFlight;
  int _dirtyGeneration = 0;
  int _savedGeneration = 0;
  int _failedGeneration = 0;
  int? _savedEventSequence;
  int _documentRevision = 0;
  int _savedDocumentRevision = 0;
  bool _started = false;
  bool _paused = false;
  bool _stopped = false;
  bool _completing = false;
  bool _disposed = false;

  /// 지금까지 캔버스 문서에 일어난 변경 횟수다.
  ///
  /// 획뿐 아니라 채우기·영역 지우개·전체 지우기처럼 그림 이벤트를 만들지 않는 변경도
  /// 센다. 이벤트 순서만으로는 이런 변경을 구분할 수 없어 저장 여부 판단에 함께 쓴다.
  int get documentRevision => _documentRevision;

  /// 서버에 아직 반영되지 않은 캔버스 변경이 남아 있는지 여부다.
  bool get hasUnsavedSnapshot => _savedDocumentRevision < _documentRevision;

  int get elapsedMilliseconds => journal.elapsedMilliseconds;
  bool get isDisposed => _disposed;
  bool get isCompleting => _completing;
  bool get canRetrySave => batchQueue.hasFailure
      ? batchQueue.canRetryFailure
      : _draftStatus == DrawingSaveStatus.failed && _draftFailureRetryable;
  Object? get saveFailure => batchQueue.failure ?? _draftFailure;

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
    if (batchQueue.hasFailure ||
        (_draftStatus == DrawingSaveStatus.failed &&
            _failedGeneration >= _dirtyGeneration)) {
      return DrawingSaveStatus.failed;
    }
    if (_draftStatus == DrawingSaveStatus.saving || batchQueue.isSending) {
      return DrawingSaveStatus.saving;
    }
    if (_draftStatus == DrawingSaveStatus.saved &&
        _savedGeneration >= _dirtyGeneration) {
      return DrawingSaveStatus.saved;
    }
    return DrawingSaveStatus.localOnly;
  }

  void start({required Future<BinaryUploadDto?> Function() snapshotProvider}) {
    if (_disposed) return;
    _snapshotProvider = snapshotProvider;
    _started = true;
    _paused = false;
    _stopped = false;
    _completing = false;
    _startTimers();
  }

  void _startTimers() {
    if (_disposed || !_started || _paused || _stopped) return;
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

  /// lifecycle background 동안 주기 callback만 멈춘다.
  ///
  /// 호출부는 이 메서드 뒤에 [flushAndSaveDraft]를 시작하고, resumed에서
  /// [resume]을 호출한다. 진행 중 요청은 single-flight loop가 끝까지 관리한다.
  void pause() {
    if (_disposed || _stopped) return;
    _paused = true;
    _cancelTimers();
  }

  void resume() {
    if (_disposed || _stopped || !_started) return;
    _paused = false;
    _startTimers();
  }

  /// 자동 저장과 주기 전송을 멈춘다.
  ///
  /// 그림 단계가 끝난 뒤에는 서버가 초안·획 저장을 받지 않으므로(409) 타이머를
  /// 남겨두면 실패만 반복한다.
  void stop() {
    _stopped = true;
    _completing = true;
    _paused = false;
    _cancelTimers();
  }

  /// 새 Draft 저장을 막고 완료 이전에 시작된 저장 하나가 끝날 때까지 기다린다.
  Future<void> beginCompletion() async {
    if (_disposed || _stopped) return;
    _completing = true;
    pause();
    final saving = _saveInFlight;
    if (saving != null) await saving;
  }

  /// 완료 API가 실패했을 때 명시적 저장 차단만 해제한다.
  void cancelCompletion() {
    if (_disposed || _stopped) return;
    _completing = false;
  }

  void _cancelTimers() {
    _flushTimer?.cancel();
    _flushTimer = null;
    _autosaveTimer?.cancel();
    _autosaveTimer = null;
  }

  List<StrokeEventDto> recordStroke(DrawingStroke stroke, Size canvasSize) {
    final events = journal.recordStroke(stroke, canvasSize);
    batchQueue.addEvents(events);
    if (events.isNotEmpty) _markDirty();
    return events;
  }

  StrokeEventDto? recordUndo() {
    final event = journal.recordUndo();
    if (event != null) {
      batchQueue.addEvents([event]);
      _markDirty();
    }
    return event;
  }

  StrokeEventDto? recordRedo() {
    final event = journal.recordRedo();
    if (event != null) {
      batchQueue.addEvents([event]);
      _markDirty();
    }
    return event;
  }

  /// 그림 이벤트를 만들지 않는 문서 변경을 저장 대상으로 기록한다.
  ///
  /// 채우기·영역 지우개·전체 지우기는 journal event 없이 캔버스 이미지만 바꾸므로,
  /// 이벤트 순서가 그대로여도 새 초안을 올려야 한다. 가짜 event를 만들지 않고
  /// 문서 revision만 올려 replay cutoff 의미를 지킨다.
  void recordSnapshotChange() {
    if (_disposed) return;
    _markDirty();
  }

  void _markDirty() {
    _dirtyGeneration += 1;
    _documentRevision += 1;
    if (_draftStatus == DrawingSaveStatus.saved) {
      _draftStatus = DrawingSaveStatus.localOnly;
    }
    _safeNotify();
  }

  Future<void> flushEvents() => batchQueue.flush();

  /// 완료용 snapshot을 만들기 전에 모든 완결 event batch가 서버에 도착했는지 확인한다.
  Future<bool> flushStrokeBatches() async {
    if (_disposed) return false;
    final saving = _saveInFlight;
    if (saving != null) await saving;
    if (_disposed) return false;
    await batchQueue.flush();
    return !batchQueue.hasFailure;
  }

  /// stroke batch를 먼저 보낸 뒤 같은 event sequence의 Draft를 저장한다.
  Future<bool> flushAndSaveDraft() async {
    if (_disposed || _stopped || _completing) return false;
    if (journal.events.isEmpty && !hasUnsavedSnapshot) return true;
    await saveDraftNow();
    if (_disposed || batchQueue.hasFailure) return false;
    return _savedEventSequence == journal.lastEventSequence;
  }

  Future<DraftSaveResponseDto?> saveDraftNow() {
    if (_disposed ||
        _stopped ||
        _completing ||
        sessionId == null ||
        repository == null ||
        _snapshotProvider == null ||
        // 채우기·전체 지우기는 event 없이 그림만 바꾼다. event 유무만 보면 이런
        // 변경이 영영 저장되지 않으므로 스냅샷 변경도 저장 사유로 인정한다.
        (journal.events.isEmpty && !hasUnsavedSnapshot)) {
      return Future.value(null);
    }
    final existing = _saveInFlight;
    if (existing != null) return existing;
    if (_draftStatus == DrawingSaveStatus.failed &&
        _dirtyGeneration <= _failedGeneration) {
      return Future.value(null);
    }
    return _startSaveLoop();
  }

  Future<void> retry() async {
    if (_disposed || _stopped || _completing || !canRetrySave) return;
    await batchQueue.retryHead();
    if (_disposed || batchQueue.hasFailure) return;
    final failedAttempt = _failedAttempt;
    if (_draftStatus == DrawingSaveStatus.failed &&
        _draftFailureRetryable &&
        failedAttempt != null) {
      await _startSaveLoop(retryAttempt: failedAttempt);
    } else if (_draftStatus == DrawingSaveStatus.failed &&
        _draftFailureRetryable) {
      _failedAttempt = null;
      _failedGeneration = 0;
      await _startSaveLoop();
    } else {
      await saveDraftNow();
    }
  }

  Future<DraftSaveResponseDto?> _startSaveLoop({
    _DraftSaveAttempt? retryAttempt,
  }) {
    final existing = _saveInFlight;
    if (existing != null) return existing;
    final completer = Completer<DraftSaveResponseDto?>();
    _saveInFlight = completer.future;
    unawaited(
      _runSaveLoop(
        retryAttempt: retryAttempt,
      ).then(completer.complete, onError: completer.completeError),
    );
    return completer.future.whenComplete(() {
      if (identical(_saveInFlight, completer.future)) {
        _saveInFlight = null;
      }
    });
  }

  Future<DraftSaveResponseDto?> _runSaveLoop({
    _DraftSaveAttempt? retryAttempt,
  }) async {
    DraftSaveResponseDto? latest = _latestDraftResponse;
    var retainedAttempt = retryAttempt;
    while (!_disposed) {
      if (retainedAttempt case final attempt?) {
        retainedAttempt = null;
        final response = await _uploadAttempt(attempt);
        if (response == null || _disposed) {
          if (!_disposed &&
              _draftFailureRetryable &&
              _dirtyGeneration > attempt.generation) {
            continue;
          }
          return response;
        }
        latest = response;
        if (_dirtyGeneration <= attempt.generation) return latest;
        continue;
      }

      if (_dirtyGeneration <= _savedGeneration &&
          _savedEventSequence == journal.lastEventSequence &&
          !hasUnsavedSnapshot) {
        return latest;
      }

      await batchQueue.flush();
      if (_disposed || batchQueue.hasFailure) return null;

      final generation = _dirtyGeneration;
      final documentRevision = _documentRevision;
      // 이벤트가 하나도 없는 문서는 replay cutoff가 0이다. 채우기만 한 문서도 이
      // 값으로 저장·복원할 수 있으며 가짜 event를 만들지 않는다.
      final lastEventSequence = journal.lastEventSequence ?? 0;
      if (_savedEventSequence == lastEventSequence && !hasUnsavedSnapshot) {
        _savedGeneration = generation;
        _draftStatus = DrawingSaveStatus.saved;
        _safeNotify();
        return latest;
      }

      BinaryUploadDto? preview;
      try {
        preview = await _snapshotProvider!();
      } on Object catch (error) {
        _recordDraftFailure(error, generation: generation);
        return null;
      }
      if (_disposed) return null;
      if (_dirtyGeneration != generation) {
        // snapshot을 만드는 동안 새 stroke가 끝났다면 sequence와 이미지의 경계를
        // 추측하지 않고 최신 batch flush부터 다시 시작한다.
        continue;
      }
      if (preview == null) return null;

      final attempt = _DraftSaveAttempt(
        idempotencyKey: _idempotencyKeyProvider(),
        preview: _immutablePreview(preview),
        canvasState: _immutableCanvasState(
          DraftCanvasStateDto(
            lastEventSequence: lastEventSequence,
            toolState: null,
            viewport: null,
            clientSavedAt: _now().toUtc().toIso8601String(),
          ),
        ),
        generation: generation,
        documentRevision: documentRevision,
      );
      final response = await _uploadAttempt(attempt);
      if (response == null || _disposed) {
        if (!_disposed &&
            _draftFailureRetryable &&
            _dirtyGeneration > generation) {
          continue;
        }
        return response;
      }
      latest = response;
      if (_dirtyGeneration <= generation) return latest;
    }
    return latest;
  }

  Future<DraftSaveResponseDto?> _uploadAttempt(
    _DraftSaveAttempt attempt,
  ) async {
    if (_disposed || sessionId == null || repository == null) return null;
    if (attempt.preview.bytes.length > kMaxDraftPreviewBytes) {
      _recordDraftFailure(
        const _DraftPreviewTooLargeFailure(),
        generation: attempt.generation,
        attempt: attempt,
      );
      return null;
    }
    _draftFailure = null;
    _draftFailureRetryable = false;
    _draftStatus = DrawingSaveStatus.saving;
    _safeNotify();
    var processingRetries = 0;
    while (!_disposed) {
      try {
        final response = await repository!.saveDraft(
          sessionId!,
          attempt.preview,
          attempt.canvasState,
          idempotencyKey: attempt.idempotencyKey,
        );
        if (_disposed) return null;
        _latestDraftResponse = response;
        _savedGeneration = attempt.generation;
        _savedEventSequence = attempt.canvasState.lastEventSequence;
        if (_savedDocumentRevision < attempt.documentRevision) {
          _savedDocumentRevision = attempt.documentRevision;
        }
        _failedAttempt = null;
        _failedGeneration = 0;
        _draftFailure = null;
        _draftFailureRetryable = false;
        _draftStatus = DrawingSaveStatus.saved;
        _safeNotify();
        return response;
      } on Object catch (error) {
        final canRetryProcessing =
            _isDraftSaveInProgress(error) &&
            processingRetries < policy.maxDraftProcessingRetries &&
            !_stopped &&
            !_completing;
        if (canRetryProcessing) {
          processingRetries += 1;
          await Future<void>.delayed(
            _draftProcessingRetryDelay(processingRetries),
          );
          if (_disposed) return null;
          if (!_stopped && !_completing) continue;
        }
        if (!_disposed && _isDraftSequenceConflict(error)) {
          await _inspectLatestDraftAfterConflict();
        }
        if (!_disposed) {
          _recordDraftFailure(
            error,
            generation: attempt.generation,
            attempt: attempt,
          );
        }
        return null;
      }
    }
    return null;
  }

  Duration _draftProcessingRetryDelay(int retryNumber) => Duration(
    microseconds: policy.draftProcessingBackoff.inMicroseconds * retryNumber,
  );

  bool _isDraftSaveInProgress(Object error) =>
      _draftErrorCode(error) == 'DRAFT_SAVE_IN_PROGRESS';

  bool _isDraftSequenceConflict(Object error) =>
      _draftErrorCode(error) == 'DRAWING_409_009' ||
      _draftErrorCode(error) == 'DRAWING_409_010';

  String? _draftErrorCode(Object error) =>
      error is ApiResponseFailure ? error.error?.code : null;

  Future<void> _inspectLatestDraftAfterConflict() async {
    if (_disposed || sessionId == null || repository == null) return;
    try {
      // Draft GET에는 저장소 checksum이 없고 Backend가 preview를 재인코딩하므로
      // sequence/size만으로 성공 처리하지 않는다. 최신 metadata 조회는 충돌
      // 진단과 향후 서버 fingerprint 계약 연결을 위한 안전한 경계로만 사용한다.
      await repository!.getDraft(sessionId!);
    } on Object {
      // Reconciliation 조회 실패도 원래 PUT 409를 성공으로 바꾸지 않는다.
    }
  }

  void _recordDraftFailure(
    Object error, {
    required int generation,
    _DraftSaveAttempt? attempt,
  }) {
    if (_disposed) return;
    _draftFailure = error;
    _draftFailureRetryable = _isDraftFailureRetryable(error);
    _failedAttempt = attempt;
    _failedGeneration = generation;
    _draftStatus = DrawingSaveStatus.failed;
    _safeNotify();
  }

  bool _isDraftFailureRetryable(Object error) {
    if (error is _DraftPreviewTooLargeFailure) return false;
    if (error case ApiTransportFailure(
      type: ApiTransportFailureType.cancelled,
    )) {
      // 자동 재시도하지 않지만 사용자가 다시 시도하면 같은 snapshot을 쓴다.
      return true;
    }
    return switch (_draftErrorCode(error)) {
      'DRAFT_SAVE_IN_PROGRESS' => true,
      'IDEMPOTENCY_KEY_REUSED' ||
      'DRAWING_400_003' ||
      'DRAWING_400_004' ||
      'DRAWING_409_009' ||
      'DRAWING_409_010' => false,
      _ => ApiFailurePresentation.of(error).canRetry,
    };
  }

  void _notifyFromQueue() => _safeNotify();

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    batchQueue.dispose();
    batchQueue.onChanged = null;
    _cancelTimers();
    super.dispose();
  }
}
