import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// PDF 로 만들 리포트다. 본문을 섹션 단위로 받는다.
@immutable
final class ReportPdfRequest {
  const ReportPdfRequest({required this.sections, required this.title});

  /// 화면에 쌓인 순서대로의 섹션 경계다. 카드 하나가 한 장을 넘지 않게 이 단위로 자른다.
  final List<RenderRepaintBoundary> sections;

  /// PDF 파일 정보에 넣을 제목이다. 본문 제목은 캡처 안에 이미 들어 있다.
  final String title;
}

/// 화면에 보이는 리포트를 그대로 담은 PDF 를 만드는 함수 모양이다.
///
/// 테스트가 실제 GPU 캡처 없이 저장·공유 흐름만 확인할 수 있도록 화면에서 분리한다.
typedef ReportPdfComposer =
    Future<Uint8List> Function(ReportPdfRequest request);

/// 화면에 보이는 리포트를 섹션이 잘리지 않게 PDF 로 굽는다.
///
/// ⚠️ **정본은 서버다. 여기에 문서 디자인을 더하지 말 것**(ADR-0003, S15P11B209-965).
/// 리포트 PDF 는 서버가 만든 파일을 앱·웹이 함께 쓰기로 정했다. 이 캡처 경로는 서버 템플릿
/// 전환(S15P11B209-968)이 끝날 때까지만 남겨 두고, 끝나면 통째로 제거한다(S15P11B209-969).
/// 표지·요약 구성이나 카드 단위 배치 같은 개선은 서버 템플릿에만 넣는다 — 여기에 넣으면
/// 전환할 때 그대로 폐기된다.
///
/// 서버가 만드는 PDF 는 줄글만 담아 카드·색·그림·감정이 전부 빠진다. 보호자가 화면에서 본
/// 리포트와 저장한 파일이 다르면 저장한 쪽을 신뢰할 수 없다. 그래서 위젯을 이미지로 떠서
/// 그대로 싣는다.
///
/// ⚠️ 본문 전체를 한 장의 긴 이미지로 떠서 종이 크기로 자르면 자르는 자리가 카드 중간이 되어
/// 글줄과 카드가 매 장 잘린다. 그래서 섹션마다 따로 떠서, 들어갈 자리가 있는 섹션만 그 장에
/// 채우고 남으면 다음 장으로 넘긴다. 한 섹션이 한 장보다 길 때만 그 섹션을 나눈다.
abstract final class ReportSnapshotPdf {
  /// 종이 여백이다. 캡처를 가장자리까지 붙이면 인쇄할 때 잘린다.
  static const double _marginHorizontal = 24;
  static const double _marginTop = 24;
  static const double _marginBottom = 30;

  /// 섹션 사이 간격이다. 화면의 섹션 간격과 비슷하게 둔다.
  static const double _sectionGap = 10;

  /// 화면 밀도 그대로면 확대했을 때 글자가 흐리다. 섹션마다 따로 뜨므로 한 장이 크지 않아
  /// 세 배까지 올릴 수 있다.
  static const double _defaultPixelRatio = 3;

  /// 캡처 한 장의 픽셀 상한이다.
  ///
  /// 섹션이 아주 길면(문답 목록 등) 밀도를 그대로 곱한 픽셀이 수천만 개가 되어 저사양 기기에서
  /// 캡처가 실패한다. 상한을 넘으면 밀도를 낮춰 저장을 성공시키는 쪽을 고른다 — 저장 실패보다
  /// 조금 흐린 저장이 낫다.
  static const int _maxCapturePixels = 24000000;

  /// 종이에 실제로 그림이 들어가는 폭이다.
  static double get _contentWidth =>
      PdfPageFormat.a4.width - _marginHorizontal * 2;

  /// 한 장에 들어가는 본문 높이다. 쪽번호 자리를 뺀다.
  static double get _contentHeight =>
      PdfPageFormat.a4.height - _marginTop - _marginBottom - _footerHeight;

  static const double _footerHeight = 16;

  /// 이 비율(높이/폭)을 넘는 섹션은 한 장에 못 들어간다. 그 섹션만 나눈다.
  ///
  /// 섹션 아래 간격까지 빼야 한다. 딱 한 장 높이로 자르면 간격이 더해져 한 장을 넘고, 그러면
  /// 배치가 실패해 저장 자체가 안 된다.
  static double get _maxSectionAspectRatio =>
      (_contentHeight - _sectionGap) / _contentWidth;

  /// 앱과 같은 글꼴이다. 쪽번호와 파일 정보에 쓴다.
  static const String _fontAsset = 'assets/fonts/NanumSquareNeo-Regular.ttf';

  /// [request] 의 섹션들을 순서대로 담은 PDF 바이트를 만든다.
  static Future<Uint8List> compose(
    ReportPdfRequest request, {
    double pixelRatio = _defaultPixelRatio,
  }) async {
    final pieces = <_Piece>[];
    for (final section in request.sections) {
      pieces.addAll(await _capture(section, pixelRatio));
    }
    return _document(request.title, pieces);
  }

  /// 섹션 하나를 뜬다. 한 장보다 길면 그 섹션만 여러 조각으로 나눈다.
  static Future<List<_Piece>> _capture(
    RenderRepaintBoundary section,
    double pixelRatio,
  ) async {
    if (!section.attached || section.size.isEmpty) return const [];
    final image = await section.toImage(
      pixelRatio: _fitPixelRatio(section.size, pixelRatio),
    );
    try {
      return await _split(image);
    } finally {
      image.dispose();
    }
  }

  static Future<List<_Piece>> _split(ui.Image image) async {
    final width = image.width;
    final aspectRatio = image.height / width;
    if (aspectRatio <= _maxSectionAspectRatio) {
      final bytes = await _encode(image);
      return bytes == null
          ? const []
          : [_Piece(bytes: bytes, aspectRatio: aspectRatio)];
    }
    // 한 장보다 긴 섹션이다. 이 섹션만 장 높이에 맞춰 나눈다. 자르는 자리가 글줄일 수 있지만
    // 다른 섹션까지 함께 잘리는 것보다 낫다.
    final chunkHeight = math.max(1, (width * _maxSectionAspectRatio).floor());
    final pieces = <_Piece>[];
    for (var top = 0; top < image.height; top += chunkHeight) {
      final height = math.min(chunkHeight, image.height - top);
      if (height <= 0) break;
      final chunk = await _crop(image, top: top, width: width, height: height);
      try {
        final bytes = await _encode(chunk);
        if (bytes != null) {
          pieces.add(_Piece(bytes: bytes, aspectRatio: height / width));
        }
      } finally {
        chunk.dispose();
      }
    }
    return pieces;
  }

  /// 캡처 배율을 [_maxCapturePixels] 안으로 낮춘다. 여유가 있으면 요청값을 그대로 쓴다.
  static double _fitPixelRatio(Size size, double requested) {
    final area = size.width * size.height;
    if (area <= 0) return requested;
    if (area * requested * requested <= _maxCapturePixels) return requested;
    return math.sqrt(_maxCapturePixels / area);
  }

  static Future<Uint8List?> _encode(ui.Image image) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
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

  /// 앱과 같은 글꼴을 실어 둔다.
  ///
  /// PDF 기본 글꼴(Helvetica)은 한글을 그리지 못한다. 지금 그리는 글자는 쪽번호뿐이지만,
  /// 글꼴이 없으면 파일 정보의 한글 제목에서도 경고가 난다. 읽지 못하면 기본 글꼴로 둔다 —
  /// 글꼴 때문에 저장이 실패하는 것이 더 나쁘다.
  static Future<pw.ThemeData?> _theme() async {
    try {
      final data = await rootBundle.load(_fontAsset);
      return pw.ThemeData.withFont(base: pw.Font.ttf(data));
    } on Object {
      return null;
    }
  }

  /// 조각들을 순서대로 흘려 담는다. 한 장에 다 못 들어가는 조각은 다음 장에서 시작한다.
  ///
  /// 쪽번호 말고는 글자를 넣지 않는다. 한글을 그리려면 폰트를 함께 실어야 하는데, 제목·본문은
  /// 이미 캡처 안에 있어 다시 그릴 이유가 없다.
  static Future<Uint8List> _document(String title, List<_Piece> pieces) async {
    final document = pw.Document(title: title, theme: await _theme());
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(
          _marginHorizontal,
          _marginTop,
          _marginHorizontal,
          _marginBottom,
        ),
        footer: (context) => pw.Container(
          height: _footerHeight,
          alignment: pw.Alignment.center,
          child: pw.Text(
            '${context.pageNumber} / ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
        ),
        build: (context) => [
          for (final piece in pieces)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: _sectionGap),
              child: pw.Image(
                pw.MemoryImage(piece.bytes),
                width: _contentWidth,
                height: _contentWidth * piece.aspectRatio,
              ),
            ),
        ],
      ),
    );
    return document.save();
  }
}

/// 종이에 붙일 이미지 한 조각이다. 대개 섹션 하나이고, 긴 섹션만 여러 조각이 된다.
@immutable
final class _Piece {
  const _Piece({required this.bytes, required this.aspectRatio});

  final Uint8List bytes;
  final double aspectRatio;
}
