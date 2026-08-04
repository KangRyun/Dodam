import 'dart:io';
import 'dart:typed_data';

import 'package:dodam/features/drawing/data/disk_pending_htp_photo_store.dart';
import 'package:dodam/features/drawing/domain/pending_htp_photo.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late DiskPendingHtpPhotoStore store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('htp_pending_test');
    store = DiskPendingHtpPhotoStore(rootDirectory: () async => root);
  });

  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  PendingHtpPhoto photo(String subject, List<int> bytes) => PendingHtpPhoto(
    subject: subject,
    bytes: Uint8List.fromList(bytes),
    mimeType: 'image/jpeg',
    width: 1200,
    height: 900,
    fileName: '$subject.jpg',
  );

  test('보관한 사진을 주제 순서(HOUSE→TREE→PERSON)로 복원한다', () async {
    await store.save(7, photo('PERSON', [3, 3, 3]));
    await store.save(7, photo('HOUSE', [1, 1, 1]));
    await store.save(7, photo('TREE', [2, 2, 2]));

    final loaded = await store.load(7);

    expect(loaded.map((p) => p.subject), ['HOUSE', 'TREE', 'PERSON']);
    expect(loaded.first.bytes, [1, 1, 1]);
    expect(loaded.first.mimeType, 'image/jpeg');
    expect(loaded.first.width, 1200);
    expect(loaded.first.height, 900);
    expect(loaded.first.fileName, 'HOUSE.jpg');
  });

  test('같은 주제 재촬영은 이전 사진을 덮어쓴다', () async {
    await store.save(7, photo('HOUSE', [1, 1, 1]));
    await store.save(7, photo('HOUSE', [9, 9, 9, 9]));

    final loaded = await store.load(7);

    expect(loaded, hasLength(1));
    expect(loaded.single.bytes, [9, 9, 9, 9]);
  });

  test('remove는 해당 주제만 지운다', () async {
    await store.save(7, photo('HOUSE', [1]));
    await store.save(7, photo('TREE', [2]));

    await store.remove(7, 'HOUSE');

    final loaded = await store.load(7);
    expect(loaded.map((p) => p.subject), ['TREE']);
  });

  test('clear는 아동의 보관 사진을 모두 지운다', () async {
    await store.save(7, photo('HOUSE', [1]));
    await store.save(7, photo('TREE', [2]));

    await store.clear(7);

    expect(await store.load(7), isEmpty);
  });

  test('아동별로 분리 보관한다', () async {
    await store.save(7, photo('HOUSE', [1]));
    await store.save(8, photo('HOUSE', [2]));

    expect((await store.load(7)).single.bytes, [1]);
    expect((await store.load(8)).single.bytes, [2]);
  });

  test('메타가 없는 반쪽 항목은 건너뛴다', () async {
    await store.save(7, photo('HOUSE', [1]));
    // 메타만 삭제해 바이트만 남은 손상 상태를 만든다.
    final metaFile = File('${root.path}/htp_pending_photos/7/HOUSE.json');
    await metaFile.delete();

    expect(await store.load(7), isEmpty);
  });

  test('보관이 없으면 빈 목록을 돌려준다', () async {
    expect(await store.load(99), isEmpty);
  });
}
