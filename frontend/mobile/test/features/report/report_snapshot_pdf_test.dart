import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dodam/features/report/presentation/services/report_snapshot_pdf.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// 실제 캡처는 프레임을 읽으므로 [WidgetTester.runAsync] 안에서만 완료된다.
void main() {
  testWidgets('스크롤 밖 내용까지 담아 여러 장의 PDF로 만든다', (tester) async {
    tester.view.physicalSize = const Size(400, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    await tester.pumpWidget(_TallReport(snapshotKey: key));
    await tester.pumpAndSettle();

    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    // 화면(600)보다 훨씬 긴 본문이 한 경계에 들어 있어야 한다.
    expect(boundary.size.height, greaterThan(2000));

    late final Uint8List bytes;
    late final List<Uint8List> pages;
    await tester.runAsync(() async {
      bytes = await ReportSnapshotPdf.compose(boundary, pixelRatio: 1);
      final image = await boundary.toImage();
      pages = await ReportSnapshotPdf.sliceToPages(image);
      image.dispose();
    });

    expect(bytes.sublist(0, 5), [0x25, 0x50, 0x44, 0x46, 0x2D]);
    // 폭 400 이면 A4 비율 한 장이 약 566px 다. 2400px 본문은 여러 장으로 나뉜다.
    expect(pages.length, greaterThan(3));
    for (final page in pages) {
      // 각 장은 PNG 로 굽는다.
      expect(page.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
    }
  });

  testWidgets('한 장에 담기는 짧은 화면은 한 페이지로 만든다', (tester) async {
    tester.view.physicalSize = const Size(400, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    await tester.pumpWidget(
      _TallReport(snapshotKey: key, sectionCount: 1, sectionHeight: 120),
    );
    await tester.pumpAndSettle();

    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    late final List<Uint8List> pages;
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      pages = await ReportSnapshotPdf.sliceToPages(image);
      image.dispose();
    });

    expect(pages, hasLength(1));
  });

  test('빈 이미지도 최소 한 장은 만든다', () async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(
      const Rect.fromLTWH(0, 0, 10, 1),
      Paint()..color = const Color(0xFFFFFFFF),
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(10, 1);
    picture.dispose();

    final pages = await ReportSnapshotPdf.sliceToPages(image);
    image.dispose();

    expect(pages, hasLength(1));
  });
}

/// 실제 리포트처럼 스크롤 밖으로 흐르는 본문이다.
class _TallReport extends StatelessWidget {
  const _TallReport({
    required this.snapshotKey,
    this.sectionCount = 8,
    this.sectionHeight = 300,
  });

  final GlobalKey snapshotKey;
  final int sectionCount;
  final double sectionHeight;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: RepaintBoundary(
          key: snapshotKey,
          child: ColoredBox(
            color: const Color(0xFFFFFDF7),
            child: Column(
              children: [
                for (var index = 0; index < sectionCount; index++)
                  Container(
                    height: sectionHeight,
                    margin: const EdgeInsets.all(8),
                    color: index.isEven
                        ? const Color(0xFFEAD98A)
                        : const Color(0xFFB9D3A0),
                    alignment: Alignment.center,
                    child: Text('섹션 $index'),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
