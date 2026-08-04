import 'dart:typed_data';

import 'package:dodam/features/drawing/domain/pending_htp_photo.dart';
import 'package:dodam/features/drawing/domain/photo_picker_adapter.dart';
import 'package:dodam/features/drawing/presentation/screens/htp_photo_precapture_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 유효한 1x1 PNG. 시그니처 검증을 통과하고 Image.memory로 디코딩된다.
final _png = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, //
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, //
  0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41, //
  0x54, 0x78, 0x9C, 0x62, 0x00, 0x01, 0x00, 0x00, //
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, //
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, //
  0x42, 0x60, 0x82,
]);

final class _MemoryStore implements PendingHtpPhotoStore {
  final Map<int, Map<String, PendingHtpPhoto>> _byChild = {};

  @override
  Future<void> save(int childId, PendingHtpPhoto photo) async {
    (_byChild[childId] ??= {})[photo.subject] = photo;
  }

  @override
  Future<List<PendingHtpPhoto>> load(int childId) async {
    final map = _byChild[childId] ?? {};
    return [
      for (final s in const ['HOUSE', 'TREE', 'PERSON']) ?map[s],
    ];
  }

  @override
  Future<void> remove(int childId, String subject) async {
    _byChild[childId]?.remove(subject);
  }

  @override
  Future<void> clear(int childId) async {
    _byChild.remove(childId);
  }
}

PickedPhoto _pngPhoto(String subject) =>
    PickedPhoto(bytes: _png, fileName: '$subject.png', mimeType: 'image/png');

void main() {
  testWidgets('집→나무→사람을 차례로 촬영·확인해 보관하고 완료를 알린다', (tester) async {
    final store = _MemoryStore();
    final acquired = <String>[];
    List<PendingHtpPhoto>? completed;

    await tester.pumpWidget(
      MaterialApp(
        home: HtpPhotoPrecaptureScreen(
          childId: 7,
          store: store,
          dimensionReader: (_) async => (1200, 900),
          acquirePhoto: (context, subject) async {
            acquired.add(subject);
            return _pngPhoto(subject);
          },
          onCompleted: (photos) => completed = photos,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 첫 주제는 카메라 열기를 눌러 촬영한다(마운트 자동 오픈 없음).
    await tester.tap(find.byKey(const ValueKey('htp-precapture-open-camera')));
    await tester.pumpAndSettle();

    // 집 미리보기 → 사용
    expect(find.text('집 사진, 이대로 쓸까요?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('htp-precapture-use')));
    await tester.pumpAndSettle();

    // 나무 미리보기 → 사용
    expect(find.text('나무 사진, 이대로 쓸까요?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('htp-precapture-use')));
    await tester.pumpAndSettle();

    // 사람 미리보기 → 사용 → 완료
    expect(find.text('사람 사진, 이대로 쓸까요?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('htp-precapture-use')));
    await tester.pumpAndSettle();

    expect(acquired, ['HOUSE', 'TREE', 'PERSON']);
    expect(completed, isNotNull);
    expect(completed!.map((p) => p.subject), ['HOUSE', 'TREE', 'PERSON']);
    expect(await store.load(7), hasLength(3));
  });

  testWidgets('다시 찍기는 같은 주제를 다시 촬영한다', (tester) async {
    final store = _MemoryStore();
    final acquired = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: HtpPhotoPrecaptureScreen(
          childId: 7,
          store: store,
          dimensionReader: (_) async => (1200, 900),
          acquirePhoto: (context, subject) async {
            acquired.add(subject);
            return _pngPhoto(subject);
          },
          onCompleted: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('htp-precapture-open-camera')));
    await tester.pumpAndSettle();

    expect(find.text('집 사진, 이대로 쓸까요?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('htp-precapture-retake')));
    await tester.pumpAndSettle();

    // 집을 두 번 촬영했고 아직 보관 전이다.
    expect(acquired, ['HOUSE', 'HOUSE']);
    expect(await store.load(7), isEmpty);
    expect(find.text('집 사진, 이대로 쓸까요?'), findsOneWidget);
  });

  testWidgets('첫 주제에서 그만두면 onCancelled를 호출한다', (tester) async {
    final store = _MemoryStore();
    var cancelled = false;

    await tester.pumpWidget(
      MaterialApp(
        home: HtpPhotoPrecaptureScreen(
          childId: 7,
          store: store,
          dimensionReader: (_) async => (1200, 900),
          // 취소(null 반환) → idle 상태의 시작 화면이 뜬다.
          acquirePhoto: (context, subject) async => null,
          onCompleted: (_) {},
          onCancelled: () => cancelled = true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('htp-precapture-cancel')));
    await tester.pump();

    expect(cancelled, isTrue);
  });
}
