import 'dart:convert';
import 'dart:io';

import '../domain/pending_htp_photo.dart';

/// 기기 파일 시스템에 HTP 선촬영 사진을 보관하는 [PendingHtpPhotoStore] 구현.
///
/// 루트 디렉터리는 주입받는다 — 운영에서는 `path_provider`의 문서 디렉터리를,
/// 테스트에서는 임시 디렉터리를 넘겨 플랫폼 채널 없이 검증한다.
/// 주제별로 바이트 파일(`<subject>.bin`)과 메타 파일(`<subject>.json`)을 쓴다.
class DiskPendingHtpPhotoStore implements PendingHtpPhotoStore {
  DiskPendingHtpPhotoStore({required this.rootDirectory});

  /// 보관 루트 디렉터리 resolver. 운영은 `path_provider` 문서 디렉터리,
  /// 테스트는 임시 디렉터리를 넘긴다.
  final Future<Directory> Function() rootDirectory;

  /// 주제 순서. 복원 시 이 순서로 돌려준다.
  static const List<String> subjectsInOrder = ['HOUSE', 'TREE', 'PERSON'];

  Future<Directory> _childDir(int childId) async {
    final root = await rootDirectory();
    final dir = Directory('${root.path}/htp_pending_photos/$childId');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  File _binFile(Directory dir, String subject) =>
      File('${dir.path}/$subject.bin');
  File _metaFile(Directory dir, String subject) =>
      File('${dir.path}/$subject.json');

  @override
  Future<void> save(int childId, PendingHtpPhoto photo) async {
    final dir = await _childDir(childId);
    // 메타를 먼저 지워, 바이트만 남고 메타가 없는 반쪽 상태로 읽히지 않게 한다.
    final meta = _metaFile(dir, photo.subject);
    if (meta.existsSync()) await meta.delete();
    await _binFile(dir, photo.subject).writeAsBytes(photo.bytes, flush: true);
    await meta.writeAsString(
      jsonEncode({
        'mimeType': photo.mimeType,
        'width': photo.width,
        'height': photo.height,
        'fileName': photo.fileName,
      }),
      flush: true,
    );
  }

  @override
  Future<List<PendingHtpPhoto>> load(int childId) async {
    final dir = await _childDir(childId);
    final result = <PendingHtpPhoto>[];
    for (final subject in subjectsInOrder) {
      final bin = _binFile(dir, subject);
      final meta = _metaFile(dir, subject);
      if (!bin.existsSync() || !meta.existsSync()) continue;
      try {
        final bytes = await bin.readAsBytes();
        final map = jsonDecode(await meta.readAsString()) as Map<String, dynamic>;
        result.add(
          PendingHtpPhoto(
            subject: subject,
            bytes: bytes,
            mimeType: map['mimeType'] as String,
            width: (map['width'] as num).toInt(),
            height: (map['height'] as num).toInt(),
            fileName: map['fileName'] as String,
          ),
        );
      } on Object {
        // 손상·형식 불일치 항목은 건너뛴다(복원이 실패로 끊기지 않게).
      }
    }
    return result;
  }

  @override
  Future<void> remove(int childId, String subject) async {
    final dir = await _childDir(childId);
    final bin = _binFile(dir, subject);
    final meta = _metaFile(dir, subject);
    if (bin.existsSync()) await bin.delete();
    if (meta.existsSync()) await meta.delete();
  }

  @override
  Future<void> clear(int childId) async {
    final root = await rootDirectory();
    final dir = Directory('${root.path}/htp_pending_photos/$childId');
    if (dir.existsSync()) await dir.delete(recursive: true);
  }
}
