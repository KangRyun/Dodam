import 'dart:async';
import 'dart:typed_data';

import 'package:dodam/app/app.dart';
import 'package:dodam/app/router/app_routes.dart';
import 'package:dodam/core/network/network.dart';
import 'package:dodam/features/activity/data/dto/activity_dtos.dart';
import 'package:dodam/features/activity/domain/repositories/activity_repository.dart';
import 'package:dodam/features/conversation/conversation.dart';
import 'package:dodam/features/drawing/data/dto/drawing_dtos.dart';
import 'package:dodam/features/report/data/dto/report_dtos.dart';
import 'package:dodam/features/report/domain/repositories/report_repository.dart';
import 'package:dodam/features/report/domain/services/report_file_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Activity Detail의 실제 reportId로 진입하고 Back으로 복귀한다', (tester) async {
    final reportRepository = _ReportRepository(report: _report(reportId: 777));
    await tester.pumpWidget(
      DodamApp(
        activityRepository: const _ActivityRepository(),
        reportRepository: reportRepository,
        initialRoute: AppRoutes.activityDetail('120'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('activity-report-cta')),
    );
    await tester.tap(find.byKey(const ValueKey('activity-report-cta')));
    await tester.pumpAndSettle();

    expect(reportRepository.calls, [777]);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('우리 가족'), findsOneWidget);
  });

  testWidgets('완료 리포트의 계약 섹션을 실제 값으로 표시한다', (tester) async {
    final repository = _ReportRepository();
    await _openReport(tester, repository);

    expect(repository.calls, [501]);
    // drawingSession — 활동 이름·완료일은 '한눈에 보는 활동'에서 뺐다
    // (S15P11B209-996). 남는 건 활동 유형·활동 시간·입력 방식이다.
    expect(find.text('우리 가족'), findsNothing);
    expect(find.text('그림일기'), findsOneWidget);
    // 입력 방식은 서버 코드가 아니라 보호자가 읽을 수 있는 말로 낸다. PDF 와 같은 문구다.
    expect(find.text('앱에서 그리기'), findsOneWidget);
    expect(find.text('CANVAS'), findsNothing);
    expect(find.text('23분'), findsOneWidget);
    // childExpression
    expect(find.text('동생이랑 놀아서 좋았어요'), findsOneWidget);
    // 히어로 풀인용 + 섹션 = 2회(의도된 중복)
    expect(find.textContaining('우리 동생이야.'), findsNWidgets(2));
    expect(find.text('기쁨'), findsOneWidget);
    // activityFacts 블럭은 그림일기에서 빼고 HTP에만 남겼다(S15P11B209-996).
    expect(find.text('사람, 집'), findsNothing);
    expect(find.text('그린 시간'), findsNothing);
    expect(find.text('22분'), findsNothing);
    expect(find.text('4회'), findsNothing);
    // conversationSummary
    expect(find.text('편안하게 대화했어요.'), findsOneWidget);
    // guardianConversationGuide + limitations
    expect(find.text('어떤 부분이 좋아?'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('report-non-diagnostic-notice')),
      findsOneWidget,
    );
    // 한계 문장과 참고 자료는 표지 안내와 겹쳐 빼고, 서버의 비진단 안내만 남겼다
    // (S15P11B209-996).
    expect(find.textContaining('진단이 아닌 관찰 참고 자료'), findsNothing);
    expect(find.textContaining('나타난 특징을 정리한 자료예요'), findsOneWidget);
  });

  testWidgets('서버가 만든 리포트 PDF를 내려받아 저장한다', (tester) async {
    // 문서 정본은 서버다(ADR-0003). 앱은 화면을 떠서 굽지 않고 같은 파일을 받아
    //   저장·공유만 한다 — 앱과 웹이 다른 문서를 만들지 않게 하는 전제다.
    final repository = _ReportRepository();
    final fileActions = _ReportFileActions();
    await _openReport(tester, repository, fileActions: fileActions);

    await tester.ensureVisible(find.byKey(const ValueKey('report-save-pdf')));
    await tester.tap(find.byKey(const ValueKey('report-save-pdf')));
    await tester.pumpAndSettle();

    expect(repository.exportCalls, [501]);
    expect(repository.exportKeys, ['report-export-501']);
    expect(repository.downloadUrls, ['/api/v1/reports/501/exports/501/file']);
    expect(fileActions.savedFileNames, ['dodam-report-501.pdf']);
    expect(fileActions.savedBytes.single, _pdfBytes);
    expect(find.text('PDF를 저장했어요.'), findsOneWidget);
  });

  testWidgets('완료 리포트 PDF 파일을 시스템 공유 화면으로 전달한다', (tester) async {
    final fileActions = _ReportFileActions();
    await _openReport(tester, _ReportRepository(), fileActions: fileActions);

    await tester.ensureVisible(find.byKey(const ValueKey('report-share-pdf')));
    await tester.tap(find.byKey(const ValueKey('report-share-pdf')));
    await tester.pumpAndSettle();

    expect(fileActions.sharedFileNames, ['dodam-report-501.pdf']);
    expect(fileActions.sharedBytes.single, _pdfBytes);
  });

  testWidgets('PDF 처리 중에는 저장과 공유를 중복 실행하지 않는다', (tester) async {
    final pending = Completer<ReportExportDto>();
    final repository = _ReportRepository(exportPending: pending);
    final fileActions = _ReportFileActions();
    await _openReport(tester, repository, fileActions: fileActions);

    await tester.ensureVisible(find.byKey(const ValueKey('report-save-pdf')));
    await tester.tap(find.byKey(const ValueKey('report-save-pdf')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('report-share-pdf')));
    await tester.pump();

    expect(repository.exportCalls, [501]);
    pending.complete(_completedExport);
    await tester.pumpAndSettle();
    expect(fileActions.savedFileNames, ['dodam-report-501.pdf']);
    expect(fileActions.sharedFileNames, isEmpty);
  });

  testWidgets('PDF 저장 실패를 안내하고 같은 멱등성 키로 재시도한다', (tester) async {
    final repository = _ReportRepository(
      exportError: ApiTransportFailure(
        type: ApiTransportFailureType.connection,
      ),
    );
    final fileActions = _ReportFileActions();
    await _openReport(tester, repository, fileActions: fileActions);

    await tester.ensureVisible(find.byKey(const ValueKey('report-save-pdf')));
    await tester.tap(find.byKey(const ValueKey('report-save-pdf')));
    await tester.pumpAndSettle();
    expect(find.text('PDF를 저장하지 못했어요. 다시 시도해 주세요.'), findsOneWidget);

    repository.exportError = null;
    await tester.tap(find.byKey(const ValueKey('report-save-pdf')));
    await tester.pumpAndSettle();

    expect(repository.exportKeys, ['report-export-501', 'report-export-501']);
    expect(fileActions.savedFileNames, ['dodam-report-501.pdf']);
  });

  testWidgets('PDF가 아닌 응답은 저장하지 않고 오류를 안내한다', (tester) async {
    final repository = _ReportRepository(
      downloadBytes: Uint8List.fromList(const [0x7B, 0x7D]),
    );
    final fileActions = _ReportFileActions();
    await _openReport(tester, repository, fileActions: fileActions);

    await tester.ensureVisible(find.byKey(const ValueKey('report-save-pdf')));
    await tester.tap(find.byKey(const ValueKey('report-save-pdf')));
    await tester.pumpAndSettle();

    expect(fileActions.savedFileNames, isEmpty);
    expect(find.text('PDF를 저장하지 못했어요. 다시 시도해 주세요.'), findsOneWidget);
  });

  testWidgets('PDF prefix와 비슷하지만 dash가 없는 응답은 저장하지 않는다', (tester) async {
    final repository = _ReportRepository(
      downloadBytes: Uint8List.fromList(const [0x25, 0x50, 0x44, 0x46, 0x78]),
    );
    final fileActions = _ReportFileActions();
    await _openReport(tester, repository, fileActions: fileActions);

    await tester.ensureVisible(find.byKey(const ValueKey('report-save-pdf')));
    await tester.tap(find.byKey(const ValueKey('report-save-pdf')));
    await tester.pumpAndSettle();

    expect(fileActions.savedFileNames, isEmpty);
    expect(find.text('PDF를 저장하지 못했어요. 다시 시도해 주세요.'), findsOneWidget);
  });

  testWidgets('파일 저장 선택을 취소하면 성공이나 오류로 안내하지 않는다', (tester) async {
    final fileActions = _ReportFileActions(saveResult: false);
    await _openReport(tester, _ReportRepository(), fileActions: fileActions);

    await tester.ensureVisible(find.byKey(const ValueKey('report-save-pdf')));
    await tester.tap(find.byKey(const ValueKey('report-save-pdf')));
    await tester.pumpAndSettle();

    expect(find.text('PDF를 저장했어요.'), findsNothing);
    expect(find.textContaining('저장하지 못했어요'), findsNothing);
  });

  testWidgets('보호자 금지 정보와 구형 문구를 노출하지 않는다', (tester) async {
    await _openReport(tester, _ReportRepository());

    expect(find.textContaining('위험도'), findsNothing);
    expect(find.textContaining('진단명'), findsNothing);
    expect(find.text('음성으로 답했어요 · 재생 파일 미제공'), findsNothing);
  });

  testWidgets('representativeUtterances가 비면 아이 표현 섹션을 만들지 않는다', (tester) async {
    await _openReport(
      tester,
      _ReportRepository(report: _report(expression: _emptyExpression)),
    );

    expect(find.byKey(const ValueKey('report-child-expression')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('messageId가 null인 발화도 텍스트로 표시한다', (tester) async {
    await _openReport(
      tester,
      _ReportRepository(
        report: _report(
          expression: const ReportChildExpressionDto(
            selectedEmotions: [],
            expressedEmotionText: null,
            representativeUtterances: [
              ReportUtteranceDto(
                messageId: null,
                text: '원본 없는 음성 답변',
                source: 'STT',
                sttNeedsConfirmation: false,
              ),
            ],
          ),
        ),
      ),
    );

    // 히어로 풀인용 + 섹션 = 2회(의도된 중복)
    expect(find.textContaining('원본 없는 음성 답변'), findsNWidgets(2));
    expect(find.byKey(const ValueKey('voice-answer-play-804')), findsNothing);
  });

  testWidgets('STT 발화와 유효한 messageId에만 재생 UI를 표시한다', (tester) async {
    final playback = _VoicePlaybackRepository();
    final player = _VoicePlaybackPlayer();
    await _openReport(
      tester,
      _ReportRepository(
        report: _report(
          expression: _expression([
            _utterance(804, '재생 가능한 음성', 'STT'),
            _utterance(null, 'messageId 없음', 'STT'),
            _utterance(0, 'messageId 0', 'STT'),
            _utterance(-1, '음수 messageId', 'STT'),
            _utterance(805, '직접 입력', 'TEXT'),
            _utterance(806, '알 수 없는 출처', 'UNKNOWN'),
          ]),
        ),
      ),
      voicePlaybackRepository: playback,
      voicePlayer: player,
    );

    expect(find.byKey(const ValueKey('voice-answer-play-804')), findsOneWidget);
    for (final id in [0, -1, 805, 806]) {
      expect(find.byKey(ValueKey('voice-answer-play-$id')), findsNothing);
    }
    for (final text in [
      'messageId 없음',
      'messageId 0',
      '음수 messageId',
      '직접 입력',
      '알 수 없는 출처',
    ]) {
      expect(find.textContaining(text), findsOneWidget);
    }
    // '재생 가능한 음성'은 첫 clean 발화라 히어로로 승격된다 —
    // 히어로 풀인용 + 섹션 = 2회(의도된 중복).
    expect(find.textContaining('재생 가능한 음성'), findsNWidgets(2));
    expect(playback.messageIds, isEmpty);
  });

  testWidgets('재생·정지·완료 후 다시 재생 상태를 Report 안에서 구분한다', (tester) async {
    final playback = _VoicePlaybackRepository();
    final player = _VoicePlaybackPlayer(holdPlayback: true);
    await _openReport(
      tester,
      _ReportRepository(),
      voicePlaybackRepository: playback,
      voicePlayer: player,
    );

    final play = find.byKey(const ValueKey('voice-answer-play-804'));
    await tester.ensureVisible(play);
    await tester.tap(play);
    await tester.pump();
    await tester.pump();

    expect(playback.messageIds, [804]);
    expect(find.byKey(const ValueKey('voice-answer-stop-804')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('voice-answer-stop-804')));
    await tester.pumpAndSettle();
    // 리포트에서는 상태 문구를 화면에 남기지 않는다(S15P11B209-996).
    // 다시 재생 버튼과 낭독기용 안내만 남는다.
    expect(find.text('재생을 멈췄어요.'), findsNothing);
    expect(
      find.byKey(const ValueKey('voice-answer-status-804')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('voice-answer-replay-804')),
      findsOneWidget,
    );

    player.holdPlayback = false;
    await tester.tap(find.byKey(const ValueKey('voice-answer-replay-804')));
    await tester.pumpAndSettle();
    expect(playback.messageIds, [804, 804]);
    expect(find.text('재생이 끝났어요.'), findsNothing);
    expect(
      find.byKey(const ValueKey('voice-answer-replay-804')),
      findsOneWidget,
    );
  });

  testWidgets('다운로드 중에는 loading만 표시하고 화면 이탈 시 취소·dispose한다', (tester) async {
    final pending = Completer<VoiceAnswerAudio>();
    final playback = _VoicePlaybackRepository(pending: pending);
    final player = _VoicePlaybackPlayer();
    await _openReport(
      tester,
      _ReportRepository(),
      voicePlaybackRepository: playback,
      voicePlayer: player,
    );

    final play = find.byKey(const ValueKey('voice-answer-play-804'));
    await tester.ensureVisible(play);
    await tester.tap(play);
    await tester.pump();

    expect(
      find.byKey(const ValueKey('voice-answer-loading-804')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('voice-answer-stop-804')), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(playback.cancelledMessageIds, [804]);
    expect(player.disposeCount, 1);

    pending.complete(_voiceAudio());
    await tester.pump();
    expect(player.playCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('일시 오류만 재시도하고 Report 본문과 PDF 기능은 유지한다', (tester) async {
    final playback = _VoicePlaybackRepository(
      failure: const ApiResponseFailure(statusCode: 500, error: null),
    );
    final player = _VoicePlaybackPlayer();
    await _openReport(
      tester,
      _ReportRepository(),
      voicePlaybackRepository: playback,
      voicePlayer: player,
    );

    final play = find.byKey(const ValueKey('voice-answer-play-804'));
    await tester.ensureVisible(play);
    await tester.tap(play);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('voice-answer-failure-804')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('voice-answer-retry-804')),
      findsOneWidget,
    );
    expect(find.text('그림일기'), findsOneWidget);
    // 히어로 풀인용 + 섹션 = 2회(의도된 중복)
    expect(find.textContaining('우리 동생이야.'), findsNWidgets(2));
    expect(find.byKey(const ValueKey('report-save-pdf')), findsOneWidget);
    expect(find.byKey(const ValueKey('report-share-pdf')), findsOneWidget);

    playback.failure = null;
    await tester.tap(find.byKey(const ValueKey('voice-answer-retry-804')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('voice-answer-replay-804')),
      findsOneWidget,
    );
  });

  testWidgets('영구 음성 오류에는 재시도를 표시하지 않는다', (tester) async {
    final playback = _VoicePlaybackRepository(
      failure: const ApiResponseFailure(statusCode: 404, error: null),
    );
    await _openReport(
      tester,
      _ReportRepository(),
      voicePlaybackRepository: playback,
      voicePlayer: _VoicePlaybackPlayer(),
    );

    final play = find.byKey(const ValueKey('voice-answer-play-804'));
    await tester.ensureVisible(play);
    await tester.tap(play);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('voice-answer-failure-804')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('voice-answer-retry-804')), findsNothing);
    expect(find.text('녹음한 음성을 찾을 수 없어요.'), findsOneWidget);
  });

  testWidgets('다른 대표 음성을 재생하면 기존 재생을 멈추고 하나만 활성화한다', (tester) async {
    final playback = _VoicePlaybackRepository();
    final player = _VoicePlaybackPlayer(holdPlayback: true);
    await _openReport(
      tester,
      _ReportRepository(
        report: _report(
          expression: _expression([
            _utterance(804, '첫 번째 음성', 'STT'),
            _utterance(806, '두 번째 음성', 'STT'),
          ]),
        ),
      ),
      voicePlaybackRepository: playback,
      voicePlayer: player,
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey('voice-answer-play-804')),
    );
    await tester.tap(find.byKey(const ValueKey('voice-answer-play-804')));
    await tester.pump();
    await tester.pump();
    await tester.ensureVisible(
      find.byKey(const ValueKey('voice-answer-play-806')),
    );
    await tester.tap(find.byKey(const ValueKey('voice-answer-play-806')));
    await tester.pump();
    await tester.pump();

    expect(playback.messageIds, [804, 806]);
    expect(find.byKey(const ValueKey('voice-answer-stop-804')), findsNothing);
    expect(find.byKey(const ValueKey('voice-answer-stop-806')), findsOneWidget);
  });

  testWidgets('background 전환은 Report 음성 재생을 정지한다', (tester) async {
    final player = _VoicePlaybackPlayer(holdPlayback: true);
    await _openReport(
      tester,
      _ReportRepository(),
      voicePlaybackRepository: _VoicePlaybackRepository(),
      voicePlayer: player,
    );

    final play = find.byKey(const ValueKey('voice-answer-play-804'));
    await tester.ensureVisible(play);
    await tester.tap(play);
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('voice-answer-stop-804')), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('voice-answer-stop-804')), findsNothing);
    expect(
      find.byKey(const ValueKey('voice-answer-replay-804')),
      findsOneWidget,
    );
  });

  testWidgets('작은 화면과 textScale 2.0에서도 음성 버튼 접근성과 48dp를 지킨다', (tester) async {
    final semantics = tester.ensureSemantics();
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _openReport(
      tester,
      _ReportRepository(
        report: _report(
          expression: _expression([
            _utterance(
              804,
              '아주 긴 대표 발화 ${List.filled(30, '내용').join(' ')}',
              'STT',
            ),
          ]),
        ),
      ),
      voicePlaybackRepository: _VoicePlaybackRepository(),
      voicePlayer: _VoicePlaybackPlayer(),
      textScale: 2.0,
    );

    final play = find.byKey(const ValueKey('voice-answer-play-804'));
    await tester.ensureVisible(play);
    await tester.pump();

    expect(tester.getSize(play).height, greaterThanOrEqualTo(48));
    expect(find.bySemanticsLabel('아이 음성 답변 재생'), findsOneWidget);
    expect(find.byKey(const ValueKey('report-small-layout')), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('조회 중 Loading을 표시한다', (tester) async {
    final pending = Completer<ReportDetailDto>();
    final repository = _ReportRepository(pending: pending);
    await _openReport(tester, repository, settle: false);
    await tester.pump();
    expect(find.byKey(const ValueKey('report-loading')), findsOneWidget);
    pending.complete(_completed);
    await tester.pumpAndSettle();
  });

  testWidgets('GENERATING 상태는 polling 없이 준비 안내를 표시한다', (tester) async {
    await _openReport(
      tester,
      _ReportRepository(report: _report(status: 'GENERATING', sections: false)),
      settle: false,
    );
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('report-generating')), findsOneWidget);
    expect(find.text('관찰 리포트를 준비하고 있어요'), findsOneWidget);
  });

  testWidgets('FAILED_FINAL 상태도 실패로 보여 주고 실패 사유를 조회한다', (tester) async {
    // 회귀: 리포트 실패가 셋으로 갈라진 뒤에도 이 화면은 'FAILED' 하나만 알고 있었다.
    //   그래서 최종 실패로 끝난 리포트가 기본 분기로 빠져 영원히 "준비하고 있어요"로 남았다.
    final repository = _ReportRepository(
      report: _report(status: 'FAILED_FINAL', sections: false),
    );
    await _openReport(tester, repository);

    expect(find.byKey(const ValueKey('report-failed')), findsOneWidget);
    expect(find.byKey(const ValueKey('report-generating')), findsNothing);
    expect(repository.generationStatusCalls, [501]);
  });

  testWidgets('FAILED_RETRYABLE 상태는 아직 진행 중으로 보여 준다', (tester) async {
    // 재시도 작업이 집어 갈 수 있는 실패다. 보호자가 지금 할 일이 없는데 "다시 확인 필요"를
    //   붙이면 없는 문제를 만든다.
    final repository = _ReportRepository(
      report: _report(status: 'FAILED_RETRYABLE', sections: false),
    );
    // 준비 안내에는 계속 도는 애니메이션이 있어 settle 하면 끝나지 않는다.
    await _openReport(tester, repository, settle: false);
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('report-generating')), findsOneWidget);
    expect(find.byKey(const ValueKey('report-failed')), findsNothing);
    expect(repository.generationStatusCalls, isEmpty);
  });

  testWidgets('FAILED 상태에서 실패 사유를 조회하고 재생성을 접수한다', (tester) async {
    final repository = _ReportRepository(
      report: _report(status: 'FAILED', sections: false),
    );
    await _openReport(tester, repository);
    expect(find.byKey(const ValueKey('report-failed')), findsOneWidget);
    expect(repository.generationStatusCalls, [501]);
    expect(find.textContaining('분석이 잠시 지연됐어요'), findsOneWidget);

    await tester.tap(find.text('다시 준비하기'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(repository.regenerateCalls, [501]);
    expect(find.byKey(const ValueKey('report-generating')), findsOneWidget);
  });

  testWidgets('재시도할 수 없는 FAILED 상태에는 재생성 버튼을 표시하지 않는다', (tester) async {
    final repository =
        _ReportRepository(report: _report(status: 'FAILED', sections: false))
          ..generationStatus = ReportGenerationStatusDto.fromJson(const {
            'reportId': 501,
            'reportStatus': 'FAILED',
            'reportVersion': 1,
            'retryable': false,
            'failureReason': 'UNKNOWN_NEW_CODE',
          });

    await _openReport(tester, repository);

    expect(find.textContaining('리포트를 준비하는 중 문제가 생겼어요'), findsOneWidget);
    expect(find.text('다시 준비하기'), findsNothing);
  });

  testWidgets('네트워크 Error에서 Retry할 수 있다', (tester) async {
    final repository = _ReportRepository(
      error: const ApiTransportFailure(
        type: ApiTransportFailureType.connection,
      ),
    );
    await _openReport(tester, repository);
    expect(find.byKey(const ValueKey('report-error')), findsOneWidget);

    repository.error = null;
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(repository.calls, [501, 501]);
  });

  testWidgets('403 권한 오류는 재시도 없이 오류 상태를 보여준다', (tester) async {
    await _openReport(
      tester,
      _ReportRepository(
        error: const ApiResponseFailure(
          statusCode: 403,
          error: ApiError(
            code: 'REPORT_ACCESS_DENIED',
            message: '리포트에 접근할 권한이 없습니다.',
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('report-error')), findsOneWidget);
    expect(find.text('다시 시도'), findsNothing);
  });

  testWidgets('invalid reportId는 API를 호출하지 않는다', (tester) async {
    final repository = _ReportRepository();
    await _openReport(tester, repository, reportId: 'invalid');
    expect(repository.calls, isEmpty);
    expect(find.byKey(const ValueKey('report-invalid-id')), findsOneWidget);
  });

  testWidgets('404 REPORT_NOT_FOUND는 Empty로 처리한다', (tester) async {
    await _openReport(
      tester,
      _ReportRepository(
        error: const ApiResponseFailure(
          statusCode: 404,
          error: ApiError(code: 'REPORT_NOT_FOUND', message: '리포트를 찾을 수 없습니다.'),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('report-empty')), findsOneWidget);
  });

  testWidgets('응답 reportId가 요청과 다르면 Empty로 처리한다', (tester) async {
    await _openReport(
      tester,
      _ReportRepository(report: _report(reportId: 777)),
    );
    expect(find.byKey(const ValueKey('report-empty')), findsOneWidget);
  });

  testWidgets('관찰 섹션이 모두 비면 빈 데이터 안내를 아이콘과 함께 표시한다', (tester) async {
    await _openReport(
      tester,
      _ReportRepository(report: _report(sections: false)),
    );

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('report-no-observations')),
      findsOneWidget,
    );
    expect(find.text('아직 표시할 관찰 기록이 없어요.'), findsOneWidget);
    // 색상 외 신호: 전용 아이콘을 함께 쓴다.
    expect(find.byIcon(Icons.inbox_outlined), findsOneWidget);
  });

  testWidgets('이미지가 없으면 placeholder를 아이콘과 문구로 표시한다', (tester) async {
    // 활동 정보가 하나도 없으면 '한눈에 보는 활동' 블럭 자체가 숨으므로
    // (S15P11B209-996), 정보는 있고 그림 URL만 비어 있는 표본으로 확인한다.
    await _openReport(tester, _ReportRepository());

    expect(
      find.byKey(const ValueKey('report-image-placeholder')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.image_outlined), findsOneWidget);
    expect(find.text('그림을 불러오지 못했어요'), findsOneWidget);
  });

  testWidgets('Home CTA는 48dp 이상이며 Guardian Home으로 이동한다', (tester) async {
    await _openReport(tester, _ReportRepository());
    final cta = find.byKey(const ValueKey('report-home-cta'));
    await tester.ensureVisible(cta);

    expect(tester.getSize(cta).height, greaterThanOrEqualTo(48));

    await tester.tap(cta);
    await tester.pumpAndSettle();
    expect(find.text('보호자 홈'), findsWidgets);
  });

  testWidgets('loading 상태에 Semantics 라벨을 제공한다', (tester) async {
    final handle = tester.ensureSemantics();
    final pending = Completer<ReportDetailDto>();
    await _openReport(
      tester,
      _ReportRepository(pending: pending),
      settle: false,
    );
    await tester.pump();

    expect(find.bySemanticsLabel('관찰 리포트를 불러오고 있어요'), findsOneWidget);

    pending.complete(_completed);
    await tester.pumpAndSettle();
    handle.dispose();
  });

  testWidgets('empty 상태에 Semantics 라벨을 제공한다', (tester) async {
    final handle = tester.ensureSemantics();
    await _openReport(
      tester,
      _ReportRepository(
        error: const ApiResponseFailure(
          statusCode: 404,
          error: ApiError(code: 'REPORT_NOT_FOUND', message: '없음'),
        ),
      ),
    );

    expect(find.bySemanticsLabel(RegExp('관찰 리포트를 찾을 수 없어요')), findsOneWidget);
    handle.dispose();
  });

  testWidgets('error 상태에 Semantics 라벨을 제공한다', (tester) async {
    final handle = tester.ensureSemantics();
    await _openReport(
      tester,
      _ReportRepository(
        error: const ApiTransportFailure(
          type: ApiTransportFailureType.connection,
        ),
      ),
    );

    expect(find.bySemanticsLabel(RegExp('관찰 리포트를 불러오지 못했어요')), findsOneWidget);
    handle.dispose();
  });

  testWidgets('textScale 2.0에서도 overflow가 없다', (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _openReport(tester, _ReportRepository(), textScale: 2.0);

    expect(tester.takeException(), isNull);
    expect(find.text('그림일기'), findsOneWidget);
  });

  testWidgets('비진단 안내는 작은 화면과 큰 글자에서도 읽을 수 있다', (tester) async {
    final handle = tester.ensureSemantics();
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _openReport(tester, _ReportRepository(), textScale: 2.0);
    final notice = find.byKey(const ValueKey('report-non-diagnostic-notice'));
    await tester.ensureVisible(notice);
    await tester.pump();

    expect(notice, findsOneWidget);
    expect(find.textContaining('나타난 특징을 정리한 자료예요'), findsOneWidget);
    expect(tester.takeException(), isNull);
    handle.dispose();
  });

  testWidgets('작은 화면에서도 단일 스크롤로 overflow가 없다', (tester) async {
    tester.view.physicalSize = const Size(500, 560);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _openReport(tester, _ReportRepository());

    expect(find.byKey(const ValueKey('report-small-layout')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('넓은 화면에서는 2단 레이아웃으로 배치한다', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _openReport(tester, _ReportRepository());

    expect(find.byKey(const ValueKey('report-wide-layout')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _openReport(
  WidgetTester tester,
  ReportRepository repository, {
  ReportFileActions? fileActions,
  String reportId = '501',
  bool settle = true,
  double textScale = 1.0,
  VoiceAnswerPlaybackRepository? voicePlaybackRepository,
  VoiceAnswerAudioPlayer? voicePlayer,
}) async {
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: DodamApp(
        reportRepository: repository,
        reportFileActions: fileActions ?? _ReportFileActions(),
        voiceAnswerPlaybackRepository: voicePlaybackRepository,
        voiceAnswerAudioPlayerFactory: voicePlayer == null
            ? null
            : () => voicePlayer,
        initialRoute: AppRoutes.report(reportId),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

final class _ReportRepository implements ReportRepository {
  _ReportRepository({
    ReportDetailDto? report,
    this.pending,
    this.error,
    this.exportPending,
    this.exportError,
    Uint8List? downloadBytes,
  }) : report = report ?? _completed,
       downloadBytes = downloadBytes ?? _pdfBytes;

  ReportDetailDto report;
  final Completer<ReportDetailDto>? pending;
  final Completer<ReportExportDto>? exportPending;
  Object? error;
  Object? exportError;
  final Uint8List downloadBytes;
  final List<int> calls = [];
  final List<int> exportCalls = [];
  final List<String> exportKeys = [];
  final List<String> downloadUrls = [];
  ReportGenerationStatusDto generationStatus =
      ReportGenerationStatusDto.fromJson(const {
        'reportId': 501,
        'reportStatus': 'FAILED',
        'reportVersion': 1,
        'retryable': true,
        'failureReason': 'AI_TIMEOUT',
      });
  final List<int> generationStatusCalls = [];
  final List<int> regenerateCalls = [];

  @override
  Future<ReportGenerationStatusDto> getGenerationStatus(int reportId) async {
    generationStatusCalls.add(reportId);
    return generationStatus;
  }

  @override
  Future<ReportGenerationStatusDto> regenerateReport(
    int reportId, {
    required String idempotencyKey,
  }) async {
    regenerateCalls.add(reportId);
    return ReportGenerationStatusDto.fromJson({
      'reportId': reportId + 1,
      'reportStatus': 'GENERATING',
      'reportVersion': 2,
      'retryable': false,
    });
  }

  @override
  Future<Uint8List> downloadImage(String imageUrl) async => Uint8List(0);

  @override
  Future<ReportDetailDto> getReport(int reportId) async {
    calls.add(reportId);
    if (error case final error?) throw error;
    return pending?.future ?? report;
  }

  @override
  Future<ApiPage<ReportSummaryDto>> getReports(
    int childId, {
    ReportFilterDto filter = const ReportFilterDto(),
  }) => throw UnimplementedError();

  @override
  Future<AnalysisStatusDto> getAnalysisStatus(int analysisId) =>
      throw UnimplementedError();

  @override
  Future<AnalysisAcceptedDto> retryAnalysis(
    int analysisId, {
    required String idempotencyKey,
  }) => throw UnimplementedError();

  @override
  Future<ReportExportDto> requestExport(
    int reportId, {
    required String idempotencyKey,
  }) async {
    exportCalls.add(reportId);
    exportKeys.add(idempotencyKey);
    if (exportError case final error?) throw error;
    return exportPending?.future ?? _completedExport;
  }

  @override
  Future<Uint8List> downloadExport(String downloadUrl) async {
    downloadUrls.add(downloadUrl);
    return downloadBytes;
  }
}

final class _ReportFileActions implements ReportFileActions {
  _ReportFileActions({this.saveResult = true});

  final bool saveResult;
  final List<String> savedFileNames = [];
  final List<Uint8List> savedBytes = [];
  final List<String> sharedFileNames = [];
  final List<Uint8List> sharedBytes = [];

  @override
  Future<bool> save({
    required String fileName,
    required Uint8List bytes,
  }) async {
    savedFileNames.add(fileName);
    savedBytes.add(bytes);
    return saveResult;
  }

  @override
  Future<void> share({
    required String fileName,
    required Uint8List bytes,
    Rect? shareOrigin,
  }) async {
    sharedFileNames.add(fileName);
    sharedBytes.add(bytes);
  }
}

final class _VoicePlaybackRepository implements VoiceAnswerPlaybackRepository {
  _VoicePlaybackRepository({this.failure, this.pending});

  Object? failure;
  final Completer<VoiceAnswerAudio>? pending;
  final List<int> messageIds = [];
  final List<int> cancelledMessageIds = [];

  @override
  Future<VoiceAnswerAudio> loadVoiceAnswerAudio(
    int messageId, {
    VoiceAnswerPlaybackCancellation? cancellation,
  }) async {
    messageIds.add(messageId);
    if (cancellation != null) {
      unawaited(
        cancellation.whenCancelled.then((_) {
          cancelledMessageIds.add(messageId);
        }),
      );
    }
    if (failure case final caught?) throw caught;
    return pending?.future ?? _voiceAudio();
  }
}

VoiceAnswerAudio _voiceAudio() => VoiceAnswerAudio(
  bytes: Uint8List.fromList([1, 2, 3]),
  mimeType: 'audio/webm',
);

final class _VoicePlaybackPlayer implements VoiceAnswerAudioPlayer {
  _VoicePlaybackPlayer({this.holdPlayback = false});

  bool holdPlayback;
  Completer<void>? _activePlayback;
  int playCount = 0;
  int stopCount = 0;
  int disposeCount = 0;

  @override
  Future<void> play(Uint8List bytes, {required String mimeType}) async {
    playCount += 1;
    if (!holdPlayback) return;
    final playback = Completer<void>();
    _activePlayback = playback;
    await playback.future;
  }

  @override
  Future<void> stop() async {
    stopCount += 1;
    final active = _activePlayback;
    if (active != null && !active.isCompleted) active.complete();
    _activePlayback = null;
  }

  @override
  Future<void> dispose() async {
    disposeCount += 1;
    await stop();
  }
}

final class _ActivityRepository implements ActivityRepository {
  const _ActivityRepository();

  @override
  Future<ActivityDetailDto> getActivity(int activityId) async =>
      ActivityDetailDto(
        activityId: activityId,
        childId: 3,
        childNickname: '도담이',
        title: '우리 가족',
        drawingType: const ActivityDrawingTypeDto(
          code: 'ART_DIARY',
          name: '그림일기',
        ),
        inputMethod: 'CANVAS',
        sessionStatus: 'COMPLETED',
        currentStage: 'COMPLETED',
        selectedEmotions: const ['JOY'],
        startedAt: '2026-07-20T09:40:00Z',
        completedAt: '2026-07-20T10:03:00Z',
        latestAsset: null,
        latestAnalysis: null,
        conversationId: null,
        reportId: 777,
      );

  @override
  Future<ApiPage<ActivitySummaryDto>> getActivities(
    int childId, {
    ActivityFilterDto filter = const ActivityFilterDto(),
  }) => throw UnimplementedError();

  @override
  Future<void> deleteActivity(int activityId) => throw UnimplementedError();

  @override
  Future<List<ActivityConversationMessageDto>> getConversationMessages(
    int conversationId,
  ) => throw UnimplementedError();

  @override
  Future<Uint8List> downloadImage(String url) => throw UnimplementedError();
}

const _emptyExpression = ReportChildExpressionDto(
  selectedEmotions: [],
  expressedEmotionText: null,
  representativeUtterances: [],
);

ReportChildExpressionDto _expression(List<ReportUtteranceDto> utterances) =>
    ReportChildExpressionDto(
      selectedEmotions: const [],
      expressedEmotionText: null,
      representativeUtterances: utterances,
    );

ReportUtteranceDto _utterance(int? messageId, String? text, String source) =>
    ReportUtteranceDto(
      messageId: messageId,
      text: text,
      source: source,
      sttNeedsConfirmation: false,
    );

final _completed = _report();
final _pdfBytes = Uint8List.fromList(const [0x25, 0x50, 0x44, 0x46, 0x2D]);
const _completedExport = ReportExportDto(
  reportId: 501,
  exportId: 501,
  status: 'COMPLETED',
  downloadUrl: '/api/v1/reports/501/exports/501/file',
);

ReportDetailDto _report({
  int reportId = 501,
  String status = 'COMPLETED',
  bool sections = true,
  ReportChildExpressionDto? expression,
}) => ReportDetailDto(
  reportId: reportId,
  reportVersion: 1,
  reportStatus: status,
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
  childExpression:
      expression ??
      (sections
          ? const ReportChildExpressionDto(
              selectedEmotions: ['JOY'],
              expressedEmotionText: '동생이랑 놀아서 좋았어요',
              representativeUtterances: [
                ReportUtteranceDto(
                  messageId: 804,
                  text: '우리 동생이야.',
                  source: 'STT',
                  sttNeedsConfirmation: false,
                ),
              ],
            )
          : _emptyExpression),
  activityFacts: sections
      ? const ReportActivityFactsDto(
          detectedObjects: ['사람', '집'],
          drawingDurationMs: 1320000,
          pauseCount: 4,
          eraseCount: 2,
          pressureAvailable: false,
          notes: [],
        )
      : null,
  conversationSummary: sections
      ? const ReportConversationSummaryDto(
          questionCount: 5,
          answeredCount: 4,
          skippedCount: 1,
          summary: '편안하게 대화했어요.',
        )
      : null,
  guardianConversationGuide: sections ? const ['어떤 부분이 좋아?'] : const [],
  limitations: sections ? const ['이 리포트는 진단이 아닌 관찰 참고 자료입니다.'] : const [],
  nonDiagnosticNotice: '이 리포트는 아이가 그림을 그리고 대화한 과정에서 나타난 특징을 정리한 자료예요.',
  expertReview: const ReportExpertReviewDto(
    status: 'NOT_REQUESTED',
    available: false,
  ),
  createdAt: '2026-07-20T10:12:00',
);
