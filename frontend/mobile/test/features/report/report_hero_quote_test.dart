import 'dart:typed_data';

import 'package:dodam/app/app.dart';
import 'package:dodam/app/router/app_routes.dart';
import 'package:dodam/core/network/api_page.dart';
import 'package:dodam/features/drawing/data/dto/drawing_dtos.dart';
import 'package:dodam/features/report/data/dto/report_dtos.dart';
import 'package:dodam/features/report/domain/repositories/report_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 표지 히어로 인용(`report-hero-quote`)의 승격 규칙을 검증한다.
///
/// 승격 규칙(report_screen.dart `_heroQuoteText`): representativeUtterances
/// 중 text 가 비어있지 않고 sttNeedsConfirmation == false 인 **첫** 발화.
/// 히어로는 풀인용이라 아래 '아이의 표현' 섹션에도 같은 발화가 그대로
/// 남는다(의도된 중복) — 이 파일은 히어로 자체의 노출 여부·내용만 본다.
void main() {
  testWidgets('text 있고 sttNeedsConfirmation==false인 대표 발화가 있으면 히어로에 뜬다', (
    tester,
  ) async {
    await _openReport(
      tester,
      _ReportRepository(
        report: _report(
          expression: _expression([_utterance('오늘 놀이터에 갔어요', false)]),
        ),
      ),
    );

    final hero = find.byKey(const ValueKey('report-hero-quote'));
    expect(hero, findsOneWidget);
    expect(
      find.descendant(of: hero, matching: find.textContaining('오늘 놀이터에 갔어요')),
      findsOneWidget,
    );
  });

  testWidgets('대표 발화가 모두 sttNeedsConfirmation==true이면 히어로 인용이 없다', (
    tester,
  ) async {
    await _openReport(
      tester,
      _ReportRepository(
        report: _report(
          expression: _expression([
            _utterance('확인이 필요한 말 1', true),
            _utterance('확인이 필요한 말 2', true),
          ]),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('report-hero-quote')), findsNothing);
    // 확인이 필요한 발화는 아래 섹션에는 그대로 남아 있어야 한다(히어로만 막는다).
    expect(find.textContaining('확인이 필요한 말 1'), findsOneWidget);
    expect(find.textContaining('확인이 필요한 말 2'), findsOneWidget);
  });

  testWidgets('representativeUtterances가 비어 있으면 히어로 인용이 없다', (tester) async {
    await _openReport(
      tester,
      _ReportRepository(report: _report(expression: _expression(const []))),
    );

    expect(find.byKey(const ValueKey('report-hero-quote')), findsNothing);
  });

  testWidgets('childExpression이 없으면 히어로 인용이 없다', (tester) async {
    await _openReport(
      tester,
      _ReportRepository(report: _report(expression: null, sections: false)),
    );

    expect(find.byKey(const ValueKey('report-hero-quote')), findsNothing);
  });

  testWidgets('첫 발화가 확인 필요면 건너뛰고 그다음 clean 발화가 히어로에 뜬다', (tester) async {
    await _openReport(
      tester,
      _ReportRepository(
        report: _report(
          expression: _expression([
            _utterance('확인이 필요한 첫 발화', true),
            _utterance('그다음 확실한 발화', false),
          ]),
        ),
      ),
    );

    final hero = find.byKey(const ValueKey('report-hero-quote'));
    expect(hero, findsOneWidget);
    expect(
      find.descendant(
        of: hero,
        matching: find.textContaining('그다음 확실한 발화'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: hero,
        matching: find.textContaining('확인이 필요한 첫 발화'),
      ),
      findsNothing,
    );
    // 건너뛴 첫 발화도 아래 섹션에는 그대로 남는다.
    expect(find.textContaining('확인이 필요한 첫 발화'), findsOneWidget);
    // 승격된 발화는 히어로 풀인용 + 섹션 = 2회(의도된 중복).
    expect(find.textContaining('그다음 확실한 발화'), findsNWidgets(2));
  });
}

Future<void> _openReport(
  WidgetTester tester,
  ReportRepository repository, {
  String reportId = '501',
}) async {
  await tester.pumpWidget(
    DodamApp(
      reportRepository: repository,
      initialRoute: AppRoutes.report(reportId),
    ),
  );
  await tester.pumpAndSettle();
}

ReportUtteranceDto _utterance(String text, bool sttNeedsConfirmation) =>
    ReportUtteranceDto(
      messageId: null,
      text: text,
      source: 'STT',
      sttNeedsConfirmation: sttNeedsConfirmation,
    );

ReportChildExpressionDto _expression(List<ReportUtteranceDto> utterances) =>
    ReportChildExpressionDto(
      selectedEmotions: const [],
      expressedEmotionText: null,
      representativeUtterances: utterances,
    );

ReportDetailDto _report({
  ReportChildExpressionDto? expression,
  bool sections = true,
}) => ReportDetailDto(
  reportId: 501,
  reportVersion: 1,
  reportStatus: 'COMPLETED',
  drawingSession: sections
      ? const ReportDrawingSessionDto(
          drawingSessionId: 120,
          childId: 3,
          drawingTypeCode: 'ART_DIARY',
          drawingTypeName: '그림일기',
          title: '우리 가족',
          inputMethod: 'CANVAS',
          startedAt: '2026-07-20T09:40:00',
          completedAt: '2026-07-20T10:03:00',
          durationMs: 1380000,
        )
      : null,
  // 위젯 테스트에서 실제 네트워크 이미지를 받지 않도록 URL은 비운다.
  drawing: const ReportDrawingDto(finalImageUrl: null, thumbnailUrl: null),
  childExpression: expression,
  activityFacts: null,
  conversationSummary: null,
  guardianConversationGuide: const [],
  limitations: const ['이 리포트는 진단이 아닌 관찰 참고 자료입니다.'],
  nonDiagnosticNotice: '이 리포트는 아이가 그림을 그리고 대화한 과정에서 나타난 특징을 정리한 자료예요.',
  expertReview: const ReportExpertReviewDto(
    status: 'NOT_REQUESTED',
    available: false,
  ),
  createdAt: '2026-07-20T10:12:00',
);

final class _ReportRepository implements ReportRepository {
  _ReportRepository({required this.report});

  final ReportDetailDto report;

  @override
  Future<ReportDetailDto> getReport(int reportId) async => report;

  @override
  Future<ReportGenerationStatusDto> getGenerationStatus(int reportId) =>
      throw UnimplementedError();

  @override
  Future<ReportGenerationStatusDto> regenerateReport(
    int reportId, {
    required String idempotencyKey,
  }) => throw UnimplementedError();

  @override
  Future<Uint8List> downloadImage(String imageUrl) async => Uint8List(0);

  @override
  Future<ApiPage<ReportSummaryDto>> getReports(
    int childId, {
    ReportFilterDto filter = const ReportFilterDto(),
  }) => throw UnimplementedError();

  @override
  Future<ReportExportDto> requestExport(
    int reportId, {
    required String idempotencyKey,
  }) => throw UnimplementedError();

  @override
  Future<Uint8List> downloadExport(String downloadUrl) =>
      throw UnimplementedError();

  @override
  Future<AnalysisStatusDto> getAnalysisStatus(int analysisId) =>
      throw UnimplementedError();

  @override
  Future<AnalysisAcceptedDto> retryAnalysis(
    int analysisId, {
    required String idempotencyKey,
  }) => throw UnimplementedError();
}
