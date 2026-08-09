import 'package:dodam/features/referral/data/dto/referral_summary_dto.dart';
import 'package:dodam/features/referral/domain/repositories/referral_summary_repository.dart';
import 'package:dodam/features/referral/presentation/screens/referral_summary_screen.dart';
import 'package:dodam/features/referral/referral_feature.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 전문가 의뢰 요약 화면 (S15P11B209-1012).
///
/// 이 화면이 지켜야 하는 것은 배치가 아니라 **순서와 침묵**이다 — 아이가 한 말이 앱의
/// 관찰보다 앞에 오고, 근거가 없으면 지어내지 않는다.
void main() {
  testWidgets('켜져 있으면 요약을 조회해 보여 준다', (tester) async {
    final repository = _Repository();

    await _pump(tester, repository);
    await tester.pumpAndSettle();

    // 2026-08-09 노출을 켰다. 켜진 상태에서 준비 중 안내가 남아 있으면 진입점만 열리고
    //   화면은 빈 채로 보인다 — 스위치와 화면이 어긋나지 않는지 여기서 고정한다.
    expect(ReferralSummaryFeature.enabled, isTrue);
    expect(find.byKey(const ValueKey('referral-summary-disabled')), findsNothing);
    expect(repository.calls, isNotEmpty);
  });

  group('켜졌을 때 (본문 위젯 직접 렌더)', () {
    testWidgets('아이가 한 말이 앱의 관찰보다 위에 온다', (tester) async {
      await _pumpBody(tester, _summary());

      final voice = tester.getTopLeft(find.text('"블록으로 성을 만들었어"'));
      final observation = tester.getTopLeft(find.text('블록 놀이 이야기'));

      // 앵커링을 막는 유일한 장치가 이 순서다. 뒤집히면 전문가가 앱의 가설부터 읽는다.
      expect(voice.dy, lessThan(observation.dy));
    });

    testWidgets('고른 답을 스스로 말한 것으로 표시하지 않는다', (tester) async {
      await _pumpBody(tester, _summary());

      expect(find.text('보기에서 고름'), findsOneWidget);
      expect(find.text('아이가 스스로 말함'), findsOneWidget);
    });

    testWidgets('되풀이된 관찰에 회차 수가 함께 나온다', (tester) async {
      await _pumpBody(tester, _summary());

      // 몇 회차에서 봤는지가 없으면 한 번짜리와 구별되지 않는다.
      expect(find.text('2회차에서 확인'), findsOneWidget);
    });

    testWidgets('안전 신호에 처리 내역이 없으면 그 사실을 적는다', (tester) async {
      await _pumpBody(tester, _summary());

      // 비워 두면 전문가는 방치됐는지 알 수 없다.
      expect(find.text('앱이 취한 처리 내역이 기록되지 않았어요.'), findsOneWidget);
    });

    testWidgets('음성 원본이 있어도 재생 링크를 담지 않는다', (tester) async {
      await _pumpBody(tester, _summary());

      expect(
        find.text('아이 목소리 원본은 앱에 남아 있어요. 이 요약에는 담기지 않아요.'),
        findsOneWidget,
      );
    });

    testWidgets('회차가 없으면 빈 표 대신 안내를 보여 준다', (tester) async {
      await _pumpBody(tester, const ReferralSummaryDto());

      expect(
        find.byKey(const ValueKey('referral-summary-empty')),
        findsOneWidget,
      );
    });
  });

  group('DTO', () {
    test('말이 빈 발화와 제목 없는 관찰은 버린다', () {
      final dto = ReferralSummaryDto.fromJson({
        'sessions': [
          {
            'childVoices': [
              {'text': '  '},
              {'text': '진짜 답', 'spontaneous': true},
            ],
          },
        ],
        'repeatedObservations': [
          {'title': ''},
          {'title': '블록 놀이 이야기', 'occurrenceCount': 2},
        ],
      });

      expect(dto.sessions.single.childVoices.single.text, '진짜 답');
      expect(dto.repeatedObservations.single.title, '블록 놀이 이야기');
    });

    test('아이가 말하지 않은 실제·시점은 UNKNOWN 으로 남는다', () {
      final dto = ReferralSummaryDto.fromJson({
        'sessions': [
          {'headline': '성 만들기'},
        ],
      });

      // 활동 날짜는 사건 날짜의 근거가 아니다 — 짐작해 채우면 없는 사실이 된다.
      expect(dto.sessions.single.realityStatus, 'UNKNOWN');
      expect(dto.sessions.single.timeScope, 'UNKNOWN');
    });
  });
}

Future<void> _pump(WidgetTester tester, _Repository repository) async {
  await tester.pumpWidget(
    MaterialApp(
      home: ReferralSummaryScreen(childId: 7, repository: repository),
    ),
  );
  await tester.pump();
}

Future<void> _pumpBody(WidgetTester tester, ReferralSummaryDto summary) async {
  // 카드가 많아 기본 600x800 에서는 아래쪽이 잘려 find 가 실패한다.
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: ReferralSummaryBody(summary: summary)),
    ),
  );
  await tester.pump();
}

ReferralSummaryDto _summary() => ReferralSummaryDto(
  childDisplayName: '별이',
  generatedAt: DateTime.utc(2026, 8, 8),
  purpose: '전문가 상담에 필요한 기록을 모아 정리한 자료예요.',
  sessions: [
    ReferralSessionDto(
      reportId: 1,
      activityDate: DateTime.utc(2026, 8, 7),
      headline: '블록 성 이야기',
      childVoices: const [
        ReferralChildVoiceDto(text: '블록으로 성을 만들었어', spontaneous: true),
        ReferralChildVoiceDto(text: '재밌었어', elicitationType: 'OPTION'),
      ],
    ),
  ],
  repeatedObservations: [
    ReferralRepeatedObservationDto(
      title: '블록 놀이 이야기',
      occurrenceCount: 2,
      firstSeenOn: DateTime.utc(2026, 8, 1),
      lastSeenOn: DateTime.utc(2026, 8, 7),
    ),
  ],
  safetySignals: const [
    ReferralSafetySignalDto(reasonCode: 'SELF_HARM_MENTION'),
  ],
  answerComposition: const ReferralAnswerCompositionDto(
    spokenAnswerCount: 1,
    optionAnswerCount: 1,
  ),
  voiceRecordingAvailable: true,
  notIncluded: const ['색·크기 해석'],
  reviewNotice: '공유 전에 아이 이름이 들어갔는지 확인해 주세요.',
);

final class _Repository implements ReferralSummaryRepository {
  final List<int> calls = [];

  @override
  Future<ReferralSummaryDto> getReferralSummary(
    int childId, {
    int? sessions,
  }) async {
    calls.add(childId);
    return const ReferralSummaryDto();
  }
}
