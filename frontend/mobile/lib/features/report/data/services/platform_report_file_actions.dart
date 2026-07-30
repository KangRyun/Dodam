import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/widgets.dart';
import 'package:share_plus/share_plus.dart';

import '../../domain/services/report_file_actions.dart';

/// 리포트 PDF를 플랫폼 파일 선택기와 공유 화면에 전달하는 구현체다.
final class PlatformReportFileActions implements ReportFileActions {
  const PlatformReportFileActions();

  @override
  Future<bool> save({
    required String fileName,
    required Uint8List bytes,
  }) async {
    final baseName = fileName.endsWith('.pdf')
        ? fileName.substring(0, fileName.length - 4)
        : fileName;
    final savedPath = await FileSaver.instance.saveAs(
      name: baseName,
      bytes: bytes,
      fileExtension: 'pdf',
      mimeType: MimeType.pdf,
    );
    return savedPath != null;
  }

  @override
  Future<void> share({
    required String fileName,
    required Uint8List bytes,
    Rect? shareOrigin,
  }) async {
    await SharePlus.instance.share(
      ShareParams(
        title: '도담 관찰 리포트',
        files: [
          XFile.fromData(bytes, mimeType: 'application/pdf', name: fileName),
        ],
        sharePositionOrigin: shareOrigin,
      ),
    );
  }
}
