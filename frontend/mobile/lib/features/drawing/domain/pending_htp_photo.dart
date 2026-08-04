import 'dart:typed_data';

/// HTP 주제 3개를 처리 전에 미리 촬영해 기기에 보관해 둔 사진 한 장
/// (S15P11B209-872). 백엔드는 주제별로 순서대로만 업로드를 받으므로, 선촬영한
/// 나무·사람 사진은 각 주제 차례가 올 때까지 여기에 보관했다가 꺼내 올린다.
class PendingHtpPhoto {
  const PendingHtpPhoto({
    required this.subject,
    required this.bytes,
    required this.mimeType,
    required this.width,
    required this.height,
    required this.fileName,
  });

  /// HTP 주제 코드: `HOUSE` · `TREE` · `PERSON`.
  final String subject;
  final Uint8List bytes;
  final String mimeType;
  final int width;
  final int height;
  final String fileName;
}

/// HTP 선촬영 사진을 각 주제 처리 시점까지 기기에 보관·복원한다.
///
/// 아동당 활성 HTP 활동은 하나뿐이므로 `childId`로 묶는다. 앱이 중간에 종료돼도
/// 남은 주제 사진을 복원해 이어서 처리할 수 있어야 한다(디스크 보관).
abstract interface class PendingHtpPhotoStore {
  /// 한 주제 사진을 보관한다(같은 주제 재촬영 시 덮어쓴다).
  Future<void> save(int childId, PendingHtpPhoto photo);

  /// 보관된 사진을 주제 순서(HOUSE→TREE→PERSON)로 돌려준다.
  Future<List<PendingHtpPhoto>> load(int childId);

  /// 한 주제 사진을 지운다(업로드 성공 뒤 호출).
  Future<void> remove(int childId, String subject);

  /// 아동의 보관 사진을 모두 지운다(활동 완료·취소 시).
  Future<void> clear(int childId);
}
