import 'package:dodam/core/network/api_page.dart';
import 'package:dodam/features/activity/data/dto/activity_dtos.dart';
import 'package:dodam/features/activity/domain/repositories/activity_repository.dart';
import 'package:dodam/features/guardian/presentation/widgets/mind_calendar_card.dart';
import 'package:dodam/features/guardian/presentation/widgets/mind_emotion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ActivitySummaryDto _activity({
  required int id,
  required String startedAt,
  required List<String> emotions,
}) => ActivitySummaryDto(
  activityId: id,
  title: '나무 그리기',
  drawingType: const ActivityDrawingTypeDto(code: 'HTP', name: '집-나무-사람'),
  inputMethod: 'CANVAS',
  sessionStatus: 'COMPLETED',
  selectedEmotions: emotions,
  thumbnailUrl: null,
  analysisStatus: 'SUCCESS',
  report: null,
  startedAt: startedAt,
  completedAt: null,
);

void main() {
  group('reduceDailyEmotions', () {
    test('하루 한 활동이면 그 활동의 감정을 그 날짜에 매핑한다', () {
      final result = reduceDailyEmotions([
        _activity(id: 1, startedAt: '2026-07-14T10:00:00', emotions: ['HAPPY']),
      ], 2026, 7);

      expect(result[14], MindEmotion.happy);
      expect(result.containsKey(13), isFalse);
    });

    test('하루에 여러 활동이면 마지막(startedAt 최신) 활동의 감정을 쓴다', () {
      final result = reduceDailyEmotions([
        _activity(id: 1, startedAt: '2026-07-14T09:00:00', emotions: ['SAD']),
        _activity(id: 2, startedAt: '2026-07-14T18:00:00', emotions: ['ANGRY']),
        _activity(id: 3, startedAt: '2026-07-14T12:00:00', emotions: ['CALM']),
      ], 2026, 7);

      expect(result[14], MindEmotion.angry);
    });

    test('마지막 활동의 감정이 표시 대상이 아니면 그 날은 기록 없음이다', () {
      final result = reduceDailyEmotions([
        _activity(id: 1, startedAt: '2026-07-14T09:00:00', emotions: ['HAPPY']),
        _activity(
          id: 2,
          startedAt: '2026-07-14T20:00:00',
          emotions: ['UNKNOWN'],
        ),
      ], 2026, 7);

      // 마지막 활동이 UNKNOWN이므로 이전 HAPPY로 되돌리지 않는다.
      expect(result.containsKey(14), isFalse);
    });

    test('감정이 비어 있으면 얼굴을 그리지 않는다', () {
      final result = reduceDailyEmotions([
        _activity(id: 1, startedAt: '2026-07-14T09:00:00', emotions: []),
      ], 2026, 7);

      expect(result.containsKey(14), isFalse);
    });

    test('다른 달 활동은 무시한다', () {
      final result = reduceDailyEmotions([
        _activity(id: 1, startedAt: '2026-06-30T10:00:00', emotions: ['HAPPY']),
        _activity(id: 2, startedAt: '2026-08-01T10:00:00', emotions: ['SAD']),
      ], 2026, 7);

      expect(result, isEmpty);
    });

    test('SCARED는 불안 표정으로 매핑된다', () {
      final result = reduceDailyEmotions([
        _activity(
          id: 1,
          startedAt: '2026-07-03T10:00:00',
          emotions: ['SCARED'],
        ),
      ], 2026, 7);

      expect(result[3], MindEmotion.scared);
    });
  });

  // 헤더 겹침 회귀(S15P11B209-787): 좁은 카드 폭에서 연·월 / 제목 / 활동수가
  // 서로 겹치면 안 된다. 옛 Stack 구조는 가운데 제목이 연·월 위로 올라타
  // 겹쳤다(Stack overflow는 예외를 던지지 않아 기존 overflow 테스트로는 못 잡음).
  group('마음 달력 헤더 레이아웃', () {
    Future<void> pumpCardAt(WidgetTester tester, double width) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: width,
                height: 520,
                child: MindCalendarCard(
                  childId: 1,
                  repository: _EmptyActivityRepository(),
                  childName: '도담이',
                  initialMonth: DateTime(2026, 8),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('좁은 폭(360)에서 연·월과 제목이 가로로 겹치지 않는다', (tester) async {
      await pumpCardAt(tester, 360);

      final monthRect = tester.getRect(find.text('2026년 8월'));
      final titleRect = tester.getRect(find.text('이번 달 마음 달력'));

      // 제목은 연·월 오른쪽에 놓여야 한다(겹치면 title.left < month.right).
      expect(
        titleRect.left,
        greaterThanOrEqualTo(monthRect.right),
        reason: '제목이 연·월 텍스트와 겹쳤다(옛 Stack 회귀).',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('넓은 폭(560)에서도 연·월과 제목이 겹치지 않고 활동수가 오른쪽 끝에 있다', (
      tester,
    ) async {
      await pumpCardAt(tester, 560);

      final monthRect = tester.getRect(find.text('2026년 8월'));
      final titleRect = tester.getRect(find.text('이번 달 마음 달력'));
      // 활동 합산은 Text.rich라 findRichText로 잡는다.
      final countRect = tester.getRect(
        find.textContaining('활동', findRichText: true),
      );

      expect(titleRect.left, greaterThanOrEqualTo(monthRect.right));
      expect(countRect.left, greaterThanOrEqualTo(titleRect.right));
      expect(tester.takeException(), isNull);
    });
  });
}

/// 헤더 레이아웃만 검증하므로 활동은 비운다.
final class _EmptyActivityRepository implements ActivityRepository {
  @override
  Future<ApiPage<ActivitySummaryDto>> getActivities(
    int childId, {
    ActivityFilterDto filter = const ActivityFilterDto(),
  }) async => const ApiPage<ActivitySummaryDto>(
    content: [],
    page: 0,
    size: 8,
    totalElements: 0,
    totalPages: 1,
    hasNext: false,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
