import 'dart:convert';
import 'dart:typed_data';

import 'package:dodam/core/network/api_page.dart';
import 'package:dodam/features/activity/data/dto/activity_dtos.dart';
import 'package:dodam/features/activity/domain/repositories/activity_repository.dart';
import 'package:dodam/features/child/data/dto/child_dtos.dart';
import 'package:dodam/features/child_mode/presentation/screens/child_gallery_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _child = ChildSummaryDto(
  childId: 7,
  nickname: '도담',
  birthDate: '2020-01-01',
  age: 6,
  profileImageUrl: null,
  preferredCharacter: null,
  questionDifficulty: 'EASY',
  tutorialStatus: 'DONE',
  relationshipType: 'PARENT',
  recentActivity: ChildRecentActivityDto(
    lastActivityAt: null,
    totalActivityCount: 0,
  ),
);

ActivitySummaryDto _artwork(int id, String title, {String? thumbnailUrl}) =>
    ActivitySummaryDto(
      activityId: id,
      title: title,
      drawingType: const ActivityDrawingTypeDto(
        code: 'ART_DIARY',
        name: '그림일기',
      ),
      inputMethod: 'TOUCH',
      sessionStatus: 'COMPLETED',
      selectedEmotions: const [],
      thumbnailUrl: thumbnailUrl ?? '/api/v1/drawing-assets/$id/file',
      analysisStatus: 'COMPLETED',
      report: null,
      startedAt: '2026-07-30T09:00:00Z',
      completedAt: '2026-07-30T09:20:00Z',
    );

/// 1x1 투명 PNG — 인증 이미지 로딩이 유효한 바이트를 받도록.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
);

class _FakeActivityRepository implements ActivityRepository {
  _FakeActivityRepository(this.artworks);
  final List<ActivitySummaryDto> artworks;

  @override
  Future<ApiPage<ActivitySummaryDto>> getActivities(
    int childId, {
    ActivityFilterDto filter = const ActivityFilterDto(),
  }) async => ApiPage<ActivitySummaryDto>(
    content: artworks,
    page: 0,
    size: 20,
    totalElements: artworks.length,
    totalPages: 1,
    hasNext: false,
  );

  @override
  Future<Uint8List> downloadImage(String url) async => _png;

  @override
  Future<ActivityDetailDto> getActivity(int activityId) =>
      throw UnimplementedError();
  @override
  Future<void> deleteActivity(int activityId) => throw UnimplementedError();
  @override
  Future<List<ActivityConversationMessageDto>> getConversationMessages(
    int conversationId,
  ) => throw UnimplementedError();
}

Widget _wrap(Widget child) => MaterialApp(home: child);

void main() {
  testWidgets('썸네일이 있는 그림을 액자와 명패로 전시한다', (tester) async {
    final repository = _FakeActivityRepository([
      _artwork(1, '우리 가족'),
      _artwork(2, '무지개'),
    ]);

    await tester.pumpWidget(
      _wrap(ChildGalleryScreen(child: _child, repository: repository)),
    );
    await tester.pumpAndSettle();

    expect(find.text('도담의 그림 전시관'), findsOneWidget);
    expect(find.text('내가 그린 그림 2점'), findsOneWidget);
    expect(find.text('우리 가족'), findsOneWidget);
    expect(find.text('무지개'), findsOneWidget);
  });

  testWidgets('썸네일이 없는 활동은 전시하지 않아 빈 상태를 보여준다', (tester) async {
    final repository = _FakeActivityRepository([
      _artwork(1, '제목만 있는 활동', thumbnailUrl: ''),
    ]);

    await tester.pumpWidget(
      _wrap(ChildGalleryScreen(child: _child, repository: repository)),
    );
    await tester.pumpAndSettle();

    expect(find.text('아직 전시된 그림이 없어요'), findsOneWidget);
    expect(find.text('제목만 있는 활동'), findsNothing);
  });

  testWidgets('액자를 누르면 전시 홀(상세)로 들어가 위치를 보여준다', (tester) async {
    final repository = _FakeActivityRepository([
      _artwork(1, '우리 가족'),
      _artwork(2, '무지개'),
    ]);

    await tester.pumpWidget(
      _wrap(ChildGalleryScreen(child: _child, repository: repository)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('우리 가족').first);
    await tester.pumpAndSettle();

    expect(find.text('1 / 2'), findsOneWidget);
    expect(find.textContaining('참 멋지게 그렸다'), findsOneWidget);
  });
}
