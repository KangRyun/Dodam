import 'dart:ui';

import '../data/dto/drawing_dtos.dart';
import '../presentation/models/drawing_stroke.dart';

abstract final class DrawingEventTypes {
  static const strokeStart = 'STROKE_START';
  static const strokeMove = 'STROKE_MOVE';
  static const strokeEnd = 'STROKE_END';
  static const toolChange = 'TOOL_CHANGE';
  static const colorChange = 'COLOR_CHANGE';
  static const thicknessChange = 'THICKNESS_CHANGE';
  static const undo = 'UNDO';
  static const redo = 'REDO';
  static const canvasClear = 'CANVAS_CLEAR';
  static const fill = 'FILL';
  static const pause = 'PAUSE';
  static const resume = 'RESUME';

  /// 하나의 획을 이루는 세 종류다. 배치 변환기가 이것만 `STROKE` 하나로 합치고
  /// 나머지는 그대로 내보낸다.
  static bool isStrokePart(String type) =>
      type == strokeStart || type == strokeMove || type == strokeEnd;
}

final class SessionSequenceAllocator {
  /// Team default starts at 1 and increases session-wide. The start remains
  /// configurable because the unimplemented server currently only checks >= 0.
  SessionSequenceAllocator({int startValue = 1}) : _nextValue = startValue;

  int _nextValue;
  int get nextValue => _nextValue;

  int allocate() => _nextValue++;

  void resumeAt(int nextValue) {
    if (nextValue < 0) throw ArgumentError.value(nextValue, 'nextValue');
    _nextValue = nextValue;
  }
}

/// 아직 이벤트로 굳히지 않은 도구 설정 변경 하나다.
final class _PendingSetting<T> {
  const _PendingSetting(this.value, this.elapsedMilliseconds);

  final T value;
  final int elapsedMilliseconds;
}

final class DrawingEventJournal {
  DrawingEventJournal({
    SessionSequenceAllocator? sequenceAllocator,
    Stopwatch? sessionClock,
  }) : _sequenceAllocator = sequenceAllocator ?? SessionSequenceAllocator(),
       _sessionClock = sessionClock ?? (Stopwatch()..start());

  /// 이 시간 이상 캔버스 입력이 없으면 멈춤 한 번으로 본다.
  ///
  /// 백엔드 `StrokeBehaviorSummaryService.PAUSE_THRESHOLD_MS`와 같은 3초다. 팀이
  /// 확정한 값이고("다음에 뭘 그릴지 생각하는 멈춤"의 길이), 앱과 서버가 다른 값을
  /// 쓰면 같은 활동의 멈춤 횟수가 두 갈래로 갈린다. 획을 바꾸며 손을 떼는 정도의
  /// 짧은 간격은 이 값 아래라 오탐으로 잡히지 않는다.
  static const int pauseThresholdMilliseconds = 3000;

  final SessionSequenceAllocator _sequenceAllocator;
  final Stopwatch _sessionClock;
  final List<StrokeEventDto> _events = [];

  /// 아직 배치 큐로 넘기지 않은 이벤트다. 한 번의 기록이 설정 변경·멈춤·획을 한꺼번에
  /// 만들 수 있어 반환값 하나로는 전부 전달할 수 없다.
  final List<StrokeEventDto> _outbox = [];

  int _undoableStrokeCount = 0;
  int _redoableStrokeCount = 0;

  /// Draft 복원이 이벤트 순번을 재조정할 수 있는 구간이 끝났는지다.
  ///
  /// [resumeEventSequence]는 이미 기록된 이벤트가 있으면 실패하므로, 복원 응답을
  /// 기다리는 동안 도구·색 변경이 순번을 먼저 써 버리면 서버에 저장된 번호와 겹친다.
  /// 그래서 설정 변경은 이 값이 참이 되기 전까지 이벤트로 굳히지 않고 대기시킨다.
  bool _sequenceSettled = false;

  String? _committedToolCode;
  String? _committedColorHex;
  double? _committedThickness;
  _PendingSetting<String>? _pendingTool;
  _PendingSetting<String>? _pendingColor;
  _PendingSetting<double>? _pendingThickness;

  /// 마지막 캔버스 활동 시각이다. 첫 활동 전에는 null이라 멈춤을 재지 않는다 —
  /// 화면 준비·튜토리얼 시간이 "그리다 멈춘 시간"으로 둔갑하지 않게 한다.
  int? _lastActivityMilliseconds;

  int get elapsedMilliseconds => _sessionClock.elapsedMilliseconds;
  List<StrokeEventDto> get events => List.unmodifiable(_events);
  int? get lastEventSequence => _events.lastOrNull?.seq;
  int get snapshotCutoffSequence {
    final cutoff = _sequenceAllocator.nextValue - 1;
    return cutoff < 0 ? 0 : cutoff;
  }

  int get undoableStrokeCount => _undoableStrokeCount;
  int get redoableStrokeCount => _redoableStrokeCount;

  bool resumeEventSequence(int nextValue) {
    if (_events.isNotEmpty) return false;
    _sequenceAllocator.resumeAt(nextValue);
    _sequenceSettled = true;
    return true;
  }

  /// 배치 큐로 아직 넘기지 않은 이벤트를 꺼낸다.
  List<StrokeEventDto> drainPendingEvents() {
    if (_outbox.isEmpty) return const [];
    final drained = List<StrokeEventDto>.unmodifiable(_outbox);
    _outbox.clear();
    return drained;
  }

  List<StrokeEventDto> recordStroke(DrawingStroke stroke, Size canvasSize) {
    final converted = DrawingStrokeEventConverter.preview(
      stroke: stroke,
      canvasSize: canvasSize,
    );
    if (converted.isEmpty) return const [];

    _beginCanvasAction();
    _noteActivity(converted.first.t, canStartClock: true);
    final events = <StrokeEventDto>[];
    for (final event in converted) {
      final sequenced = event.withSequence(_sequenceAllocator.allocate());
      events.add(sequenced);
      _append(sequenced);
    }
    _undoableStrokeCount += 1;
    _redoableStrokeCount = 0;
    _lastActivityMilliseconds = events.last.t;
    return List.unmodifiable(events);
  }

  StrokeEventDto? recordUndo({int? elapsedMilliseconds}) {
    if (_undoableStrokeCount == 0) return null;
    final event = _recordCanvasAction(
      DrawingEventTypes.undo,
      elapsedMilliseconds: elapsedMilliseconds,
    );
    _undoableStrokeCount -= 1;
    _redoableStrokeCount += 1;
    return event;
  }

  StrokeEventDto? recordRedo({int? elapsedMilliseconds}) {
    if (_redoableStrokeCount == 0) return null;
    final event = _recordCanvasAction(
      DrawingEventTypes.redo,
      elapsedMilliseconds: elapsedMilliseconds,
    );
    _redoableStrokeCount -= 1;
    _undoableStrokeCount += 1;
    return event;
  }

  /// 전체 지우기를 기록한다.
  ///
  /// 문서 컨트롤러가 실행 취소·다시 실행 이력까지 함께 비우므로 여기서도 두 카운터를
  /// 0으로 되돌린다. 그러지 않으면 지운 뒤 첫 UNDO가 문서에는 없는 되돌리기로 기록된다.
  StrokeEventDto recordCanvasClear({int? elapsedMilliseconds}) {
    final event = _recordCanvasAction(
      DrawingEventTypes.canvasClear,
      elapsedMilliseconds: elapsedMilliseconds,
    );
    _undoableStrokeCount = 0;
    _redoableStrokeCount = 0;
    return event;
  }

  /// 영역 채우기를 기록한다. 채운 자리는 실제로 측정된 좌표라 함께 싣는다.
  ///
  /// 채우기도 문서의 실행 취소 대상이므로 되돌릴 수 있는 변경 수를 함께 올린다.
  /// 이 값이 없으면 채우기만 한 그림에서 UNDO 이벤트가 아예 나가지 않는다.
  StrokeEventDto recordFill({
    required Color color,
    required Offset documentPoint,
    required Size canvasSize,
    int? elapsedMilliseconds,
  }) {
    final hasCanvas = canvasSize.width > 0 && canvasSize.height > 0;
    final event = _recordCanvasAction(
      DrawingEventTypes.fill,
      elapsedMilliseconds: elapsedMilliseconds,
      x: hasCanvas
          ? (documentPoint.dx / canvasSize.width).clamp(0.0, 1.0)
          : null,
      y: hasCanvas
          ? (documentPoint.dy / canvasSize.height).clamp(0.0, 1.0)
          : null,
      color: DrawingStrokeEventConverter.colorHex(color),
    );
    _undoableStrokeCount += 1;
    _redoableStrokeCount = 0;
    return event;
  }

  /// 이벤트를 만들지 않는 되돌릴 수 있는 변경(획 지우개 제스처)을 카운터에만 반영한다.
  void noteUndoableDocumentChange() {
    _undoableStrokeCount += 1;
    _redoableStrokeCount = 0;
  }

  /// 도구 전환을 대기 목록에 올린다.
  ///
  /// [toolCode]는 크레용·연필·붓처럼 아이가 실제로 고른 도구다. 획에 실리는
  /// PEN/ERASER보다 좁혀지지 않은 값이라 같은 PEN 안에서의 전환도 남는다.
  void recordToolChange(String toolCode, {int? elapsedMilliseconds}) {
    final t = _noteSettingActivity(elapsedMilliseconds);
    if (toolCode == _committedToolCode) {
      _pendingTool = null;
      return;
    }
    _pendingTool = _PendingSetting(toolCode, t);
  }

  void recordColorChange(Color color, {int? elapsedMilliseconds}) {
    final t = _noteSettingActivity(elapsedMilliseconds);
    final hex = DrawingStrokeEventConverter.colorHex(color);
    if (hex == _committedColorHex) {
      _pendingColor = null;
      return;
    }
    _pendingColor = _PendingSetting(hex, t);
  }

  void recordThicknessChange(double thickness, {int? elapsedMilliseconds}) {
    final t = _noteSettingActivity(elapsedMilliseconds);
    if (thickness <= 0 || thickness == _committedThickness) {
      if (thickness == _committedThickness) _pendingThickness = null;
      return;
    }
    _pendingThickness = _PendingSetting(thickness, t);
  }

  /// 대기 중인 설정 변경을 이벤트로 굳힌다.
  ///
  /// 색 팔레트와 굵기 슬라이더는 끄는 동안 값이 초당 수십 번 바뀐다. 매 변화를
  /// 이벤트로 만들면 한 번의 조작이 배치를 가득 채우고, 분석에는 "마지막에 무엇을
  /// 골랐는가"만 남으면 된다. 그래서 마지막 값 하나만 남겼다가 다음 캔버스 행동이나
  /// 배치 전송 직전에 굳힌다. 시각은 굳힌 때가 아니라 아이가 그 값을 고른 때다.
  List<StrokeEventDto> commitPendingSettings() {
    if (!_sequenceSettled) return const [];
    final staged = <(int, String, String?, String?, double?)>[];
    if (_pendingTool case final pending?) {
      staged.add((
        pending.elapsedMilliseconds,
        DrawingEventTypes.toolChange,
        pending.value,
        null,
        null,
      ));
    }
    if (_pendingColor case final pending?) {
      staged.add((
        pending.elapsedMilliseconds,
        DrawingEventTypes.colorChange,
        null,
        pending.value,
        null,
      ));
    }
    if (_pendingThickness case final pending?) {
      staged.add((
        pending.elapsedMilliseconds,
        DrawingEventTypes.thicknessChange,
        null,
        null,
        pending.value,
      ));
    }
    if (staged.isEmpty) return const [];
    // 아이가 고른 순서대로 남긴다.
    staged.sort((a, b) => a.$1.compareTo(b.$1));

    final committed = <StrokeEventDto>[];
    for (final (at, type, tool, color, thickness) in staged) {
      final event = StrokeEventDto(
        seq: _sequenceAllocator.allocate(),
        t: at,
        type: type,
        tool: tool,
        color: color,
        thickness: thickness,
      );
      committed.add(event);
      _append(event);
    }
    _committedToolCode = _pendingTool?.value ?? _committedToolCode;
    _committedColorHex = _pendingColor?.value ?? _committedColorHex;
    _committedThickness = _pendingThickness?.value ?? _committedThickness;
    _pendingTool = null;
    _pendingColor = null;
    _pendingThickness = null;
    return List.unmodifiable(committed);
  }

  /// 앱이 백그라운드에 다녀온 시간을 멈춤에서 제외한다.
  ///
  /// 세션 시계는 앱이 가려져 있는 동안에도 흐른다. 그대로 두면 아이가 앱을 닫고 다음
  /// 날 이어 그렸을 때 "12시간 멈춤"이 관찰 사실로 기록된다. 캔버스 앞에서 망설인
  /// 시간이 아니므로 재개 시각을 새 기준으로 삼는다. (백엔드도 같은 이유로
  /// `MAX_CONTINUOUS_GAP_MS` 위 간격을 그리기 시간에서 뺀다.)
  void resetIdleClock({int? elapsedMilliseconds}) {
    if (_lastActivityMilliseconds == null) return;
    _lastActivityMilliseconds =
        elapsedMilliseconds ?? _sessionClock.elapsedMilliseconds;
  }

  /// 그림 단계를 끝내기 직전, 마지막 획 뒤에 남은 멈춤을 닫는다.
  ///
  /// 멈춤은 "다시 그리기 시작한 순간"에만 닫히므로, 아이가 손을 놓고 그대로 완료를
  /// 누르면 그 구간이 영영 기록되지 않는다. 주기 전송에서 닫지 않는 이유는 아직
  /// 진행 중인 멈춤을 조각내 같은 멈춤이 여러 번으로 세어지기 때문이다.
  List<StrokeEventDto> closeTrailingPause({int? elapsedMilliseconds}) {
    final committed = commitPendingSettings();
    final last = _lastActivityMilliseconds;
    if (last == null || !_sequenceSettled) return committed;
    final now = elapsedMilliseconds ?? _sessionClock.elapsedMilliseconds;
    _emitPauseIfIdle(last, now);
    _lastActivityMilliseconds = now;
    return committed;
  }

  StrokeEventDto _recordCanvasAction(
    String type, {
    int? elapsedMilliseconds,
    double? x,
    double? y,
    String? color,
  }) {
    _beginCanvasAction();
    final t = elapsedMilliseconds ?? _sessionClock.elapsedMilliseconds;
    _noteActivity(t, canStartClock: true);
    final event = StrokeEventDto(
      seq: _sequenceAllocator.allocate(),
      t: t,
      type: type,
      x: x,
      y: y,
      color: color,
    );
    _append(event);
    _lastActivityMilliseconds = t;
    return event;
  }

  /// 캔버스 행동은 순번을 확정하고, 그 앞에 대기 중이던 설정 변경부터 굳힌다.
  void _beginCanvasAction() {
    _sequenceSettled = true;
    commitPendingSettings();
  }

  /// 설정 변경도 아이의 행동이라 멈춤을 끊는다. 다만 첫 캔버스 행동 전에는 멈춤
  /// 시계를 시작하지 않는다 — 아직 한 번도 그리지 않은 시간은 "그리다 멈춘 것"이 아니다.
  int _noteSettingActivity(int? elapsedMilliseconds) {
    final t = elapsedMilliseconds ?? _sessionClock.elapsedMilliseconds;
    _noteActivity(t, canStartClock: false);
    return t;
  }

  void _noteActivity(int t, {required bool canStartClock}) {
    final last = _lastActivityMilliseconds;
    if (last == null) {
      if (canStartClock) _lastActivityMilliseconds = t;
      return;
    }
    _emitPauseIfIdle(last, t);
    _lastActivityMilliseconds = t;
  }

  /// 멈춤은 PAUSE·RESUME 두 이벤트를 붙여서 낸다.
  ///
  /// 배치 이벤트에는 절대 시각 필드가 없어(좌표의 `t`만 있다) 멈춤 길이를 이벤트로는
  /// 실을 수 없다. 그래서 길이는 `metrics.pauseDurationMsDelta`가, 횟수와 순서는
  /// 이 두 이벤트가 나눠 맡는다. 항상 한 배치 안에 짝으로 들어가므로 배치 변환기가
  /// 두 이벤트의 `t` 차이로 길이를 계산해도 이벤트와 지표가 어긋나지 않는다.
  void _emitPauseIfIdle(int from, int to) {
    if (!_sequenceSettled) return;
    if (to - from < pauseThresholdMilliseconds) return;
    _append(
      StrokeEventDto(
        seq: _sequenceAllocator.allocate(),
        t: from,
        type: DrawingEventTypes.pause,
      ),
    );
    _append(
      StrokeEventDto(
        seq: _sequenceAllocator.allocate(),
        t: to,
        type: DrawingEventTypes.resume,
      ),
    );
  }

  void _append(StrokeEventDto event) {
    _events.add(event);
    _outbox.add(event);
  }
}

abstract final class DrawingStrokeEventConverter {
  /// 순번을 붙이기 전의 획 이벤트를 만든다.
  ///
  /// 획보다 앞서 굳혀야 할 설정 변경·멈춤이 있어 순번을 여기서 먼저 쓰면 순서가
  /// 뒤집힌다. 그래서 좌표 변환만 하고 순번은 호출부가 붙인다.
  static List<StrokeEventDto> preview({
    required DrawingStroke stroke,
    required Size canvasSize,
  }) {
    if (stroke.points.isEmpty ||
        canvasSize.width <= 0 ||
        canvasSize.height <= 0) {
      return const [];
    }

    if (stroke.points.length == 1) {
      final point = stroke.points.single;
      return List.unmodifiable([
        _eventForPoint(
          point: point,
          stroke: stroke,
          canvasSize: canvasSize,
          type: DrawingEventTypes.strokeStart,
          includeStyle: true,
        ),
        _eventForPoint(
          point: point,
          stroke: stroke,
          canvasSize: canvasSize,
          type: DrawingEventTypes.strokeEnd,
        ),
      ]);
    }

    final result = <StrokeEventDto>[];
    for (var index = 0; index < stroke.points.length; index++) {
      final point = stroke.points[index];
      final isFirst = index == 0;
      final isLast = index == stroke.points.length - 1;
      result.add(
        _eventForPoint(
          point: point,
          stroke: stroke,
          canvasSize: canvasSize,
          type: isFirst
              ? DrawingEventTypes.strokeStart
              : isLast
              ? DrawingEventTypes.strokeEnd
              : DrawingEventTypes.strokeMove,
          includeStyle: isFirst,
        ),
      );
    }
    return List.unmodifiable(result);
  }

  static List<StrokeEventDto> convert({
    required DrawingStroke stroke,
    required Size canvasSize,
    required SessionSequenceAllocator sequenceAllocator,
  }) {
    final events = preview(stroke: stroke, canvasSize: canvasSize);
    if (events.isEmpty) return const [];
    return List.unmodifiable([
      for (final event in events) event.withSequence(sequenceAllocator.allocate()),
    ]);
  }

  static StrokeEventDto _eventForPoint({
    required DrawingPoint point,
    required DrawingStroke stroke,
    required Size canvasSize,
    required String type,
    bool includeStyle = false,
  }) => StrokeEventDto(
    seq: 0,
    t: point.elapsedMilliseconds,
    type: type,
    x: (point.position.dx / canvasSize.width).clamp(0.0, 1.0),
    y: (point.position.dy / canvasSize.height).clamp(0.0, 1.0),
    tool: includeStyle ? _toolCode(stroke.tool) : null,
    color: includeStyle && stroke.tool == DrawingTool.pen
        ? colorHex(stroke.color)
        : null,
    // Team policy uses the same Flutter logical pixel value as Paint.strokeWidth.
    // TODO(API): Document logical pixels as the final backend unit.
    thickness: includeStyle ? stroke.thickness : null,
    pressure: point.pressure?.clamp(0.0, 1.0),
  );

  static String _toolCode(DrawingTool tool) => switch (tool) {
    DrawingTool.pen => 'PEN',
    DrawingTool.eraser => 'ERASER',
  };

  static String colorHex(Color color) {
    final rgb = color.toARGB32() & 0x00FFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }
}
