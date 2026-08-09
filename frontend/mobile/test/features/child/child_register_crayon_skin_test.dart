import 'package:dodam/app/state/guardian_child_controller.dart';
import 'package:dodam/features/child/data/dto/child_dtos.dart';
import 'package:dodam/features/child/domain/repositories/child_repository.dart';
import 'package:dodam/features/child/presentation/screens/child_registration_screen.dart';
import 'package:dodam/features/child/presentation/widgets/crayon_form_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 아이 등록/편집 크레용 스킨(S15P11B209-943).
///
/// 스킨만 바꾼 작업이라 여기서는 "보이는 것"과 "저장 값이 그대로인지"를 함께
/// 확인한다 — 미터 칸 수·색, 선택 시 `questionDifficulty` 코드, 헤더 아이콘 분기.
void main() {
  testWidgets('난이도 3항목이 1·2·3칸 미터로 뜨고 색이 단계별로 다르다', (tester) async {
    await _pumpScreen(tester);

    const expected = [
      ('PRESCHOOL', 1, CrayonPalette.easyFill, CrayonPalette.easyStrong),
      ('LOWER_ELEMENTARY', 2, CrayonPalette.midFill, CrayonPalette.midStrong),
      ('UPPER_ELEMENTARY', 3, CrayonPalette.hardFill, CrayonPalette.hardStrong),
    ];

    for (final (code, filled, fill, strong) in expected) {
      final meter = tester.widget<CrayonMeter>(
        find.descendant(
          of: find.byKey(ValueKey('difficulty-$code')),
          matching: find.byType(CrayonMeter),
        ),
      );
      expect(meter.filled, filled, reason: code);
      expect(meter.total, 3, reason: code);
      expect(meter.color, fill, reason: code);
      expect(meter.strongColor, strong, reason: code);
    }
  });

  testWidgets('이모지 접두사 없이 라벨과 설명만 보여준다', (tester) async {
    await _pumpScreen(tester);

    expect(find.text('유아형 (만 4–6세)'), findsOneWidget);
    expect(find.textContaining('🌱'), findsNothing);
    expect(find.textContaining('🌿'), findsNothing);
    expect(find.textContaining('☘️'), findsNothing);
  });

  testWidgets('난이도를 고르면 그 코드로 저장되고 선택 카드만 강조된다', (tester) async {
    final repository = _ChildRepository();
    await _pumpScreen(tester, repository: repository);

    // 기본값은 PRESCHOOL이라 첫 카드가 선택 상태다.
    expect(_isSelected(tester, 'PRESCHOOL'), isTrue);
    expect(_isSelected(tester, 'UPPER_ELEMENTARY'), isFalse);

    final target = find.byKey(const ValueKey('difficulty-UPPER_ELEMENTARY'));
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();

    expect(_isSelected(tester, 'UPPER_ELEMENTARY'), isTrue);
    expect(_isSelected(tester, 'PRESCHOOL'), isFalse);

    await _submitWithRequiredFields(tester);
    expect(
      repository.createRequests.single.questionDifficulty,
      'UPPER_ELEMENTARY',
    );
  });

  testWidgets('난이도 카드는 48dp 탭 영역과 선택 상태 semantics를 지킨다', (tester) async {
    await _pumpScreen(tester);

    final card = find.byKey(const ValueKey('difficulty-PRESCHOOL'));
    expect(tester.getSize(card).height, greaterThanOrEqualTo(48));
    // 색이 아니라 텍스트로도 단계를 알 수 있어야 한다.
    final semantics = tester.getSemantics(card);
    expect(semantics.label, contains('유아형'));
    expect(semantics.label, contains('짧고 쉬운 말로'));
  });

  testWidgets('등록 헤더는 도장, 편집 헤더는 렌치를 타이틀 앞에 둔다', (tester) async {
    await _pumpScreen(tester);
    expect(
      _headerAsset(tester),
      'assets/images/child_register/crayon_stamp.png',
    );

    await _pumpScreen(tester, child: _child());
    expect(
      _headerAsset(tester),
      'assets/images/child_register/crayon_wrench.png',
    );
  });

  testWidgets('크레용 스킨을 입혀도 이름·생년월일 입력이 그대로 동작한다', (tester) async {
    final repository = _ChildRepository();
    await _pumpScreen(tester, repository: repository);

    await _submitWithRequiredFields(tester, nickname: '새봄');

    expect(repository.createRequests.single.nickname, '새봄');
    expect(repository.createRequests.single.birthDate, isNotEmpty);
  });

  testWidgets('좁은 폭·글자 2배에서도 난이도 카드가 overflow하지 않는다', (tester) async {
    await _pumpScreen(tester, size: const Size(390, 844), textScale: 2);

    expect(tester.takeException(), isNull);
    for (final code in const [
      'PRESCHOOL',
      'LOWER_ELEMENTARY',
      'UPPER_ELEMENTARY',
    ]) {
      final card = find.byKey(ValueKey('difficulty-$code'));
      await tester.ensureVisible(card);
      expect(card, findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });
}

/// 선택 표시는 체크 배지로 드러난다. 카드 하나에만 붙어야 한다.
bool _isSelected(WidgetTester tester, String code) => find
    .descendant(
      of: find.byKey(ValueKey('difficulty-$code')),
      matching: find.byIcon(Icons.check_rounded),
    )
    .evaluate()
    .isNotEmpty;

String _headerAsset(WidgetTester tester) {
  final image = tester.widget<Image>(
    find.descendant(of: find.byType(AppBar), matching: find.byType(Image)),
  );
  return (image.image as AssetImage).assetName;
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  _ChildRepository? repository,
  ChildSummaryDto? child,
  Size size = const Size(1280, 900),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final controller = GuardianChildController(repository ?? _ChildRepository());
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, body) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: body!,
      ),
      home: ChildRegistrationScreen(controller: controller, child: child),
    ),
  );
  await tester.pumpAndSettle();
}

/// 필수 값을 채우고 제출한다. 크레용 카드로 감싼 뒤에도 입력 경로가 살아 있는지
/// 함께 확인하는 역할을 한다.
Future<void> _submitWithRequiredFields(
  WidgetTester tester, {
  String nickname = '민지',
}) async {
  final nicknameField = find.byKey(const ValueKey('child-nickname'));
  await tester.ensureVisible(nicknameField);
  await tester.enterText(nicknameField, nickname);
  final birthDate = find.byKey(const ValueKey('child-birth-date'));
  await tester.ensureVisible(birthDate);
  await tester.tap(birthDate);
  await tester.pumpAndSettle();
  await tester.tap(find.text('선택'));
  await tester.pumpAndSettle();
  final submit = find.byKey(const ValueKey('submit-child-registration'));
  await tester.ensureVisible(submit);
  await tester.tap(submit);
  await tester.pumpAndSettle();
}

ChildSummaryDto _child() => const ChildSummaryDto(
  childId: 3,
  nickname: '민지',
  birthDate: '2019-03-14',
  age: 7,
  profileImageUrl: null,
  preferredCharacter: 'BASE',
  questionDifficulty: 'PRESCHOOL',
  tutorialStatus: 'NOT_STARTED',
  relationshipType: 'MOTHER',
  recentActivity: ChildRecentActivityDto(
    lastActivityAt: null,
    totalActivityCount: 0,
  ),
);

final class _ChildRepository implements ChildRepository {
  final List<CreateChildRequestDto> createRequests = [];

  @override
  Future<ChildDetailDto> createChild(CreateChildRequestDto request) async {
    createRequests.add(request);
    return ChildDetailDto(
      childId: 1,
      nickname: request.nickname,
      birthDate: request.birthDate,
      age: 6,
      profileImageUrl: null,
      preferredCharacter: request.preferredCharacter,
      questionDifficulty: request.questionDifficulty,
      responseModes: const ['VOICE'],
      tutorialStatus: 'NOT_STARTED',
      profileStatus: 'ACTIVE',
      relationshipType: request.relationshipType,
      createdAt: '2026-08-05T00:00:00Z',
    );
  }

  @override
  Future<List<ChildSummaryDto>> getChildren() async => const [];

  @override
  Future<void> deleteChild(int childId) async {}

  @override
  Future<ChildDetailDto> getChild(int childId) => throw UnimplementedError();

  @override
  Future<TutorialProgressDto> getTutorialProgress(int childId) =>
      throw UnimplementedError();

  @override
  Future<ChildDetailDto> updateChild(
    int childId,
    UpdateChildRequestDto request,
  ) => throw UnimplementedError();

  @override
  Future<TutorialProgressDto> updateTutorialProgress(
    int childId,
    UpdateTutorialRequestDto request,
  ) => throw UnimplementedError();
}
