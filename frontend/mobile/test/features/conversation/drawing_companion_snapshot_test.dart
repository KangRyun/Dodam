import 'package:dodam/features/activity/presentation/screens/activity_screens.dart';
import 'package:dodam/features/child_mode/domain/dodam_costume.dart';
import 'package:dodam/features/child_mode/presentation/widgets/dodam_companion.dart';
import 'package:dodam/features/conversation/conversation.dart';
import 'package:dodam/features/drawing/data/dto/drawing_dtos.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

final _question = AiQuestion(
  messageId: 9001,
  conversationId: 8001,
  sequence: 1,
  text: '오늘 그린 그림을 소개해 줄래?',
  options: [
    AiQuestionOption(
      optionId: 'OPT_1',
      type: 'OPTION',
      label: '좋아',
      value: 'yes',
    ),
  ],
  ttsAvailable: false,
  createdAt: DateTime.utc(2026, 8, 3),
);

void main() {
  test('null·빈 값·unknown 코드는 BASE snapshot으로 정규화한다', () {
    expect(DodamCostume.fromCode(null), DodamCostume.base);
    expect(DodamCostume.fromCode(''), DodamCostume.base);
    expect(DodamCostume.fromCode('UNKNOWN'), DodamCostume.base);
  });

  for (final companion in DodamCostume.values) {
    testWidgets('${companion.code} snapshot은 정확한 asset·이름으로 질문에 표시된다', (
      tester,
    ) async {
      String? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                AiQuestionBubbleOverlay(
                  companion: companion,
                  question: _question,
                  visible: true,
                  selectedOptionId: null,
                  onOptionSelected: (value) => selected = value,
                  showResponseActions: true,
                  submissionStatus: OptionAnswerSubmissionStatus.idle,
                  skipStatus: QuestionSkipStatus.idle,
                  onSkip: () {},
                  endStatus: ConversationEndStatus.idle,
                  onEnd: () {},
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final image = tester.widget<Image>(
        find.byKey(ValueKey('dodam-companion-image-${companion.code}')),
      );
      expect((image.image as AssetImage).assetName, companion.asset);
      expect(
        find.bySemanticsLabel('${companion.label} 질문. ${_question.text}'),
        findsOneWidget,
      );

      final option = find.byKey(const ValueKey('ai-question-option-OPT_1'));
      await tester.ensureVisible(option);
      await tester.tap(option);
      await tester.pump();
      expect(selected, 'OPT_1');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('선택 asset decode 실패는 BASE asset으로 fallback한다', (tester) async {
    await tester.pumpWidget(
      DefaultAssetBundle(
        bundle: _FailingAssetBundle(DodamCostume.dino.asset),
        child: const MaterialApp(
          home: Scaffold(
            body: DodamCompanionAvatar(companion: DodamCostume.dino),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('dodam-companion-image-fallback-BASE')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('ART_DIARY server snapshot은 다른 local 값과 진행 중 rebuild보다 우선한다', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({
      'dodam.child.7.costume': 'OCTOPUS',
    });
    addTearDown(() => const FlutterSecureStorage().deleteAll());
    final companion = ValueNotifier<DodamCostume>(DodamCostume.dino);
    addTearDown(companion.dispose);
    final repository = _ConversationRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<DodamCostume>(
          valueListenable: companion,
          builder: (_, value, _) => DrawingScreen(
            key: const ValueKey('active-drawing'),
            childId: '7',
            sessionId: 100,
            companion: value,
            conversationRepository: repository,
            conversationId: 8001,
            resumeConversation: true,
            questionOptionRevealDelay: Duration.zero,
            noResponseTimeout: const Duration(minutes: 1),
          ),
        ),
      ),
    );
    await _pumpUntil(
      tester,
      find.byKey(const ValueKey('dodam-companion-image-DINO')),
    );

    companion.value = DodamCostume.princess;
    await tester.pump();
    expect(
      find.byKey(const ValueKey('dodam-companion-image-DINO')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('dodam-companion-image-PRINCESS')),
      findsNothing,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(
      MaterialApp(
        home: DrawingScreen(
          childId: '7',
          sessionId: 101,
          companion: DodamCostume.princess,
          conversationRepository: _ConversationRepository(),
          conversationId: 8002,
          resumeConversation: true,
          questionOptionRevealDelay: Duration.zero,
          noResponseTimeout: const Duration(minutes: 1),
        ),
      ),
    );
    await _pumpUntil(
      tester,
      find.byKey(const ValueKey('dodam-companion-image-PRINCESS')),
    );
  });

  testWidgets('사진 HTP 대화도 전달된 snapshot을 사용하고 Canvas·CTA를 가리지 않는다', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(320, 640),
          textScaler: TextScaler.linear(2),
        ),
        child: MaterialApp(
          home: DrawingScreen(
            childId: '7',
            sessionId: 901,
            companion: DodamCostume.octopus,
            conversationRepository: _ConversationRepository(),
            conversationAnswerRepository: _AnswerRepository(),
            conversationId: 8101,
            resumeConversation: true,
            inputMethod: 'UPLOAD',
            activityContext: const DrawingActivityContextDto(
              activityKind: 'HTP',
              htpAssessmentId: 91,
              stepOrder: 1,
              drawingSubject: 'HOUSE',
            ),
            questionOptionRevealDelay: Duration.zero,
            noResponseTimeout: const Duration(minutes: 1),
          ),
        ),
      ),
    );
    await _pumpUntil(
      tester,
      find.byKey(const ValueKey('dodam-companion-image-OCTOPUS')),
    );

    final option = find.byKey(const ValueKey('ai-question-option-OPT_1'));
    final overlayScroll = find.descendant(
      of: find.byKey(const ValueKey('ai-question-overlay-scroll')),
      matching: find.byType(Scrollable),
    );
    // 바깥 화면과 질문 bubble의 중첩 스크롤을 실제 손가락으로 위쪽에 맞춘다.
    await tester.drag(
      // 크레용 셸로 바뀌며 레이아웃 키가 기기 종류별로 나뉘었다
      // (S15P11B209-805). 세로 화면이므로 mobile-portrait 다.
      find.byKey(const ValueKey('drawing-shell-mobile-portrait')),
      const Offset(0, 500),
    );
    await tester.pumpAndSettle();
    await tester.drag(overlayScroll.first, const Offset(0, 500));
    await tester.pumpAndSettle();
    expect(tester.getSize(option).height, greaterThanOrEqualTo(48));
    expect(tester.getCenter(option).dy, inInclusiveRange(0, 640));
    await tester.tap(option);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  int maxFrames = 60,
}) async {
  for (var frame = 0; frame < maxFrames && finder.evaluate().isEmpty; frame++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
  expect(finder, findsOneWidget);
}

final class _ConversationRepository implements ConversationRepository {
  @override
  Future<int> startConversation({
    required int drawingSessionId,
    int? analysisId,
    int? maxQuestionCount,
    required String idempotencyKey,
  }) async => 8001;

  @override
  Future<AiQuestion> requestNextQuestion({
    required int conversationId,
    required NextQuestionRequest request,
    required String idempotencyKey,
  }) async => _question;
}

final class _AnswerRepository implements ConversationAnswerRepository {
  @override
  Future<OptionAnswerResult> submitOptionAnswer({
    required int conversationId,
    required OptionAnswerRequest request,
    required String idempotencyKey,
  }) async => const OptionAnswerResult(answerMessageId: 9101);
}

final class _FailingAssetBundle extends CachingAssetBundle {
  _FailingAssetBundle(this.failedAsset);

  final String failedAsset;

  @override
  Future<ByteData> load(String key) {
    if (key == failedAsset) {
      return Future<ByteData>.error(StateError('decode failed'));
    }
    return rootBundle.load(key);
  }
}
