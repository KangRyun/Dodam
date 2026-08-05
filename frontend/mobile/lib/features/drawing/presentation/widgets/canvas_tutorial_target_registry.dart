import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// 튜토리얼이 가리킬 실제 도구 자리다.
///
/// 안내가 화면 가운데 카드로만 뜨면 아이는 설명을 읽고도 어느 버튼인지 못 찾는다.
/// 그래서 지금 툴바에 있는 위젯을 그대로 가리켜야 하는데, widget tree 를 훑어
/// [ValueKey] 를 찾는 방식은 기기별 툴바 배치(한 줄·두 줄)와 HTP 축약 배치마다
/// 달라져 쉽게 깨진다. 가리킬 자리마다 [GlobalKey] 를 미리 심어 두고 그 key 로만
/// 위치를 읽는다.
enum CanvasTutorialTargetId {
  /// 크레용·연필·붓·물감통. HTP 에서는 연필만 남는다.
  tools,
  eraser,

  /// 빠른 색상 줄과 팔레트 버튼. HTP 에서는 둘 다 없다.
  colors,

  /// 굵기 막대와 실제 굵기 미리보기 동그라미.
  thickness,

  /// 실행 취소·다시 실행.
  history,

  /// `다 그렸어요!`. 툴바가 아니라 화면 오른쪽 아래에 있다.
  complete,
}

/// 단계별 target 위젯의 화면 위 위치를 알려 준다.
///
/// 위치는 화면(global) 좌표로 돌려준다. 오버레이가 자기 좌표로 바꿔 쓴다.
final class CanvasTutorialTargetRegistry {
  final Map<String, GlobalKey> _keys = {};
  final Map<CanvasTutorialTargetId, Rect> _reported = {};

  /// 한 단계가 여러 위젯을 가리킬 수 있어 [slot] 으로 나눠 심는다.
  ///
  /// 같은 (id, slot) 은 늘 같은 key 를 돌려줘야 한다. 툴바는 도구를 고를 때마다
  /// 다시 만들어지므로, key 를 그때그때 새로 만들면 위치를 읽을 수 없다.
  GlobalKey key(CanvasTutorialTargetId id, [String slot = 'main']) =>
      _keys.putIfAbsent(
        '${id.name}.$slot',
        () => GlobalKey(debugLabel: 'canvas-tutorial-${id.name}-$slot'),
      );

  /// key 를 심을 수 없는 자리가 자기 위치를 직접 알려 준다.
  ///
  /// 완료 버튼은 Scaffold 가 `floatingActionButton` 자리에서 넣고 빼며, 바뀌는
  /// 동안 옛 버튼과 새 버튼을 잠시 함께 둔다. 그 사이 같은 [GlobalKey] 가 두 곳에
  /// 있게 되어 key 로는 위치를 심을 수 없다.
  void report(CanvasTutorialTargetId id, Rect? rect) {
    if (rect == null) {
      _reported.remove(id);
      return;
    }
    if (rect.isEmpty) return;
    _reported[id] = rect;
  }

  /// 지금 화면에 실제로 배치된 자리만 돌려준다.
  ///
  /// 그 조작이 화면에 없으면 비어 있다. 그때 오버레이는 없는 자리를 가리키는
  /// 대신 가운데 카드로 물러난다.
  List<Rect> rectsOf(CanvasTutorialTargetId id) {
    final prefix = '${id.name}.';
    final rects = <Rect>[?_reported[id]];
    for (final entry in _keys.entries) {
      if (!entry.key.startsWith(prefix)) continue;
      final rect = _rectOf(entry.value);
      if (rect != null) rects.add(rect);
    }
    return rects;
  }

  static Rect? _rectOf(GlobalKey key) {
    final renderObject = key.currentContext?.findRenderObject();
    if (renderObject is! RenderBox) return null;
    // 아직 배치되지 않았거나 화면에서 떨어진 위젯의 좌표를 읽으면 예외가 난다.
    if (!renderObject.attached || !renderObject.hasSize) return null;
    final size = renderObject.size;
    if (size.isEmpty) return null;
    return renderObject.localToGlobal(Offset.zero) & size;
  }
}

/// 아이가 안내받은 도구를 실제로 한 번 써 봤는지 기억한다.
///
/// 설명을 읽고 `다음`만 누르는 안내는 아이가 손으로 익히지 못한다. 그렇다고 해
/// 보기 전까지 `다음`을 막으면 진행이 멈추고, 캔버스에 선을 강제로 그리게 하면
/// 아이 그림에 원치 않는 자국이 남는다. 그래서 막지 않고 표시만 한다.
final class CanvasTutorialPracticeTracker extends ChangeNotifier {
  final Set<CanvasTutorialTargetId> _done = {};

  bool isDone(CanvasTutorialTargetId? id) => id != null && _done.contains(id);

  void mark(CanvasTutorialTargetId id) {
    if (_done.add(id)) notifyListeners();
  }
}

/// 감싼 위젯이 자기 위치를 [registry] 에 알려 준다.
///
/// 위치는 프레임 콜백이 아니라 paint 시점에 알린다. 안내는 프레임 콜백에서 위치를
/// 읽으므로, 같은 프레임의 paint 에서 넣어야 한 프레임 늦은 자리를 가리키지 않는다.
final class CanvasTutorialTargetReporter extends SingleChildRenderObjectWidget {
  const CanvasTutorialTargetReporter({
    required this.registry,
    required this.id,
    super.child,
    super.key,
  });

  final CanvasTutorialTargetRegistry registry;
  final CanvasTutorialTargetId id;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderTargetReporter(registry, id);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderTargetReporter)
      ..registry = registry
      ..id = id;
  }
}

final class _RenderTargetReporter extends RenderProxyBox {
  _RenderTargetReporter(this._registry, this._id);

  CanvasTutorialTargetRegistry _registry;
  CanvasTutorialTargetId _id;

  set registry(CanvasTutorialTargetRegistry value) {
    if (_registry == value) return;
    _registry = value;
    markNeedsPaint();
  }

  set id(CanvasTutorialTargetId value) {
    if (_id == value) return;
    _registry.report(_id, null);
    _id = value;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    _registry.report(_id, localToGlobal(Offset.zero) & size);
    super.paint(context, offset);
  }

  @override
  void detach() {
    // 화면에서 빠진 자리를 계속 가리키지 않는다.
    _registry.report(_id, null);
    super.detach();
  }
}
