import 'package:dodam/features/activity/data/dto/activity_dtos.dart';
import 'package:dodam/features/guardian/presentation/widgets/mind_calendar_card.dart';
import 'package:dodam/features/guardian/presentation/widgets/mind_emotion.dart';
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
}
