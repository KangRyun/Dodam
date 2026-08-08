import 'dart:io';
import 'dart:ui' as ui;

import 'package:dodam/design_system/design_system.dart';
import 'package:dodam/features/report/data/dto/diary_insights_dto.dart';
import 'package:dodam/features/report/data/dto/screening_summary_dto.dart';
import 'package:dodam/features/report/presentation/widgets/diary_report_v2.dart';
import 'package:dodam/features/report/presentation/widgets/screening_summary_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 실제 위젯이 그린 리포트 화면을 PNG 로 남긴다.
///
/// 검증이 아니라 **눈으로 보기 위한** 테스트다. 손으로 그린 시안은 실제 화면과 다르게
/// 나오기 마련이라, 앱이 쓰는 위젯·색·폰트 그대로 렌더해 두고 그것만 본다.
///
/// 결과는 `build/screenshots/` 에 남는다. 실행:
/// `flutter test test/features/report/diary_report_screenshot_test.dart`
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // flutter test 는 기본적으로 폰트를 싣지 않아 한글이 네모로 나온다. 앱이 번들한
    //   NanumSquareNeo 를 직접 올려 실제 화면과 같은 글자를 그린다.
    final loader = FontLoader(AppFontFamily.body);
    for (final path in const [
      'assets/fonts/NanumSquareNeo-Regular.ttf',
      'assets/fonts/NanumSquareNeo-Bold.ttf',
      'assets/fonts/NanumSquareNeo-ExtraBold.ttf',
    ]) {
      loader.addFont(
        File(path).readAsBytes().then((bytes) => ByteData.view(bytes.buffer)),
      );
    }
    await loader.load();

    // 아이콘도 폰트다. 올리지 않으면 화면의 아이콘이 전부 빈 네모로 찍혀, 스크린샷이
    //   실제 앱과 다르게 보인다. Flutter SDK 가 들고 있는 파일을 그대로 쓴다.
    final iconFont = File(
      '${Platform.environment['FLUTTER_ROOT'] ?? _flutterRootFromExecutable()}'
      '/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (iconFont.existsSync()) {
      await (FontLoader('MaterialIcons')
            ..addFont(
              iconFont.readAsBytes().then((bytes) => ByteData.view(bytes.buffer)),
            ))
          .load();
    }
  });

  testWidgets('그림일기 리포트 본문을 PNG 로 남긴다', (tester) async {
    await _capture(
      tester,
      'diary-report-v2.png',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DiaryReportV2Body(insights: _insights),
          const SizedBox(height: AppSpacing.lg),
          ScreeningSummaryCard(summary: _screening),
        ],
      ),
    );
  });
}

/// FLUTTER_ROOT 환경변수가 없을 때 실행 파일 위치에서 SDK 경로를 되짚는다.
String _flutterRootFromExecutable() {
  // .../flutter/bin/cache/dart-sdk/bin/dart → .../flutter
  final parts = Platform.resolvedExecutable.replaceAll(r'\', '/').split('/');
  final index = parts.lastIndexOf('bin');
  return index <= 0 ? '' : parts.sublist(0, index - 3).join('/');
}

/// 위젯을 실제 크기대로 그려 PNG 로 저장한다.
Future<void> _capture(WidgetTester tester, String fileName, Widget child) async {
  final key = GlobalKey();
  // 폭은 흔한 휴대폰 폭, 높이는 넉넉히 잡고 실제 그린 높이만큼만 잘라 낸다.
  tester.view.physicalSize = const Size(1170, 9000);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: AppFontFamily.body,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.leaf,
          surface: AppColors.surface,
        ),
        scaffoldBackgroundColor: AppColors.canvas,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: RepaintBoundary(
            key: key,
            child: Container(
              color: AppColors.canvas,
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: child,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  // ⚠️ 진짜 비동기 작업은 **전부** runAsync 안에서 한다. 위젯 테스트는 가짜 시간에서
  //    돌기 때문에, 파일 생성이나 이미지 인코딩을 밖에서 await 하면 그 Future 가 영원히
  //    끝나지 않고 테스트가 그대로 멈춘다(디렉터리 하나 만드는 줄에서 10분 타임아웃이 났다).
  final file = File('build/screenshots/$fileName');
  int written = 0;
  await tester.runAsync(() async {
    await file.parent.create(recursive: true);
    final ui.Image image = await boundary.toImage(pixelRatio: 2);
    final ByteData? png = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = png!.buffer.asUint8List();
    await file.writeAsBytes(bytes);
    written = bytes.length;
  });
  expect(written, greaterThan(0));
}

const _insights = DiaryInsightsDto(
  storySnapshot: DiaryStorySnapshotDto(
    headline: '동생이 블록탑을 무너뜨려 화가 난 이야기',
    summary: '아이는 동생이 블록탑을 무너뜨린 일과, 엄마에게 말했지만 동생만 안아 준 장면을 이어서 들려주었어요.',
    mainEvent: '동생이 블록탑을 무너뜨림',
  ),
  narrativeFlow: [
    DiaryNarrativeStepDto(stepType: 'EVENT', text: '동생이 블록탑을 무너뜨림'),
    DiaryNarrativeStepDto(stepType: 'CHILD_ACTION', text: '엄마에게 말함'),
    DiaryNarrativeStepDto(stepType: 'OTHER_RESPONSE', text: '엄마가 동생을 안아 줌'),
    DiaryNarrativeStepDto(stepType: 'WISH', text: '엄마가 자기 이야기도 들어주기를 바람'),
  ],
  childVoiceItems: [
    DiaryChildVoiceDto(
      text: '동생이 내 블록 무너뜨려서 진짜 화났어',
      elicitationType: 'OPEN_INVITATION',
      answerType: 'VOICE_ANSWER',
    ),
    DiaryChildVoiceDto(
      text: '엄마한테 말했는데 동생만 안아줬어',
      elicitationType: 'CUED_INVITATION',
      answerType: 'VOICE_ANSWER',
    ),
    DiaryChildVoiceDto(
      text: '속상해',
      elicitationType: 'MULTIPLE_CHOICE',
      answerType: 'OPTION_ANSWER',
    ),
    DiaryChildVoiceDto(
      text: '엄마가 내 얘기도 들어줬으면 좋겠어',
      elicitationType: 'CUED_INVITATION',
      answerType: 'VOICE_ANSWER',
    ),
  ],
  sessionObservations: [
    DiarySessionObservationDto(
      title: '동생과 있었던 일을 순서대로 이야기했어요',
      description: '이번 활동에서 아이는 일어난 일과 자기가 한 행동, 엄마의 반응을 이어서 설명했어요.',
      scopeText: '이번 활동에서 확인된 모습이에요.',
    ),
    DiarySessionObservationDto(
      title: '자기 이야기를 들어 주길 바라는 마음을 말했어요',
      description: "엄마가 동생을 안아 준 장면 뒤에 '내 얘기도 들어줬으면 좋겠어'라고 말했어요.",
      insightType: 'SESSION_HYPOTHESIS',
      domain: 'RELATIONSHIP',
      hypothesis: '이번 이야기에서는 억울함을 알아주길 바라는 마음이 있었을 수 있어요.',
      alternativeExplanations: [
        '무너진 블록을 다시 쌓고 싶은 마음이 더 컸을 수도 있어요.',
        '그날따라 엄마와 둘이 있고 싶었을 수도 있어요.',
      ],
      scopeText: '이번 활동에서 확인된 모습이에요.',
    ),
  ],
  caregiverQuestions: [
    DiaryCaregiverQuestionDto(
      question: '엄마한테 말했을 때 어떤 말을 하고 싶었어?',
      purpose: '아이가 하려던 말을 아이 표현으로 더 들어보기',
    ),
    DiaryCaregiverQuestionDto(
      question: '블록이 무너졌을 때 제일 속상했던 건 뭐였어?',
      purpose: '화가 난 이유를 아이 말로 확인하기',
    ),
  ],
  listeningTip: '누가 잘못했는지 가리기 전에, 아이가 무엇을 알아주길 바랐는지 먼저 들어주세요.',
  developmentalObservations: [
    DiaryDevelopmentalObservationDto(
      domain: 'NARRATIVE_LANGUAGE',
      status: 'OBSERVED_THIS_SESSION',
      ageContext: '이 시기에는 들었거나 만든 이야기를 두 사건 이상으로 이어 말하는 표현이 발달해 가요.',
      observation: '이번 활동에서 아이는 있었던 일과 그다음 행동을 이어서 이야기했어요.',
      scopeText: '이번 활동에서 확인된 표현이며, 전체 발달 수준을 평가한 결과가 아니에요.',
      sourceIds: ['CDC_5Y_MILESTONES', 'CDC_MILESTONE_LIMITATION'],
    ),
    DiaryDevelopmentalObservationDto(
      domain: 'EMOTION_EXPRESSION',
      status: 'PARTIALLY_OBSERVED',
      ageContext: '감정을 말이나 선택으로 표현했는지 이번 활동에서만 살펴봐요.',
      observation: '이번 활동에서 아이는 감정을 보기에서 골랐어요. 말로 설명하지는 않았어요.',
      scopeText: '이번 활동에서 확인된 표현이며, 전체 발달 수준을 평가한 결과가 아니에요.',
    ),
    DiaryDevelopmentalObservationDto(
      domain: 'SOCIAL_UNDERSTANDING',
      status: 'OBSERVED_THIS_SESSION',
      ageContext: '이 시기에는 이야기 속 인물과 장소를 함께 말하는 표현이 늘어갈 수 있어요.',
      observation: '이번 활동에서 아이는 함께 있던 사람이 한 행동도 이야기했어요.',
      scopeText: '이번 활동에서 확인된 표현이며, 전체 발달 수준을 평가한 결과가 아니에요.',
      sourceIds: ['ASHA_COMM_4_5', 'CDC_MILESTONE_LIMITATION'],
    ),
    DiaryDevelopmentalObservationDto(
      domain: 'SELF_REFLECTION',
      status: 'OBSERVED_THIS_SESSION',
      ageContext: '바라는 것이나 이유를 말했는지 이번 활동에서만 살펴봐요.',
      observation: '이번 활동에서 아이는 바라는 것이나 이야기의 끝을 이야기했어요.',
      scopeText: '이번 활동에서 확인된 표현이며, 전체 발달 수준을 평가한 결과가 아니에요.',
    ),
  ],
  unknownItems: [
    DiaryUnknownItemDto(
      code: 'SKIPPED_QUESTIONS',
      text: '아이가 넘긴 질문이 있어 그 부분은 이번에 확인하지 않았어요.',
    ),
    DiaryUnknownItemDto(
      code: 'REALITY_UNKNOWN',
      text: '실제로 있었던 일인지 상상한 이야기인지는 아이가 말하지 않았어요.',
    ),
    DiaryUnknownItemDto(
      code: 'TIME_UNKNOWN',
      text: '언제 있었던 일인지는 아이가 말하지 않았어요.',
    ),
  ],
  dataQuality: DiaryDataQualityDto(
    confirmedVoiceCount: 3,
    optionAnswerCount: 1,
    skippedCount: 1,
    evidenceCount: 6,
    visionSummaryAvailable: true,
  ),
);

final _screening = ScreeningSummaryDto(
  state: 'EXTERNAL_RESULT_AVAILABLE',
  message: '보호자가 직접 입력한 검사 기록이에요. 앱이 확인하거나 채점한 결과가 아니며, 그림일기 관찰과는 별개예요.',
  records: [
    ScreeningRecordDto(
      recordId: 1,
      instrumentId: 'K_DST',
      instrumentDisplayName: '한국 영유아 발달선별검사 K-DST',
      completedAt: DateTime(2026, 5, 20),
      sourceAuthorityName: '영유아건강검진',
      officialResultText: '심화평가권고',
      requiredDisclosure: '공식 발달선별 결과이며 진단은 아닙니다. 결과에 따라 정밀평가가 필요할 수 있습니다.',
      domainResults: const [
        ScreeningDomainResultDto(domainName: '언어', resultLabel: '심화평가권고'),
      ],
      followupMessage: '공식 선별 결과에 따라 소아청소년과 또는 발달 관련 전문가와 추가 평가를 상의해 보세요.',
      referralOptions: const ['소아청소년과', '발달클리닉'],
    ),
  ],
);
