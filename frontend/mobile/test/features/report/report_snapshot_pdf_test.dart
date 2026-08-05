import 'dart:typed_data';

import 'package:dodam/features/report/presentation/services/report_snapshot_pdf.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// 실제 캡처는 프레임을 읽으므로 [WidgetTester.runAsync] 안에서만 완료된다.
void main() {
  testWidgets('짧은 섹션 여러 개는 한 장에 모아 담는다', (tester) async {
    final keys = await _pumpSections(
      tester,
      // 세 섹션을 합쳐도 A4 한 장(폭의 약 1.3배 높이)에 들어간다.
      heights: const [120, 140, 130],
    );

    late final Uint8List bytes;
    await tester.runAsync(() async {
      bytes = await ReportSnapshotPdf.compose(
        ReportPdfRequest(sections: _boundaries(keys), title: '도담 관찰 리포트'),
        pixelRatio: 1,
      );
    });

    expect(bytes.sublist(0, 5), [0x25, 0x50, 0x44, 0x46, 0x2D]);
    expect(_pageCount(bytes), 1);
  });

  testWidgets('한 장에 안 들어가는 섹션은 자르지 않고 다음 장으로 넘긴다', (tester) async {
    // 각 섹션이 한 장의 3분의 2를 차지해 두 개가 한 장에 못 들어간다.
    final keys = await _pumpSections(tester, heights: const [360, 360, 360]);

    late final Uint8List bytes;
    await tester.runAsync(() async {
      bytes = await ReportSnapshotPdf.compose(
        ReportPdfRequest(sections: _boundaries(keys), title: '도담 관찰 리포트'),
        pixelRatio: 1,
      );
    });

    // 섹션을 쪼개지 않으므로 한 장에 하나씩 들어가 세 장이 된다.
    expect(_pageCount(bytes), 3);
  });

  testWidgets('한 장보다 긴 섹션만 그 섹션을 나눈다', (tester) async {
    final keys = await _pumpSections(tester, heights: const [1600]);

    late final Uint8List bytes;
    await tester.runAsync(() async {
      bytes = await ReportSnapshotPdf.compose(
        ReportPdfRequest(sections: _boundaries(keys), title: '도담 관찰 리포트'),
        pixelRatio: 1,
      );
    });

    expect(_pageCount(bytes), greaterThan(1));
  });

  testWidgets('배치되지 않은 섹션은 건너뛴다', (tester) async {
    final keys = await _pumpSections(tester, heights: const [200]);
    final sections = [
      ..._boundaries(keys),
      // 화면에서 떨어진 경계가 섞여도 저장이 실패하면 안 된다.
      RenderRepaintBoundary(),
    ];

    late final Uint8List bytes;
    await tester.runAsync(() async {
      bytes = await ReportSnapshotPdf.compose(
        ReportPdfRequest(sections: sections, title: '도담 관찰 리포트'),
        pixelRatio: 1,
      );
    });

    expect(_pageCount(bytes), 1);
  });
}

/// 섹션마다 캡처 경계를 두고 화면에 올린다. 실제 리포트 화면과 같은 구조다.
Future<List<GlobalKey>> _pumpSections(
  WidgetTester tester, {
  required List<double> heights,
}) async {
  tester.view.physicalSize = const Size(400, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final keys = [
    for (var index = 0; index < heights.length; index++) GlobalKey(),
  ];
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Column(
            children: [
              for (final (index, height) in heights.indexed)
                RepaintBoundary(
                  key: keys[index],
                  child: ColoredBox(
                    color: const Color(0xFFFFFDF7),
                    child: SizedBox(
                      height: height,
                      width: double.infinity,
                      child: Center(child: Text('섹션 $index')),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return keys;
}

List<RenderRepaintBoundary> _boundaries(List<GlobalKey> keys) => [
  for (final key in keys)
    key.currentContext!.findRenderObject()! as RenderRepaintBoundary,
];

/// PDF 안의 `/Type /Page` 개수를 센다. 페이지 트리를 파싱하지 않고 세는 값이라 충분하다.
int _pageCount(Uint8List bytes) {
  final text = String.fromCharCodes(bytes);
  return RegExp(r'/Type\s*/Page[^s]').allMatches(text).length;
}
