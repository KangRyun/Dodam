import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// 리포트 화면을 그대로 담은 PDF 를 만드는 함수 모양이다.
///
/// 테스트가 실제 GPU 캡처 없이 저장·공유 흐름만 확인할 수 있도록 화면에서 분리한다.
typedef ReportPdfComposer =
    Future<Uint8List> Function(RenderRepaintBoundary boundary);

/// 화면에 보이는 리포트를 그대로 종이 크기로 잘라 PDF 로 굽는다.
///
/// 서버가 만드는 PDF 는 줄글만 담아 카드·색·그림·감정이 전부 빠진다. 보호자가 화면에서 본
/// 리포트와 저장한 파일이 다르면 저장한 쪽을 신뢰할 수 없다. 그래서 위젯을 이미지로 떠서
/// 그대로 싣는다.
///
/// ⚠️ 스크롤 밖 내용까지 담기려면 리포트 본문이 한 번에 배치되어 있어야 한다. 현재 화면은
/// `SingleChildScrollView` + `Column` 이라 자식 전체가 그려지므로 경계 하나로 전부 담긴다.
/// 본문을 `ListView` 같은 지연 목록으로 바꾸면 보이는 만큼만 저장된다.
abstract final class ReportSnapshotPdf {
  /// 세로 A4 한 장의 높이·폭 비율이다. 이미지를 이 비율로 잘라 한 장에 담는다.
  static final double _pageAspectRatio =
      PdfPageFormat.a4.height / PdfPageFormat.a4.width;

  /// 화면 밀도 그대로면 글자가 흐리다. 두 배로 떠서 확대해도 읽히게 한다.
  static const double _defaultPixelRatio = 2;

  /// 캡처 이미지 한 장의 상한이다.
  ///
  /// 리포트는 섹션이 많아 화면 높이의 열 배를 넘기도 한다. 밀도를 그대로 곱하면 한 번에
  /// 잡는 픽셀이 수천만 개가 되어 저사양 기기에서 캡처가 실패한다. 상한을 넘으면 밀도를
  /// 낮춰 저장을 성공시키는 쪽을 고른다 — 저장 실패보다 조금 흐린 저장이 낫다.
  static const int _maxCapturePixels = 24000000;

  /// 종이 가장자리 여백이다. 캡처를 가장자리까지 붙이면 인쇄 시 잘린다.
  static const double _pageMargin = 16;

  /// [boundary] 가 그리는 화면을 PDF 바이트로 만든다.
  ///
  /// @param pixelRatio 캡처 배율. 기본값은 화면 밀도의 두 배다.
  static Future<Uint8List> compose(
    RenderRepaintBoundary boundary, {
    double pixelRatio = _defaultPixelRatio,
  }) async {
    final image = await boundary.toImage(
      pixelRatio: _fitPixelRatio(boundary.size, pixelRatio),
    );
    try {
      return await _document(await sliceToPages(image));
    } finally {
      image.dispose();
    }
  }

  /// 캡처 배율을 [_maxCapturePixels] 안으로 낮춘다. 여유가 있으면 요청값을 그대로 쓴다.
  static double _fitPixelRatio(Size size, double requested) {
    final area = size.width * size.height;
    if (area <= 0) return requested;
    final requestedPixels = area * requested * requested;
    if (requestedPixels <= _maxCapturePixels) return requested;
    return math.sqrt(_maxCapturePixels / area);
  }

  /// 긴 캡처를 A4 비율의 여러 장으로 자른다.
  ///
  /// 자르는 자리가 글줄 가운데일 수 있다. 그래도 내용을 빠뜨리지 않는 쪽을 골랐다 — 섹션
  /// 경계를 찾아 자르려면 화면 구조를 캡처가 알아야 하고, 그러면 화면을 바꿀 때마다 저장이
  /// 깨진다.
  @visibleForTesting
  static Future<List<Uint8List>> sliceToPages(ui.Image image) async {
    final width = image.width;
    final pageHeight = math.max(1, (width * _pageAspectRatio).round());
    final pageCount = math.max(1, (image.height / pageHeight).ceil());
    final pages = <Uint8List>[];
    for (var index = 0; index < pageCount; index++) {
      final top = index * pageHeight;
      final height = math.min(pageHeight, image.height - top);
      if (height <= 0) break;
      final slice = await _crop(image, top: top, width: width, height: height);
      try {
        final encoded = await slice.toByteData(format: ui.ImageByteFormat.png);
        if (encoded != null) pages.add(encoded.buffer.asUint8List());
      } finally {
        slice.dispose();
      }
    }
    return pages;
  }

  static Future<ui.Image> _crop(
    ui.Image source, {
    required int top,
    required int width,
    required int height,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final target = Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
    // 캡처에 투명한 곳이 있으면 PDF 뷰어가 검게 보여 준다. 흰 종이를 먼저 깔아 둔다.
    canvas
      ..drawRect(target, Paint()..color = const Color(0xFFFFFFFF))
      ..drawImageRect(
        source,
        Rect.fromLTWH(0, top.toDouble(), width.toDouble(), height.toDouble()),
        target,
        Paint(),
      );
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(width, height);
    } finally {
      picture.dispose();
    }
  }

  static Future<Uint8List> _document(List<Uint8List> pages) async {
    final document = pw.Document(title: '도담 관찰 리포트');
    for (final page in pages) {
      final image = pw.MemoryImage(page);
      document.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(_pageMargin),
          build: (context) => pw.Image(
            image,
            fit: pw.BoxFit.fitWidth,
            // 마지막 장은 짧다. 가운데 두면 앞 장과 글줄 위치가 어긋나 보인다.
            alignment: pw.Alignment.topCenter,
          ),
        ),
      );
    }
    return document.save();
  }
}
