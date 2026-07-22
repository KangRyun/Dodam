import 'dart:async';

import 'package:dodam/app/app.dart';
import 'package:dodam/app/router/app_routes.dart';
import 'package:dodam/features/child/data/dto/child_dtos.dart';
import 'package:dodam/features/child/domain/repositories/child_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Child 목록 Loading 상태를 표시한다', (tester) async {
    final completer = Completer<List<ChildSummaryDto>>();
    final repository = _FakeChildRepository(pending: completer);

    await tester.pumpWidget(DodamApp(childRepository: repository));

    expect(find.byKey(const ValueKey('child-list-loading')), findsOneWidget);
    completer.complete(const []);
    await tester.pumpAndSettle();
  });

  testWidgets('Child 목록 Error에서 Retry하면 다시 조회한다', (tester) async {
    final repository = _FakeChildRepository(error: StateError('network'));
    await tester.pumpWidget(DodamApp(childRepository: repository));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('child-list-error')), findsOneWidget);
    repository
      ..error = null
      ..children = _children;
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();

    expect(repository.getChildrenCalls, 2);
    expect(find.byKey(const ValueKey('child-list-success')), findsOneWidget);
  });

  testWidgets('Child 목록 Empty 상태를 표시한다', (tester) async {
    await tester.pumpWidget(
      DodamApp(childRepository: _FakeChildRepository(children: const [])),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('child-list-empty')), findsOneWidget);
  });

  testWidgets('Child 목록 Success와 실제 DTO 정보를 표시한다', (tester) async {
    await tester.pumpWidget(
      DodamApp(childRepository: _FakeChildRepository(children: _children)),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('child-list-success')), findsOneWidget);
    expect(find.text('도담이'), findsWidgets);
    expect(find.text('봄이'), findsOneWidget);
    expect(find.textContaining('활동 12회'), findsOneWidget);
  });

  testWidgets('선택된 childId를 유지해 해당 아동 모드로 진입한다', (tester) async {
    await tester.pumpWidget(
      DodamApp(childRepository: _FakeChildRepository(children: _children)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('child-7')));
    await tester.pump();
    await _tapAfterScroll(tester, const ValueKey('start-child-mode'));
    await tester.pumpAndSettle();

    expect(find.text('봄이, 오늘은 무엇을 그려 볼까?'), findsOneWidget);
    expect(find.byKey(const ValueKey('draw-action')), findsOneWidget);
  });

  testWidgets('선택된 아동의 그림 활동 시작 버튼은 Drawing placeholder로 연결된다', (tester) async {
    await tester.pumpWidget(
      DodamApp(childRepository: _FakeChildRepository(children: _children)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('child-3')));
    await tester.pump();
    await _tapAfterScroll(tester, const ValueKey('start-child-mode'));
    await tester.pumpAndSettle();

    await _tapAfterScroll(tester, const ValueKey('draw-action'));
    await tester.pumpAndSettle();

    expect(find.text('그림 활동'), findsWidgets);
  });

  testWidgets('아동 모드에는 보호자 전용 요약과 리포트 정보가 노출되지 않는다', (tester) async {
    await tester.pumpWidget(
      DodamApp(childRepository: _FakeChildRepository(children: _children)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('child-3')));
    await tester.pump();
    await _tapAfterScroll(tester, const ValueKey('start-child-mode'));
    await tester.pumpAndSettle();

    expect(find.text('월간 활동 요약'), findsNothing);
    expect(find.text('관찰 리포트'), findsNothing);
    expect(find.textContaining('위험'), findsNothing);
    expect(find.textContaining('분석 상세'), findsNothing);
  });

  testWidgets('childId가 없는 직접 아동 모드 접근은 보호한다', (tester) async {
    await tester.pumpWidget(
      DodamApp(
        childRepository: _FakeChildRepository(children: _children),
        initialRoute: AppRoutes.childModeHome('7'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('선택된 아동이 없어요'), findsOneWidget);
    expect(find.text('봄이, 오늘은 무엇을 그려 볼까?'), findsNothing);
  });
}

Future<void> _tapAfterScroll(WidgetTester tester, Key key) async {
  final target = find.byKey(key);
  await tester.ensureVisible(target);
  await tester.tap(target);
}

const _children = [
  ChildSummaryDto(
    childId: 3,
    nickname: '도담이',
    birthDate: '2019-03-14',
    age: 7,
    profileImageUrl: null,
    preferredCharacter: 'BEAR',
    questionDifficulty: 'PRESCHOOL',
    tutorialStatus: 'COMPLETED',
    relationshipType: 'MOTHER',
    recentActivity: ChildRecentActivityDto(
      lastActivityAt: '2026-07-20T08:15:00Z',
      totalActivityCount: 12,
    ),
  ),
  ChildSummaryDto(
    childId: 7,
    nickname: '봄이',
    birthDate: '2016-11-02',
    age: 9,
    profileImageUrl: null,
    preferredCharacter: 'RABBIT',
    questionDifficulty: 'ELEMENTARY',
    tutorialStatus: 'NOT_STARTED',
    relationshipType: 'MOTHER',
    recentActivity: ChildRecentActivityDto(
      lastActivityAt: null,
      totalActivityCount: 0,
    ),
  ),
];

final class _FakeChildRepository implements ChildRepository {
  _FakeChildRepository({this.children = const [], this.error, this.pending});

  List<ChildSummaryDto> children;
  Object? error;
  Completer<List<ChildSummaryDto>>? pending;
  int getChildrenCalls = 0;

  @override
  Future<List<ChildSummaryDto>> getChildren() async {
    getChildrenCalls += 1;
    if (pending case final pending?) return pending.future;
    if (error case final error?) throw error;
    return children;
  }

  @override
  Future<ChildDetailDto> createChild(CreateChildRequestDto request) =>
      throw UnimplementedError();
  @override
  Future<void> deleteChild(int childId, {bool cascade = true}) =>
      throw UnimplementedError();
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
