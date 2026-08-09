@Tags(['tool'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 통합 크레용 도구 아이콘(v3 flat)을 앱 에셋으로 들여오는 일회성 도구다.
///
///   flutter test tool/brushes/import_flat_tool_icons_test.dart
///
/// 원본은 도구 7종 x 선택색 8종이 미리 그려져 있다. 색을 코드에서 입히지 않고
/// 고른 색에 맞는 그림을 그대로 쓰면 테두리에 밑그림이 비치지 않는다.
/// CI 가 test/ 만 돌도록 tool/ 아래 둔다.
const _source =
    r'C:\Users\SSAFY\.codex\visualizations\2026\07\29\dodam-canvas-responsive'
    r'\unified-tool-icons-v3-flat\icons\96';
const _target = 'assets/canvas/tools';

/// 앱이 쓰는 선택색 이름이다. 원본 폴더 이름과 같다.
const _colors = <String>[
  'red',
  'orange',
  'yellow',
  'green',
  'teal',
  'blue',
  'purple',
  'charcoal',
];

/// 고른 색을 따라가는 도구다.
const _tinted = <String>['crayon', 'pencil', 'brush', 'fill'];

/// 색이 고정된 도구다. 어느 색 폴더에서 가져와도 같다.
const _fixed = <String>['eraser', 'palette'];

void main() {
  test('flat crayon tool icons are imported for every selectable color', () {
    for (final color in _colors) {
      for (final tool in _tinted) {
        final source = File(
          '$_source${Platform.pathSeparator}$color'
          '${Platform.pathSeparator}$tool.png',
        );
        expect(source.existsSync(), isTrue, reason: '$color/$tool');
        File('$_target/$color/$tool.png').createSync(recursive: true);
        source.copySync('$_target/$color/$tool.png');
      }
    }

    for (final tool in _fixed) {
      final source = File(
        '$_source${Platform.pathSeparator}charcoal'
        '${Platform.pathSeparator}$tool.png',
      );
      expect(source.existsSync(), isTrue, reason: tool);
      source.copySync('$_target/${tool}_base.png');
    }
  });
}
