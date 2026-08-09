import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/drawing_stroke.dart';

/// 도구별 획 질감 스탬프다.
///
/// 크레파스·연필·붓은 굵기만 다른 같은 선이 아니라 자국의 생김새가 다르다.
/// 승인 원화를 알파 마스크로 구운 이미지를 획을 따라 찍어 그 차이를 낸다.
/// (원화 → 마스크 변환은 `test/tools/build_brush_masks_test.dart` 참고)
abstract final class DrawingBrushStamps {
  static const _assets = <DrawingBrushProfileId, String>{
    DrawingBrushProfileId.crayon: 'assets/canvas/brushes/crayon_crumb.png',
    DrawingBrushProfileId.pencil: 'assets/canvas/brushes/pencil_grain.png',
    DrawingBrushProfileId.brush: 'assets/canvas/brushes/brush_tip.png',
  };

  static final Map<DrawingBrushProfileId, ui.Image> _loaded = {};
  static Future<void>? _loading;

  /// 스탬프가 준비되면 알린다. 아직이면 캔버스는 단색 선으로 먼저 그린다.
  static final ChangeNotifier revision = ChangeNotifier();

  static ui.Image? stampFor(DrawingBrushProfileId id) => _loaded[id];

  /// 스탬프를 한 번만 읽어 둔다. 읽기에 실패해도 그리기는 막지 않는다.
  static Future<void> ensureLoaded() => _loading ??= _load();

  static Future<void> _load() async {
    for (final entry in _assets.entries) {
      try {
        final data = await rootBundle.load(entry.value);
        final codec = await ui.instantiateImageCodec(
          data.buffer.asUint8List(),
        );
        final frame = await codec.getNextFrame();
        codec.dispose();
        _loaded[entry.key] = frame.image;
      } on Object catch (error) {
        // 에셋이 없어도 단색 선으로 그릴 수 있어야 한다.
        debugPrint('brush stamp load failed: ${entry.value} ($error)');
      }
    }
    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    revision.notifyListeners();
  }

  @visibleForTesting
  static void resetForTest() {
    for (final image in _loaded.values) {
      image.dispose();
    }
    _loaded.clear();
    _loading = null;
  }
}
