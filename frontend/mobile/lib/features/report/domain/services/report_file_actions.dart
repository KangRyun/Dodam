import 'dart:typed_data';

import 'package:flutter/widgets.dart';

/// 인증 다운로드가 끝난 리포트 PDF를 기기 저장소나 시스템 공유 화면으로 전달한다.
abstract interface class ReportFileActions {
  Future<bool> save({required String fileName, required Uint8List bytes});

  Future<void> share({
    required String fileName,
    required Uint8List bytes,
    Rect? shareOrigin,
  });
}
