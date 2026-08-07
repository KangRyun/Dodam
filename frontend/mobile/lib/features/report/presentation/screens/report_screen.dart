import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../app/router/app_router.dart';
import '../../../../app/widgets/app_failure_view.dart';
import '../../../../core/network/network.dart';
import '../../../../design_system/design_system.dart';
import '../../../activity/domain/repositories/activity_repository.dart';
import '../../../conversation/conversation.dart';
import '../../data/dto/report_dtos.dart';
import '../../data/services/platform_report_file_actions.dart';
import '../../domain/repositories/report_repository.dart';
import '../../domain/services/report_file_actions.dart';
import '../format/activity_duration_format.dart';
import '../widgets/htp_report_gallery.dart';
import '../widgets/report_mascot.dart';

/// 블럭 사이 간격. 기존 [AppSpacing.lg](24)의 60%다(S15P11B209-996).
///
/// 블럭이 많아 한 화면에 두세 개밖에 안 들어오던 것을 좁혔다. 토큰 사이값
/// (sm 12 · md 16)이라 상수로 둔다 — 카드 **안쪽** 여백은 24 그대로다.
const double _sectionGap = 14;

/// 가로 화면에서 블럭 안을 두 단으로 가를 때 쓰는 콘텐츠 상한(S15P11B209-996).
///
/// 세로 한 단일 때는 [AppSizes.contentMaxWidth](720)로 글줄이 길어지지 않게
/// 묶지만, 블럭 안에서 다시 반으로 갈리므로 상한을 넓혀야 한 단이 좁아지지
/// 않는다.
const double _wideContentMaxWidth = 1120;

/// 블럭 안을 두 단으로 가르는 최소 폭. 이보다 좁으면 한 단으로 쌓는다.
const double _blockSplitWidth = 640;

/// 블럭 안 소제목(주요 심리 경향·보호자 가이드·대화 전문) 글자 모양.
const _groupTitleStyle = TextStyle(
  color: AppColors.ink,
  fontSize: 16,
  fontWeight: FontWeight.w800,
);

/// 블럭 안을 두 단으로 가른다. 좁으면 왼쪽 뒤에 오른쪽을 이어 한 단으로 쌓는다.
///
/// 가로 화면에서 블럭이 세로로만 길어지는 것을 막는다(S15P11B209-996). 블럭끼리
/// 나누면 한쪽만 길어져 아래가 비지만, 안에서 가르면 제목 아래 내용이 균형 있게
/// 퍼진다. 한 단일 때의 읽는 순서(왼쪽 먼저, 그다음 오른쪽)는 그대로 유지한다.
class _BlockColumns extends StatelessWidget {
  const _BlockColumns({required this.left, required this.right});

  final List<Widget> left;
  final List<Widget> right;

  @override
  Widget build(BuildContext context) {
    if (left.isEmpty || right.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [...left, ...right],
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < _blockSplitWidth) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ...left,
              const SizedBox(height: AppSpacing.md),
              ...right,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: left,
              ),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: right,
              ),
            ),
          ],
        );
      },
    );
  }
}

enum _ReportViewStatus {
  loading,
  completed,
  generating,
  failed,
  empty,
  error,
  invalidId,
}

enum _ReportPdfAction { save, share }

class ReportScreen extends StatefulWidget {
  const ReportScreen({
    required this.reportId,
    required this.repository,
    this.activityRepository,
    ReportFileActions? fileActions,
    this.voiceAnswerPlaybackRepository,
    this.voiceAnswerAudioPlayerFactory,
    super.key,
  }) : fileActions = fileActions ?? const PlatformReportFileActions();

  final String reportId;
  final ReportRepository repository;
  final ActivityRepository? activityRepository;
  final ReportFileActions fileActions;
  final VoiceAnswerPlaybackRepository? voiceAnswerPlaybackRepository;
  final VoiceAnswerAudioPlayerFactory? voiceAnswerAudioPlayerFactory;

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen>
    with WidgetsBindingObserver {
  _ReportViewStatus _status = _ReportViewStatus.loading;
  ReportDetailDto? _report;
  ReportGenerationStatusDto? _generationStatus;
  Object? _failure;
  _ReportPdfAction? _pdfAction;
  bool _isRegenerating = false;
  VoiceAnswerPlaybackController? _playbackController;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _createPlaybackController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didUpdateWidget(covariant ReportScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.voiceAnswerPlaybackRepository !=
            widget.voiceAnswerPlaybackRepository ||
        oldWidget.voiceAnswerAudioPlayerFactory !=
            widget.voiceAnswerAudioPlayerFactory) {
      _playbackController?.dispose();
      _createPlaybackController();
    }
    if (oldWidget.reportId != widget.reportId ||
        oldWidget.repository != widget.repository) {
      unawaited(_load());
    }
  }

  void _createPlaybackController() {
    final repository = widget.voiceAnswerPlaybackRepository;
    final playerFactory = widget.voiceAnswerAudioPlayerFactory;
    _playbackController = repository == null || playerFactory == null
        ? null
        : VoiceAnswerPlaybackController(repository, playerFactory());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      unawaited(_playbackController?.stop());
    }
  }

  @override
  void dispose() {
    _loadGeneration++;
    WidgetsBinding.instance.removeObserver(this);
    _playbackController?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    final repository = widget.repository;
    unawaited(_playbackController?.reset());
    final reportId = int.tryParse(widget.reportId);
    if (reportId == null || reportId <= 0) {
      setState(() => _status = _ReportViewStatus.invalidId);
      return;
    }
    setState(() {
      _status = _ReportViewStatus.loading;
      _failure = null;
      _generationStatus = null;
    });
    try {
      final report = await repository.getReport(reportId);
      if (!_isCurrentLoad(generation, reportId, repository)) return;
      ReportGenerationStatusDto? generationStatus;
      if (report.reportStatus == 'FAILED') {
        try {
          generationStatus = await repository.getGenerationStatus(reportId);
          if (!_isCurrentLoad(generation, reportId, repository)) return;
        } on Object {
          // 상태 조회 실패 시에도 리포트 실패 안내 자체는 유지한다.
        }
      }
      if (!_isCurrentLoad(generation, reportId, repository)) return;
      if (report.reportId != reportId) {
        setState(() {
          _report = null;
          _status = _ReportViewStatus.empty;
        });
        return;
      }
      setState(() {
        _report = report;
        _generationStatus = generationStatus;
        _status = switch (report.reportStatus) {
          'COMPLETED' => _ReportViewStatus.completed,
          'GENERATING' => _ReportViewStatus.generating,
          'FAILED' => _ReportViewStatus.failed,
          _ => _ReportViewStatus.generating,
        };
      });
    } on ApiResponseFailure catch (failure) {
      if (!_isCurrentLoad(generation, reportId, repository)) return;
      setState(() {
        _failure = failure;
        _status = failure.statusCode == 404
            ? _ReportViewStatus.empty
            : _ReportViewStatus.error;
      });
    } on Object catch (error) {
      if (_isCurrentLoad(generation, reportId, repository)) {
        setState(() {
          _failure = error;
          _status = _ReportViewStatus.error;
        });
      }
    }
  }

  bool _isCurrentLoad(
    int generation,
    int reportId,
    ReportRepository repository,
  ) =>
      mounted &&
      generation == _loadGeneration &&
      int.tryParse(widget.reportId) == reportId &&
      identical(widget.repository, repository);

  Future<void> _regenerate() async {
    final report = _report;
    if (report == null || _isRegenerating) return;
    setState(() => _isRegenerating = true);
    try {
      await widget.repository.regenerateReport(
        report.reportId,
        idempotencyKey:
            'report-regenerate-${report.reportId}-${DateTime.now().microsecondsSinceEpoch}',
      );
      if (!mounted) return;
      setState(() => _status = _ReportViewStatus.generating);
      showAppMessage(
        context,
        message: '관찰 리포트를 다시 준비하고 있어요.',
        type: AppMessageType.success,
      );
    } on Object {
      if (!mounted) return;
      showAppMessage(
        context,
        message: '다시 준비하지 못했어요. 잠시 후 다시 시도해 주세요.',
        type: AppMessageType.error,
      );
    } finally {
      if (mounted) setState(() => _isRegenerating = false);
    }
  }

  Future<void> _handlePdf(_ReportPdfAction action) async {
    final report = _report;
    if (report == null || _pdfAction != null) return;
    final shareOrigin = action == _ReportPdfAction.share
        ? _currentScreenRect()
        : null;

    setState(() => _pdfAction = action);
    try {
      final export = await widget.repository.requestExport(
        report.reportId,
        idempotencyKey: 'report-export-${report.reportId}',
      );
      if (!export.isReady ||
          export.reportId != report.reportId ||
          export.downloadUrl !=
              '/api/v1/reports/${report.reportId}/exports/${export.exportId}/file') {
        throw const _ReportExportNotReady();
      }
      final bytes = await widget.repository.downloadExport(export.downloadUrl!);
      if (!_isPdf(bytes)) {
        throw const _ReportExportNotReady();
      }

      final fileName = 'dodam-report-${report.reportId}.pdf';
      switch (action) {
        case _ReportPdfAction.save:
          final saved = await widget.fileActions.save(
            fileName: fileName,
            bytes: bytes,
          );
          if (!saved) return;
        case _ReportPdfAction.share:
          await widget.fileActions.share(
            fileName: fileName,
            bytes: bytes,
            shareOrigin: shareOrigin,
          );
      }
      if (!mounted) return;
      if (action == _ReportPdfAction.save) {
        showAppMessage(
          context,
          message: 'PDF를 저장했어요.',
          type: AppMessageType.success,
        );
      }
    } on Object {
      if (!mounted) return;
      showAppMessage(
        context,
        message: action == _ReportPdfAction.save
            ? 'PDF를 저장하지 못했어요. 다시 시도해 주세요.'
            : 'PDF를 공유하지 못했어요. 다시 시도해 주세요.',
        type: AppMessageType.error,
      );
    } finally {
      if (mounted) {
        setState(() => _pdfAction = null);
      }
    }
  }

  Rect? _currentScreenRect() {
    final renderBox = context.findRenderObject();
    return renderBox is RenderBox
        ? renderBox.localToGlobal(Offset.zero) & renderBox.size
        : null;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.canvas,
    appBar: AppTopBar(
      title: '관찰 리포트',
      onBack: () => Navigator.of(context).maybePop(),
    ),
    body: SafeArea(top: false, child: _body()),
  );

  Widget _body() => switch (_status) {
    _ReportViewStatus.loading => const AppLoadingView(
      key: ValueKey('report-loading'),
      message: '관찰 리포트를 불러오고 있어요',
    ),
    _ReportViewStatus.generating => _ReportStateWithHome(
      key: const ValueKey('report-generating'),
      child: const AppLoadingView(message: '관찰 리포트를 준비하고 있어요'),
    ),
    _ReportViewStatus.failed => _ReportStateWithHome(
      key: const ValueKey('report-failed'),
      child: AppErrorView(
        title: '관찰 리포트를 준비하지 못했어요',
        message: _reportFailureMessage(_generationStatus?.failureReason),
        retryLabel: _isRegenerating ? '다시 준비하는 중' : '다시 준비하기',
        onRetry: _generationStatus?.retryable == true && !_isRegenerating
            ? _regenerate
            : null,
      ),
    ),
    _ReportViewStatus.error => _ReportStateWithHome(
      key: const ValueKey('report-error'),
      child: AppFailureView(
        title: '관찰 리포트를 불러오지 못했어요',
        failure: _failure,
        onRetry: _load,
      ),
    ),
    _ReportViewStatus.empty => const _ReportStateWithHome(
      key: ValueKey('report-empty'),
      child: AppEmptyView(
        title: '관찰 리포트를 찾을 수 없어요',
        message: '활동 상세에서 리포트 상태를 다시 확인해 주세요.',
      ),
    ),
    _ReportViewStatus.invalidId => const _ReportStateWithHome(
      key: ValueKey('report-invalid-id'),
      child: AppErrorView(
        title: '리포트 정보가 올바르지 않아요',
        message: '활동 상세에서 관찰 리포트를 다시 선택해 주세요.',
      ),
    ),
    _ReportViewStatus.completed => _ReportContent(
      report: _report!,
      pdfAction: _pdfAction,
      onSavePdf: () => _handlePdf(_ReportPdfAction.save),
      onSharePdf: () => _handlePdf(_ReportPdfAction.share),
      playbackController: _playbackController,
      imageFetcher: widget.repository.downloadImage,
      activityRepository: widget.activityRepository,
    ),
  };
}

String _reportFailureMessage(String? reason) {
  final normalized = reason?.toUpperCase() ?? '';
  if (normalized.contains('TIMEOUT') ||
      normalized.contains('AI') ||
      normalized.contains('ANALYSIS')) {
    return '분석이 잠시 지연됐어요. 다시 준비할 수 있는지 확인해 주세요.';
  }
  if (normalized.contains('IMAGE') ||
      normalized.contains('ASSET') ||
      normalized.contains('STORAGE') ||
      normalized.contains('FILE')) {
    return '그림을 확인하는 중 문제가 생겼어요. 다시 준비할 수 있는지 확인해 주세요.';
  }
  return '리포트를 준비하는 중 문제가 생겼어요. 잠시 후 다시 확인해 주세요.';
}

class _ReportStateWithHome extends StatelessWidget {
  const _ReportStateWithHome({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Expanded(child: child),
      Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: AppButton(
          key: const ValueKey('report-home-cta'),
          label: '보호자 홈으로 돌아가기',
          variant: AppButtonVariant.secondary,
          onPressed: () => AppRouter.goGuardianHome(context),
        ),
      ),
    ],
  );
}

class _ReportContent extends StatelessWidget {
  const _ReportContent({
    required this.report,
    required this.pdfAction,
    required this.onSavePdf,
    required this.onSharePdf,
    required this.playbackController,
    required this.imageFetcher,
    required this.activityRepository,
  });
  final ReportDetailDto report;
  final _ReportPdfAction? pdfAction;
  final VoidCallback onSavePdf;
  final VoidCallback onSharePdf;
  final VoiceAnswerPlaybackController? playbackController;
  final ImageByteFetcher imageFetcher;
  final ActivityRepository? activityRepository;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final isWide = constraints.maxWidth >= 900;
      final pagePadding = constraints.maxWidth < 360
          ? AppSpacing.sm
          : AppSpacing.lg;
      // 데이터가 없는 섹션은 각 빌더가 null을 돌려주어 자연스럽게 빠진다(오류 아님).
      //
      // 활동에 따라 섹션 구성이 갈린다. 그림일기·자유 그림은 계약 §11의 확정
      // 순서를 그대로 쓰고, HTP는 아래 [_htpSections]의 전용 순서를 쓴다.
      final isHtp = report.isHtpActivity;
      final drawings = _ReportDrawings(
        report: report,
        imageFetcher: imageFetcher,
        activityRepository: activityRepository,
      );
      // HTP 리포트의 고유 가치는 "집·나무·사람 각각에서 무엇을 보았고 어떤
      // 이야기를 나눴는가"다. 계약은 그림(§11-4)과 주제별 관찰(§11-5)을 따로
      // 두지만, 그렇게 하면 세 그림이 갤러리로만 붙고 이야기는 멀리 떨어진다.
      // HTP에서만 주제 단위로 묶어 맨 앞에 세운다.
      final htpStory = isHtp
          ? _htpSubjectStorySection(report, imageFetcher)
          : null;
      // 가로 화면에서는 블럭을 나란히 세우는 대신 각 블럭 **안**을 두 단으로
      // 가른다(S15P11B209-996).
      final wideBlocks = isWide && !isHtp;
      // 그림일기는 리포트 전체가 한 장이다(S15P11B209-996). 섹션마다 카드를
      // 두르지 않고 제목만으로 내용을 나눈다 — 색은 배경이 아니라 제목이 나른다.
      // 비진단 안내와 활동 요약은 표지 안으로 들어간다.
      final onePage = !isHtp;
      final sections = <Widget>[
        _ReportHero(
          report: report,
          flat: onePage,
          activity: isHtp
              ? null
              : _activityOverviewContent(
                  report,
                  imageFetcher,
                  activityRepository,
                ),
        ),
        if (isHtp) ...[
          ?_overviewSection(report),
          // 계약 §5 주제별 그림이 아직 없는 응답에서는 기존 그림 섹션(활동기록
          // 갤러리 우회)을 그대로 남겨 세 그림을 잃지 않는다.
          if (htpStory == null || report.subjectDrawings.isEmpty) drawings,
          ?htpStory,
          ?_childExpressionSection(report, playbackController),
          ?_conversationSummarySection(report),
          ?_observedFeaturesSection(report),
          ?_interpretationsSection(report, isHtp: true),
          ?_activityFactsSection(report, isHtp: true),
          ..._parentGuideSections(report),
          ?_legacyGuideSection(report),
        ] else ...[
          // 활동 요약은 표지 안으로 들어갔다(S15P11B209-996).
          ?_observationsSection(report, flat: onePage),
          ?_drawingStorySection(report, playbackController, flat: onePage),
        ],
        if (report.hasNoObservations) _noObservationsCard,
        _ReportActionSection(
          pdfAction: pdfAction,
          onSavePdf: onSavePdf,
          onSharePdf: onSharePdf,
          flat: onePage,
        ),
      ];
      return SingleChildScrollView(
        key: ValueKey(isWide ? 'report-wide-layout' : 'report-small-layout'),
        padding: EdgeInsets.all(pagePadding),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: wideBlocks
                  ? _wideContentMaxWidth
                  : AppSizes.contentMaxWidth,
            ),
            child: onePage
                // 한 장짜리 — 섹션 사이는 구분선과 여백으로만 나눈다.
                ? _ReportCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final (index, section) in sections.indexed) ...[
                          if (index > 0) ...[
                            const SizedBox(height: AppSpacing.lg),
                            const Divider(
                              height: 1,
                              color: AppColors.outline,
                            ),
                            const SizedBox(height: AppSpacing.lg),
                          ],
                          section,
                        ],
                      ],
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final (index, section) in sections.indexed) ...[
                        if (index > 0) const SizedBox(height: _sectionGap),
                        section,
                      ],
                    ],
                  ),
          ),
        ),
      );
    },
  );
}

const Widget _noObservationsCard = _ReportCard(
  key: ValueKey('report-no-observations'),
  backgroundColor: AppColors.surfaceSoft,
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(Icons.inbox_outlined, color: AppColors.inkMuted),
      SizedBox(width: AppSpacing.sm),
      Expanded(
        child: Text(
          '아직 표시할 관찰 기록이 없어요.',
          style: TextStyle(color: AppColors.inkMuted),
        ),
      ),
    ],
  ),
);

final class _ReportExportNotReady implements Exception {
  const _ReportExportNotReady();
}

bool _isPdf(List<int> bytes) =>
    bytes.length >= 5 &&
    bytes[0] == 0x25 &&
    bytes[1] == 0x50 &&
    bytes[2] == 0x44 &&
    bytes[3] == 0x46 &&
    bytes[4] == 0x2D;

class _ReportHero extends StatelessWidget {
  const _ReportHero({required this.report, this.activity, this.flat = false});

  final ReportDetailDto report;

  /// 카드 없이 내용만 돌려줄지 여부(S15P11B209-996).
  final bool flat;

  /// 표지 아래에 이어 붙일 활동 요약(그림 + 활동 정보).
  ///
  /// 그림일기·자유 그림은 표지와 활동 요약을 한 장으로 합친다
  /// (S15P11B209-996). HTP는 활동 정보를 별도 블럭으로 두어 null이다.
  final Widget? activity;

  Widget _intro(BuildContext context) => LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 520;
        // 표지 마스코트는 예전 크기의 70%다(S15P11B209-996). 표지가 첫 화면을
        // 거의 다 먹던 것을 줄인다 — 장식이지 본문이 아니다.
        final mascot = const ReportMascotImage(
          assetPath: ReportMascotAssets.intro,
          maxWidth: 132,
          mascotKey: ValueKey('report-mascot-intro'),
        );
        final copy = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: compact
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(
                // HTP는 세 그림을 함께 본다는 것을 표지에서부터 알린다. 검사
                // 이름·결과 표현은 쓰지 않는다(CLAUDE.md 5절).
                report.isHtpActivity
                    ? '집·나무·사람, 세 그림 이야기'
                    : '그림 속 이야기를 함께 돌아볼까요?',
                textAlign: TextAlign.start,
                style: const TextStyle(
                  color: AppColors.ink,
                  fontSize: 27,
                  height: 1.25,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            // 표지 글 사이 여백은 기존의 절반이다(12→6, 16→8).
            const SizedBox(height: 6),
            Text(
              report.isHtpActivity
                  ? '집과 나무와 사람을 그리면서 아이가 들려준 이야기를 모았어요.'
                  : '돌아보기 친구가 아이의 그림과 이야기를 차근차근 정리했어요.',
              style: const TextStyle(color: AppColors.inkMuted, height: 1.5),
            ),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                // 계약 §2 childDisplayName — 표지용. 없으면 pill 자체가 빠진다.
                if (report.childDisplayName case final name?)
                  _MetadataPill(label: name),
                if (report.createdAt case final createdAt?)
                  _MetadataPill(label: _date(createdAt)),
              ],
            ),
          ],
        );
        if (compact) {
          return Column(
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 92),
                child: mascot,
              ),
              const SizedBox(height: AppSpacing.xs),
              copy,
            ],
          );
        }
        return Row(
          children: [
            SizedBox(width: 120, child: mascot),
            const SizedBox(width: AppSpacing.lg),
            Expanded(child: copy),
          ],
        );
      },
  );

  @override
  Widget build(BuildContext context) {
    final notice = _heroNotice(report);
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _intro(context),
        ?notice,
        if (activity case final activity?) ...[
          const SizedBox(height: AppSpacing.md),
          activity,
        ],
      ],
    );
    if (flat) return body;
    return _ReportCard(
      backgroundColor: AppColors.brandYellowSoft,
      borderColor: AppColors.sunshine,
      // 표지만 위아래 여백을 절반으로 줄인다(24→12). 좌우는 다른 블럭과 맞춘다.
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: body,
    );
  }
}

/// 표지 아래에 붙는 비진단 안내(S15P11B209-996).
///
/// 예전에는 안내가 별도 보라 카드로 떨어져 있었다. "이 리포트를 어떻게 읽어야
/// 하는가"를 말하므로 읽기 시작하는 자리인 표지에 둔다. 경고가 아니라 안내라
/// 색을 쓰지 않고 구분선과 낮은 대비의 작은 글씨로만 구분한다.
///
/// 계약 §11의 `limitations`·`references`는 여기 싣지 않는다. 서버가 주는
/// 한계 문장이 이 안내와 거의 같은 말이라 두 번 읽히기 때문이다.
Widget? _heroNotice(ReportDetailDto report) {
  final notice = report.nonDiagnosticNotice?.trim();
  if (notice == null || notice.isEmpty) return null;
  return Padding(
    key: const ValueKey('report-non-diagnostic-notice'),
    padding: const EdgeInsets.only(top: AppSpacing.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 1, color: AppColors.sunshine),
        const SizedBox(height: AppSpacing.sm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 1),
              child: Icon(
                Icons.info_outline_rounded,
                size: 16,
                color: AppColors.inkMuted,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                notice,
                style: const TextStyle(
                  color: AppColors.inkMuted,
                  height: 1.45,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _MetadataPill extends StatelessWidget {
  const _MetadataPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppColors.surface.withValues(alpha: 0.78),
      borderRadius: BorderRadius.circular(AppRadius.pill),
      border: Border.all(color: AppColors.sunshine),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.ink,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}

/// 계약 §11-4: 집·나무·사람 완성 그림.
///
/// 그림의 정본은 계약 §5 `subjectReports[].imageUrl`이다. 이전에는 상세 응답의
/// `drawing`이 단수라 HTP인데도 한 장만 보였고, 그 공백을 활동기록 조회
/// ([HtpReportGallery])로 메워 왔다. 이제 계약 데이터가 있으면 그것을 쓰고,
/// 아직 주지 않는 구형 응답에서만 기존 우회 경로로 물러난다.
class _ReportDrawings extends StatelessWidget {
  const _ReportDrawings({
    required this.report,
    required this.imageFetcher,
    required this.activityRepository,
  });
  final ReportDetailDto report;
  final ImageByteFetcher imageFetcher;
  final ActivityRepository? activityRepository;

  @override
  Widget build(BuildContext context) {
    final session = report.drawingSession;
    final isHtp = report.isHtpActivity;
    // 서버는 완성본이 없으면 finalImageUrl을 비우므로 썸네일로 물러난다.
    final imageUrl =
        report.drawing?.finalImageUrl ?? report.drawing?.thumbnailUrl;
    final singleImagePreview = _ReportSingleImagePreview(
      imageUrl: imageUrl,
      imageFetcher: imageFetcher,
    );
    final subjectDrawings = report.subjectDrawings;
    final Widget preview;
    if (subjectDrawings.isNotEmpty) {
      preview = _SubjectDrawingGallery(
        subjects: subjectDrawings,
        imageFetcher: imageFetcher,
      );
    } else if (isHtp) {
      preview = HtpReportGallery(
        childId: session?.childId ?? -1,
        reportDrawingSessionId: session?.drawingSessionId ?? -1,
        repository: activityRepository,
        fallback: singleImagePreview,
      );
    } else {
      preview = singleImagePreview;
    }

    return _ReportSection(
      key: const ValueKey('report-drawings-section'),
      title: isHtp ? '집·나무·사람 그림' : '완성한 그림',
      backgroundColor: const Color(0xFFEAF6FA),
      accentColor: const Color(0xFF8CC6D8),
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 720) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      width: 92,
                      child: ReportMascotImage(
                        assetPath: ReportMascotAssets.observe,
                        maxWidth: 92,
                        mascotKey: ValueKey('report-mascot-observe'),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  preview,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(
                  width: 132,
                  child: ReportMascotImage(
                    assetPath: ReportMascotAssets.observe,
                    maxWidth: 132,
                    mascotKey: ValueKey('report-mascot-observe'),
                  ),
                ),
                const SizedBox(width: AppSpacing.lg),
                Expanded(child: preview),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// 계약 §5의 주제별 완성 그림을 HOUSE→TREE→PERSON 순서로 나란히 보여준다.
/// 주제 수를 가정하지 않으므로 HTP가 아닌 1장짜리 응답도 그대로 처리된다.
class _SubjectDrawingGallery extends StatelessWidget {
  const _SubjectDrawingGallery({
    required this.subjects,
    required this.imageFetcher,
  });

  final List<ReportSubjectReportDto> subjects;
  final ImageByteFetcher imageFetcher;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    key: const ValueKey('report-subject-gallery'),
    builder: (context, constraints) {
      final maxColumns = switch (constraints.maxWidth) {
        >= 720 => 3,
        >= 440 => 2,
        _ => 1,
      };
      final columns = maxColumns < subjects.length
          ? maxColumns
          : subjects.length;
      const gap = AppSpacing.md;
      final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final subject in subjects)
            SizedBox(
              width: width,
              child: _SubjectDrawingCard(
                subject: subject,
                imageFetcher: imageFetcher,
              ),
            ),
        ],
      );
    },
  );
}

class _SubjectDrawingCard extends StatelessWidget {
  const _SubjectDrawingCard({
    required this.subject,
    required this.imageFetcher,
  });

  final ReportSubjectReportDto subject;
  final ImageByteFetcher imageFetcher;

  @override
  Widget build(BuildContext context) {
    final label = _subjectLabel(subject.subjectType);
    return Container(
      key: ValueKey('report-subject-image-${subject.subjectType ?? 'UNKNOWN'}'),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            label: '$label 그림',
            child: ExcludeSemantics(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: AppTypography.label,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          AspectRatio(
            aspectRatio: 4 / 3,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: AuthenticatedImage(
                url: subject.imageUrl,
                fetcher: imageFetcher,
                fit: BoxFit.contain,
                semanticLabel: '$label 완성 그림',
                placeholderBuilder: (_) => const _ImagePlaceholder(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportSingleImagePreview extends StatelessWidget {
  const _ReportSingleImagePreview({
    required this.imageUrl,
    required this.imageFetcher,
  });

  final String? imageUrl;
  final ImageByteFetcher imageFetcher;

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 4 / 3,
    child: Container(
      key: const ValueKey('report-image'),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: imageUrl == null
          ? const _ImagePlaceholder()
          : AuthenticatedImage(
              url: imageUrl,
              fetcher: imageFetcher,
              fit: BoxFit.contain,
              semanticLabel: '아동이 완성한 그림',
              placeholderBuilder: (_) => const _ImagePlaceholder(),
            ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────
// 계약 §11 섹션 빌더. 각 함수는 데이터가 없으면 null(또는 빈 목록)을 돌려주어
// 해당 섹션을 숨긴다. 비진단 원칙에 따라 색상은 라벤더·블루·그린 계열 중립만
// 쓰고, 경고/위험 아이콘·문구는 쓰지 않는다.
// ─────────────────────────────────────────────────────────────────────────

/// §2 한눈에 보는 이번 활동 — 활동 정보와 아이가 고른 감정. HTP 전용이다.
/// 그림일기·자유 그림은 그림까지 묶은 [_activityOverviewSection]을 쓴다.
Widget? _overviewSection(ReportDetailDto report) {
  final session = report.drawingSession;
  final emotions = report.childExpression?.selectedEmotions ?? const [];
  final lines = <Widget>[
    if (session?.title case final title?)
      _InfoLine(label: '활동 이름', value: title),
    // 세션의 표시 이름이 없으면 계약 §2 최상위 activityType을 한국어 라벨로
    // 바꿔 쓴다. 둘 다 없으면 줄 자체가 빠진다.
    if ((session?.drawingTypeName ??
            session?.drawingTypeCode ??
            _activityTypeLabel(report.activityType))
        case final type?)
      _InfoLine(label: '활동 유형', value: type),
    if (session?.inputMethod case final inputMethod?)
      _InfoLine(label: '입력 방식', value: _inputMethodLabel(inputMethod)),
    if (formatActivityDuration(session?.durationMs) case final duration?)
      _InfoLine(label: '활동 시간', value: duration),
    if (session?.completedAt case final completedAt?)
      _InfoLine(label: '완료일', value: _date(completedAt)),
  ];
  if (lines.isEmpty && emotions.isEmpty) return null;
  return _ReportSection(
    key: const ValueKey('report-activity-info'),
    title: '한눈에 보는 이번 활동',
    backgroundColor: const Color(0xFFFFF7DA),
    accentColor: AppColors.warning,
    children: [
      ...lines,
      if (emotions.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.xs),
        const Text('아이가 선택한 감정', style: TextStyle(color: AppColors.inkMuted)),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (final emotion in emotions)
              Chip(label: Text(_emotionLabel(emotion))),
          ],
        ),
      ],
    ],
  );
}

/// 그림일기·자유 그림의 활동 요약 — 표지 안에 들어갈 내용만 돌려준다.
///
/// 활동 정보(§2)와 완성 그림(§11-4)이 따로 놓여 있으면 보호자가 "무엇을
/// 그렸나"와 "어떤 활동이었나"를 두 블럭에서 나눠 읽어야 했다. 그림을 왼쪽에
/// 두고 오른쪽에 활동 정보를 세워 한 눈에 묶고, 다시 표지와 한 장으로 합쳤다
/// (S15P11B209-996) — 리포트를 펼치면 누구의 어떤 활동인지가 먼저 온다.
///
/// 대화 요약 한 줄은 그림이 무엇인지 설명하는 문장이라 그림 바로 아래에 붙인다
/// — 예전 '대화 요약' 블럭은 이 한 줄만 남기고 없앴다.
Widget? _activityOverviewContent(
  ReportDetailDto report,
  ImageByteFetcher imageFetcher,
  ActivityRepository? activityRepository,
) {
  final session = report.drawingSession;
  final emotions = report.childExpression?.selectedEmotions ?? const [];
  final lines = <Widget>[
    // 세션의 표시 이름이 없으면 계약 §2 최상위 activityType을 한국어 라벨로
    // 바꿔 쓴다. 둘 다 없으면 줄 자체가 빠진다.
    if ((session?.drawingTypeName ??
            session?.drawingTypeCode ??
            _activityTypeLabel(report.activityType))
        case final type?)
      _InfoLine(label: '활동 유형', value: type),
    if (formatActivityDuration(session?.durationMs) case final duration?)
      _InfoLine(label: '활동 시간', value: duration),
    if (session?.inputMethod case final inputMethod?)
      _InfoLine(label: '입력 방식', value: _inputMethodLabel(inputMethod)),
  ];
  final imageUrl =
      report.drawing?.finalImageUrl ?? report.drawing?.thumbnailUrl;
  final hasImage = imageUrl != null || report.subjectDrawings.isNotEmpty;
  if (lines.isEmpty && emotions.isEmpty && !hasImage) return null;

  final caption = report.conversationSummary?.summary?.trim();
  final drawing = Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _ReportSingleImagePreview(
        imageUrl: report.subjectDrawings.isNotEmpty
            ? report.subjectDrawings.first.imageUrl
            : imageUrl,
        imageFetcher: imageFetcher,
      ),
      if (caption != null && caption.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.xs),
        Text(
          caption,
          key: const ValueKey('report-drawing-caption'),
          style: const TextStyle(
            color: AppColors.inkMuted,
            height: 1.45,
            fontSize: 13,
          ),
        ),
      ],
    ],
  );
  final facts = Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      ...lines,
      if (emotions.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.xxs),
        const Text('아이가 선택한 감정', style: TextStyle(color: AppColors.inkMuted)),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (final emotion in emotions)
              Chip(label: Text(_emotionLabel(emotion))),
          ],
        ),
      ],
    ],
  );

  return KeyedSubtree(
    key: const ValueKey('report-activity-info'),
    child: LayoutBuilder(
        builder: (context, constraints) {
          // 좁으면 나란히 두지 못한다. 그림을 위로 올리고 정보를 아래에 쌓는다.
          if (constraints.maxWidth < 460) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                drawing,
                const SizedBox(height: AppSpacing.md),
                facts,
              ],
            );
          }
          // 예전 그림 블럭에서 마스코트 옆에 놓이던 폭의 약 75%다. 그림이 여전히
          // 주인공으로 보이면서, 오른쪽에 [_InfoLine]이 라벨·값을 한 줄로 놓는 데
          // 필요한 280px이 남는 지점 — 더 키우면 활동 정보가 두 줄로 쪼개진다.
          final imageWidth = (constraints.maxWidth * 0.55).clamp(240.0, 392.0);
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: imageWidth, child: drawing),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: facts),
            ],
          );
        },
    ),
  );
}

const _interpretationOrder = <String>[
  'RELATIONSHIP',
  'EMOTION',
  'SELF_EXPRESSION',
  'ACTIVITY_STYLE',
  'ADAPTATION',
];

/// §3 publicInterpretations 카드. 배열이 비면 숨긴다.
///
/// [isHtp]이면 제목을 검사 판정 어휘("주요 심리 경향")에서 대화 소재 표현으로
/// 바꾼다. HTP를 검사로 표현·해석하지 않는다는 원칙(CLAUDE.md 5절) 때문이다.
/// 계약 §3 카드를 화면 순서(관계→감정→자기표현→활동 방식→적응)로 정렬한다.
/// 모르는 카테고리는 뒤로 민다.
List<ReportInterpretationDto> _orderedInterpretations(ReportDetailDto report) {
  int rank(ReportInterpretationDto item) {
    final index = _interpretationOrder.indexOf(item.category ?? '');
    return index < 0 ? _interpretationOrder.length : index;
  }

  return [...report.publicInterpretations]
    ..sort((a, b) => rank(a).compareTo(rank(b)));
}

Widget? _interpretationsSection(ReportDetailDto report, {bool isHtp = false}) {
  if (report.publicInterpretations.isEmpty) return null;
  final interpretations = _orderedInterpretations(report);
  final evidenceById = <int, ReportEvidenceItemDto>{
    for (final item in report.evidenceItems) ?item.evidenceId: item,
  };
  return _ReportSection(
    key: const ValueKey('report-interpretations'),
    title: isHtp ? '함께 살펴보면 좋을 이야기' : '주요 심리 경향',
    backgroundColor: AppColors.lavenderSoft,
    accentColor: AppColors.lavender,
    children: [
      for (final (index, interpretation) in interpretations.indexed) ...[
        if (index > 0) const SizedBox(height: AppSpacing.md),
        _InterpretationCard(
          index: index,
          interpretation: interpretation,
          evidenceById: evidenceById,
        ),
      ],
    ],
  );
}

/// 그림일기·자유 그림의 "그림과 나눈 이야기"(S15P11B209-996).
///
/// 예전에는 '주제별 관찰과 문답'과 '아이의 표현과 대화 요약'이 따로 있어서,
/// 같은 대화를 놓고 관찰·요약·문답이 세 군데로 흩어졌다. 하나로 묶어 읽는
/// 순서를 정한다: 그림에서 보인 것 → 아이가 한 말(들어볼 수 있음) → 대화 전문.
///
/// 가로 화면에서는 왼쪽에 관찰·발화를, 오른쪽에 대화 전문을 나란히 편다.
/// 세로 화면에서는 같은 순서로 이어 쌓는다.
Widget? _drawingStorySection(
  ReportDetailDto report,
  VoiceAnswerPlaybackController? playbackController, {
  bool flat = false,
}) {
  final subjects = report.subjectDetails;
  final expression = report.childExpression;
  final hasExpression = expression != null && !expression.isEmpty;
  if (subjects.isEmpty && !hasExpression) return null;
  final observations = [
    for (final subject in subjects) ...subject.visionObservations,
  ];
  final qaPairs = [
    for (final subject in subjects) ...subject.qaPairs,
  ];
  return _ReportSection(
    key: const ValueKey('report-drawing-story'),
    title: '그림과 나눈 이야기',
    backgroundColor: const Color(0xFFEAF6FA),
    accentColor: const Color(0xFF8CC6D8),
    flat: flat,
    children: [
      _DrawingStoryBody(
        observations: observations,
        expression: hasExpression ? expression : null,
        playbackController: playbackController,
        qaPairs: qaPairs,
      ),
    ],
  );
}

/// 그림 서술과 대화 전문을 접었다 편다.
///
/// 활동이 길수록 문답이 계속 늘어나 오른쪽 단만 길어진다. 두 단 높이를 실제로
/// 재서 맞추려면 왼쪽의 음성 재생 버튼이 상태마다 높이를 바꿔 내용이 나타났다
/// 사라진다 — 그래서 높이가 아니라 **개수**로 자른다(S15P11B209-996).
///
/// 대표 발화는 자르지 않는다. 서버가 이미 골라 보낸 짧은 목록이고, 재생 가능한
/// 발화(`STT`)가 앞에 온다는 보장이 없어 잘라내면 아이 목소리가 통째로 숨는다.
class _DrawingStoryBody extends StatefulWidget {
  const _DrawingStoryBody({
    required this.observations,
    required this.expression,
    required this.playbackController,
    required this.qaPairs,
  });

  final List<String> observations;
  final ReportChildExpressionDto? expression;
  final VoiceAnswerPlaybackController? playbackController;
  final List<ReportQaPairDto> qaPairs;

  /// 접었을 때 보여줄 그림 서술 개수.
  static const collapsedObservations = 1;

  /// 접었을 때 보여줄 문답 쌍 개수.
  static const collapsedQaPairs = 3;

  @override
  State<_DrawingStoryBody> createState() => _DrawingStoryBodyState();
}

class _DrawingStoryBodyState extends State<_DrawingStoryBody> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final observations = _expanded
        ? widget.observations
        : widget.observations
              .take(_DrawingStoryBody.collapsedObservations)
              .toList();
    final qaPairs = _expanded
        ? widget.qaPairs
        : widget.qaPairs.take(_DrawingStoryBody.collapsedQaPairs).toList();
    final hasMore =
        widget.observations.length > _DrawingStoryBody.collapsedObservations ||
        widget.qaPairs.length > _DrawingStoryBody.collapsedQaPairs;

    // 왼쪽 — 그림에서 보인 것과 아이가 한 말. 오른쪽 — 대화 전문.
    final story = <Widget>[
      for (final observation in observations) _Bullet(title: observation),
      if (widget.expression case final expression?) ...[
        if (observations.isNotEmpty) const SizedBox(height: AppSpacing.xs),
        _ChildExpression(
          expression: expression,
          playbackController: widget.playbackController,
        ),
      ],
    ];
    final transcript = <Widget>[
      if (qaPairs.isNotEmpty) ...[
        Semantics(
          header: true,
          child: const Text(
            '대화 전문',
            key: ValueKey('report-transcript'),
            style: _groupTitleStyle,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        for (final pair in qaPairs) _QaPairTile(pair: pair),
      ],
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _BlockColumns(left: story, right: transcript),
        // 두 단을 한꺼번에 여닫는다. 한쪽만 펴지면 짝이 안 맞아 보인다.
        if (hasMore)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('report-story-more'),
              onPressed: () => setState(() => _expanded = !_expanded),
              icon: Icon(
                _expanded
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
              ),
              label: Text(_expanded ? '접기' : '더보기'),
            ),
          ),
      ],
    );
  }
}

/// 아이의 표현 요약과 대표 발화. 발화는 저장된 음성이 있으면 재생할 수 있다.
///
/// 줄 간격을 [_childExpressionSection]보다 좁혀 요약·키워드·발화가 한 덩어리로
/// 읽히게 한다 — 통합 블럭 안에서는 각 줄이 독립된 문단처럼 보이면 안 된다.
class _ChildExpression extends StatelessWidget {
  const _ChildExpression({
    required this.expression,
    required this.playbackController,
  });

  final ReportChildExpressionDto expression;
  final VoiceAnswerPlaybackController? playbackController;

  @override
  Widget build(BuildContext context) => Column(
    key: const ValueKey('report-child-expression'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (expression.summary case final summary?)
        Text(summary, style: const TextStyle(color: AppColors.ink, height: 1.5)),
      if (expression.keywords.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xxs,
          children: [
            for (final word in expression.keywords) Chip(label: Text(word)),
          ],
        ),
      ],
      if (expression.expressedEmotionText case final text?) ...[
        const SizedBox(height: AppSpacing.xxs),
        Text(text, style: const TextStyle(color: AppColors.ink, height: 1.5)),
      ],
      for (final utterance in expression.representativeUtterances)
        _Utterance(utterance: utterance, playbackController: playbackController),
    ],
  );
}

/// HTP 전용 중심 섹션 — 집·나무·사람을 하나씩, 그 그림과 그 그림에서 나온
/// 이야기를 한 장에 묶어 본다.
///
/// 그림일기 경로는 계약 §11 순서(그림 → 주제별 관찰·문답)를 그대로 쓰지만,
/// HTP는 "어떤 그림에서 무슨 이야기가 나왔는지"가 리포트의 본체라 주제 단위로
/// 묶지 않으면 보호자가 그림과 이야기를 이어 읽을 수 없다.
///
/// 보여줄 주제가 하나도 없으면 null을 돌려주고, 호출부가 기존 그림 섹션으로
/// 물러난다(§10 — 빈 섹션은 숨김).
Widget? _htpSubjectStorySection(
  ReportDetailDto report,
  ImageByteFetcher imageFetcher,
) {
  final subjects = [
    for (final subject in report.orderedSubjectReports)
      if (subject.hasImage || subject.hasDetails) subject,
  ];
  if (subjects.isEmpty) return null;
  return _ReportSection(
    key: const ValueKey('report-htp-subject-stories'),
    title: '집·나무·사람, 하나씩 살펴봐요',
    backgroundColor: const Color(0xFFEAF6FA),
    accentColor: const Color(0xFF8CC6D8),
    children: [
      const Text(
        '세 가지를 그리는 동안 아이가 무엇을 그렸고 어떤 이야기를 들려줬는지 모았어요. '
        '잘 그렸는지 가리거나 결과를 매기는 자리가 아니라, 아이와 함께 다시 펼쳐 볼 이야깃거리예요.',
        style: TextStyle(color: AppColors.inkMuted, height: 1.55),
      ),
      const SizedBox(height: AppSpacing.md),
      for (final subject in subjects)
        _HtpSubjectStoryCard(
          subject: subject,
          imageFetcher: imageFetcher,
          linkedTitles: _linkedInterpretationTitles(report, subject),
        ),
    ],
  );
}

/// HTP 한 주제(집/나무/사람)의 그림 + 관찰 + 문답을 한 장에 담는다.
///
/// 그림일기 경로가 쓰는 [_SubjectDrawingCard](그림만)·[_SubjectReportCard]
/// (관찰·문답만)를 대체하는 HTP 전용 카드다.
class _HtpSubjectStoryCard extends StatelessWidget {
  const _HtpSubjectStoryCard({
    required this.subject,
    required this.imageFetcher,
    required this.linkedTitles,
  });

  final ReportSubjectReportDto subject;
  final ImageByteFetcher imageFetcher;

  /// `interpretationRefs`가 가리킨 카드의 **제목**만 담는다. 경향 문구는 근거·
  /// 범위 없이 떠돌지 않도록 여기에 싣지 않는다(§3).
  final List<String> linkedTitles;

  @override
  Widget build(BuildContext context) {
    final label = _subjectLabel(subject.subjectType);
    final code = subject.subjectType ?? 'UNKNOWN';
    return Container(
      key: ValueKey('report-htp-subject-$code'),
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              '$label 그림',
              style: const TextStyle(
                color: AppColors.ink,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (subject.hasImage) ...[
            const SizedBox(height: AppSpacing.sm),
            AspectRatio(
              aspectRatio: 4 / 3,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: AuthenticatedImage(
                  key: ValueKey('report-htp-subject-image-$code'),
                  url: subject.imageUrl,
                  fetcher: imageFetcher,
                  fit: BoxFit.contain,
                  semanticLabel: '$label 완성 그림',
                  placeholderBuilder: (_) => const _ImagePlaceholder(),
                ),
              ),
            ),
          ],
          if (subject.visionObservations.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            const Text('그림에서 보이는 것', style: AppTypography.label),
            const SizedBox(height: AppSpacing.xxs),
            for (final observation in subject.visionObservations)
              _Bullet(title: observation),
          ],
          if (subject.qaPairs.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            const Text('이 그림에서 나눈 이야기', style: AppTypography.label),
            const SizedBox(height: AppSpacing.xxs),
            _QaPairList(pairs: subject.qaPairs),
          ],
          if (linkedTitles.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            const Text('이어서 이야기해 보면 좋아요', style: AppTypography.label),
            const SizedBox(height: AppSpacing.xxs),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final title in linkedTitles) Chip(label: Text(title)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// §5-1 `interpretationRefs`는 같은 응답 `publicInterpretations`의 **배열
/// 인덱스**(0-based)다 — category 값이 아니다. 화면이 카테고리 순으로 정렬한
/// 결과가 아니라 **서버가 준 원래 순서**에 대고 풀어야 다른 카드를 가리키지
/// 않는다. 범위를 벗어난 값은 조용히 버린다.
List<String> _linkedInterpretationTitles(
  ReportDetailDto report,
  ReportSubjectReportDto subject,
) {
  final source = report.publicInterpretations;
  final titles = <String>[];
  for (final ref in subject.interpretationRefs) {
    if (ref < 0 || ref >= source.length) continue;
    final title = _interpretationTitle(source[ref]);
    if (!titles.contains(title)) titles.add(title);
  }
  return titles;
}

/// §2-1 "이런 모습이 보였어요" — AI 자체 검토를 통과해 보호자에게 열린 관찰
/// 특징만 서버가 싣는다. 화면은 중립 색·중립 문구만 쓰고, 수치·확률·내부
/// 코드는 표시하지 않는다.
Widget? _observedFeaturesSection(ReportDetailDto report) {
  final features = [
    for (final feature in report.observedFeatures)
      if (!feature.isEmpty) feature,
  ];
  if (features.isEmpty) return null;
  return _ReportSection(
    key: const ValueKey('report-observed-features'),
    title: '이런 모습이 보였어요',
    backgroundColor: AppColors.lavenderSoft,
    accentColor: AppColors.lavender,
    children: [
      for (final feature in features) _ObservedFeatureTile(feature: feature),
    ],
  );
}

/// 그림일기·자유 그림의 통합 "이런 모습이 보였어요"(S15P11B209-996).
///
/// 관찰 특징(§2-1)과 심리 경향(§3)은 둘 다 "아이에게서 무엇이 보였나"를 말한다.
/// 카드가 나뉘어 있으면 보호자가 관찰과 해석을 별개의 이야기로 읽게 되는데,
/// 실제로는 앞의 관찰이 뒤의 경향을 뒷받침하는 관계다. 한 블럭에 담되 순서를
/// 지켜 관찰을 먼저 보여준다 — 해석보다 사실이 앞이다.
Widget? _observationsSection(ReportDetailDto report, {bool flat = false}) {
  final features = [
    for (final feature in report.observedFeatures)
      if (!feature.isEmpty) feature,
  ];
  final interpretations = _orderedInterpretations(report);
  final guideGroups = _guideGroups(report);
  if (features.isEmpty && interpretations.isEmpty && guideGroups.isEmpty) {
    return null;
  }
  final evidenceById = <int, ReportEvidenceItemDto>{
    for (final item in report.evidenceItems) ?item.evidenceId: item,
  };
  // 왼쪽 — 무엇이 보였고 어떤 경향으로 읽히는가.
  final observed = <Widget>[
    for (final feature in features) _ObservedFeatureTile(feature: feature),
    if (interpretations.isNotEmpty) ...[
      if (features.isNotEmpty) const SizedBox(height: AppSpacing.xs),
      Semantics(
        header: true,
        child: const Text(
          '주요 심리 경향',
          key: ValueKey('report-interpretations'),
          style: _groupTitleStyle,
        ),
      ),
      const SizedBox(height: AppSpacing.sm),
      for (final (index, interpretation) in interpretations.indexed) ...[
        if (index > 0) const SizedBox(height: AppSpacing.md),
        _InterpretationCard(
          index: index,
          interpretation: interpretation,
          evidenceById: evidenceById,
          showConfidence: false,
          flat: true,
        ),
      ],
    ],
  ];
  // 오른쪽 — 그래서 보호자가 무엇을 해 볼 수 있는가.
  final guides = <Widget>[
    for (final (index, group) in guideGroups.indexed) ...[
      if (index > 0) const SizedBox(height: AppSpacing.md),
      Semantics(
        header: true,
        child: Text(
          group.title,
          key: ValueKey('report-parent-guide-${group.code}'),
          style: _groupTitleStyle,
        ),
      ),
      const SizedBox(height: AppSpacing.xs),
      for (final (order, item) in group.items.indexed)
        _NumberedBullet(number: order + 1, title: item),
    ],
  ];
  return _ReportSection(
    key: const ValueKey('report-observed-features'),
    title: '이런 모습이 보였어요',
    backgroundColor: AppColors.lavenderSoft,
    accentColor: AppColors.lavender,
    flat: flat,
    children: [_BlockColumns(left: observed, right: guides)],
  );
}

/// §6 아이의 표현과 대화 요약 — childExpression.
Widget? _childExpressionSection(
  ReportDetailDto report,
  VoiceAnswerPlaybackController? playbackController,
) {
  final expression = report.childExpression;
  if (expression == null || expression.isEmpty) return null;
  return _ReportSection(
    key: const ValueKey('report-child-expression'),
    title: '아이의 표현과 대화 요약',
    backgroundColor: AppColors.lavenderSoft,
    accentColor: AppColors.lavender,
    children: [
      if (expression.summary case final summary?) ...[
        Text(
          summary,
          style: const TextStyle(color: AppColors.ink, height: 1.55),
        ),
        const SizedBox(height: AppSpacing.sm),
      ],
      if (expression.keywords.isNotEmpty) ...[
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (final word in expression.keywords) Chip(label: Text(word)),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
      ],
      if (expression.expressedEmotionText case final text?) ...[
        Text(text, style: const TextStyle(color: AppColors.ink)),
        if (expression.representativeUtterances.isNotEmpty)
          const SizedBox(height: AppSpacing.md),
      ],
      for (final utterance in expression.representativeUtterances)
        _Utterance(
          utterance: utterance,
          playbackController: playbackController,
        ),
    ],
  );
}

/// §6 대화 요약 — conversationSummary.
Widget? _conversationSummarySection(ReportDetailDto report) {
  final conversation = report.conversationSummary;
  if (conversation == null || conversation.isEmpty) return null;
  final hasCounts =
      conversation.questionCount != null ||
      conversation.answeredCount != null ||
      conversation.skippedCount != null;
  return _ReportSection(
    key: const ValueKey('report-conversation-summary'),
    title: '대화 요약',
    backgroundColor: AppColors.tangerineSoft,
    accentColor: AppColors.tangerine,
    children: [
      if (hasCounts)
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            if (conversation.questionCount case final count?)
              _StatisticTile(label: '질문', value: '$count개'),
            if (conversation.answeredCount case final count?)
              _StatisticTile(label: '대답', value: '$count개'),
            if (conversation.skippedCount case final count?)
              _StatisticTile(label: '건너뜀', value: '$count개'),
          ],
        ),
      if (conversation.summary case final summary?) ...[
        if (hasCounts) const SizedBox(height: AppSpacing.md),
        Text(
          summary,
          style: const TextStyle(color: AppColors.ink, height: 1.55),
        ),
      ],
    ],
  );
}

/// §7 activityFacts — 수치만, 심리 해석을 붙이지 않는다.
///
/// [isHtp]이면 제목에서 측정·지표 뉘앙스("객관적인")를 빼고 그리는 동안 실제로
/// 있었던 일을 가리키는 말로 바꾼다.
Widget? _activityFactsSection(ReportDetailDto report, {bool isHtp = false}) {
  final facts = report.activityFacts;
  // 필압이 기록됐다는 사실만 있고(값 없음) 나머지 수치가 비어도 섹션을 보여준다
  // (S15P11B209-870의 "필압 정보: 기록됨" 표시를 잃지 않기 위함).
  if (facts == null || (facts.isEmpty && !facts.pressureAvailable)) return null;
  final tiles = <Widget>[
    if (facts.pauseCount case final count?)
      _StatisticTile(label: '멈춤', value: '$count회'),
    if (facts.eraseCount case final count?)
      _StatisticTile(label: '지우기', value: '$count회'),
    if (facts.undoCount case final count?)
      _StatisticTile(label: '되돌리기', value: '$count회'),
    if (facts.questionCount case final count?)
      _StatisticTile(label: '질문', value: '$count회'),
    if (facts.answerCount case final count?)
      _StatisticTile(label: '답변', value: '$count회'),
    if (facts.skipCount case final count?)
      _StatisticTile(label: '건너뜀', value: '$count회'),
    if (facts.detectedElementCount case final count?)
      _StatisticTile(label: '탐지된 요소', value: '$count개'),
    // 필압은 실제 평균값이 있으면 값을 보여주고, 값 없이 기록 여부만 있으면
    // "기록됨" 지표만 보여준다(S15P11B209-870).
    if (facts.hasPressureValue)
      _StatisticTile(
        label: '평균 필압',
        value: facts.pressureValue!.toStringAsFixed(2),
      )
    else if (facts.pressureAvailable)
      const _StatisticTile(label: '필압 정보', value: '기록됨'),
  ];
  // "그린 시간"은 스트로크에서 집계한 실제로 그린 시간이며, §2의 세션 기준
  // "활동 시간"과 다른 값이다(S15P11B209-870). 서버가 밀리초(drawingDurationMs)로
  // 주면 그 값을 우선 쓰고, 초 단위 계약(drawingDurationSec)만 있으면 그것을 쓴다.
  final drawingDuration =
      formatActivityDuration(facts.drawingDurationMs) ??
      _secToDuration(facts.drawingDurationSec);
  final durationLines = <Widget>[
    if (_secToDuration(facts.totalDurationSec) case final value?)
      _InfoLine(label: '총 활동 시간', value: value),
    if (drawingDuration case final value?)
      _InfoLine(label: '그린 시간', value: value),
  ];
  return _ReportSection(
    key: const ValueKey('report-activity-facts'),
    title: isHtp ? '그리는 동안 있었던 일' : '객관적인 활동 기록',
    backgroundColor: AppColors.leafSoft,
    accentColor: AppColors.leaf,
    children: [
      if (facts.detectedObjects.isNotEmpty)
        _InfoLine(label: '그린 것', value: facts.detectedObjects.join(', ')),
      ...durationLines,
      if (tiles.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: tiles,
        ),
      ],
      if (facts.notes.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.md),
        for (final note in facts.notes) _Bullet(title: note),
      ],
      if (facts.truncated) ...[
        const SizedBox(height: AppSpacing.sm),
        const Text(
          '저장된 구간까지만 집계된 값입니다.',
          style: TextStyle(color: AppColors.inkMuted, height: 1.45),
        ),
      ],
      if (facts.aggregatedHtp) ...[
        const SizedBox(height: AppSpacing.xs),
        const Text(
          '집·나무·사람 세 활동을 합친 기록입니다.',
          style: TextStyle(color: AppColors.inkMuted, height: 1.45),
        ),
      ],
    ],
  );
}

const _guideTitles = <String, String>{
  'DRAWING_CONVERSATION': '그림으로 대화해 보세요',
  'DAILY_PARENTING': '일상에서 이렇게 도와주세요',
  'HOME_OBSERVATION': '가정에서 살펴봐 주세요',
  'PROFESSIONAL_SUPPORT': '도움이 필요할 때',
};

/// 서버 `guideType`을 화면에 보일 묶음으로 접는다(S15P11B209-996).
///
/// 계약은 가이드를 네 갈래로 주지만, 보호자가 읽을 때는 성격이 겹치는 것들이
/// 있다. 그림을 놓고 나눌 말(`DRAWING_CONVERSATION`)은 구형 응답의 대화 가이드와
/// 같은 이야기고, 일상 육아(`DAILY_PARENTING`)와 가정 관찰(`HOME_OBSERVATION`)은
/// 둘 다 "집에서 이렇게 지켜봐 주세요"다. 두 묶음으로 접는다.
///
/// 계약에 없는 유형이 와도 잃지 않고 원래 이름으로 뒤에 붙인다.
List<({String code, String title, List<String> items})> _guideGroups(
  ReportDetailDto report,
) {
  final byType = <String, List<String>>{};
  for (final guide in report.orderedParentGuides) {
    byType
        .putIfAbsent(guide.guideType ?? 'UNKNOWN', () => <String>[])
        .addAll(guide.items);
  }
  List<String> take(String code) => byType.remove(code) ?? const <String>[];
  final conversation = [
    ...take('DRAWING_CONVERSATION'),
    ...report.guardianConversationGuide,
  ];
  final home = [...take('DAILY_PARENTING'), ...take('HOME_OBSERVATION')];
  // '도움이 필요할 때'(전문 도움 안내)는 그림일기 리포트에서 보여주지 않는다.
  // 아래 미확인 유형 보정에 다시 걸리지 않도록 여기서 확실히 걷어낸다.
  take('PROFESSIONAL_SUPPORT');
  return [
    if (conversation.isNotEmpty)
      (
        code: 'DRAWING_CONVERSATION',
        title: '보호자 대화 가이드',
        items: conversation,
      ),
    if (home.isNotEmpty)
      (code: 'DAILY_PARENTING', title: '일상에서 살펴봐 주세요', items: home),
    // 남은 것은 모르는 유형이다. 조용히 버리지 않는다.
    for (final entry in byType.entries)
      if (entry.value.isNotEmpty)
        (
          code: entry.key,
          title: _guideTitles[entry.key] ?? '보호자 가이드',
          items: entry.value,
        ),
  ];
}

/// §8·§9·§10 보호자 가이드 — parentGuides를 guideType별 섹션으로 나눈다.
/// HTP 전용이다. 그림일기·자유 그림은 [_parentGuideSection]으로 합쳐 보여준다.
List<Widget> _parentGuideSections(ReportDetailDto report) => [
  for (final guide in report.orderedParentGuides)
    _ReportSection(
      key: ValueKey('report-parent-guide-${guide.guideType ?? 'UNKNOWN'}'),
      title: _guideTitles[guide.guideType] ?? '보호자 가이드',
      backgroundColor: const Color(0xFFF2F6E8),
      accentColor: AppColors.leaf,
      children: [
        for (final (index, item) in guide.items.indexed)
          _NumberedBullet(number: index + 1, title: item),
      ],
    ),
];

/// 구형 응답 호환 — parentGuides가 없을 때 guardianConversationGuide 섹션.
Widget? _legacyGuideSection(ReportDetailDto report) {
  final guide = report.guardianConversationGuide;
  if (guide.isEmpty) return null;
  return _ReportSection(
    key: const ValueKey('report-conversation-guide'),
    title: '보호자 대화 가이드',
    backgroundColor: const Color(0xFFF2F6E8),
    accentColor: AppColors.leaf,
    children: [
      for (final (index, question) in guide.indexed)
        _NumberedBullet(number: index + 1, title: question),
    ],
  );
}

String? _secToDuration(int? seconds) =>
    seconds == null ? null : formatActivityDuration(seconds * 1000);

// ── 카테고리·근거·문답 라벨 ────────────────────────────────────────────────

String _interpretationTitle(ReportInterpretationDto item) =>
    item.title ?? _categoryFallbackTitle(item.category);

String _categoryFallbackTitle(String? category) => switch (category) {
  'RELATIONSHIP' => '관계',
  'EMOTION' => '감정',
  'SELF_EXPRESSION' => '자기표현',
  'ACTIVITY_STYLE' => '활동 방식',
  'ADAPTATION' => '적응',
  _ => '관찰된 경향',
};

IconData _categoryIcon(String? category) => switch (category) {
  'RELATIONSHIP' => Icons.favorite_border_rounded,
  'EMOTION' => Icons.emoji_emotions_outlined,
  'SELF_EXPRESSION' => Icons.brush_outlined,
  'ACTIVITY_STYLE' => Icons.timeline_rounded,
  'ADAPTATION' => Icons.spa_outlined,
  _ => Icons.auto_awesome_outlined,
};

Color _categoryColor(String? category) => switch (category) {
  'RELATIONSHIP' => AppColors.lavender,
  'EMOTION' => AppColors.drawingBlue,
  'SELF_EXPRESSION' => AppColors.leaf,
  'ACTIVITY_STYLE' => AppColors.lavender,
  'ADAPTATION' => AppColors.leaf,
  _ => AppColors.lavender,
};

/// 계약 §3 `confidence` 를 보호자가 읽을 문구로 바꾼다(S15P11B209-982).
///
/// "확신도 강"이 아니라 "근거가 강해요"로 쓴다. 무엇에 대한 확신인지 —
/// 아이 발화가 직접 뒷받침하는지, 그림 하나만 보고 말하는 것인지 — 가
/// 드러나야 보호자가 무게를 가늠할 수 있다.
///
/// 모르는 코드는 `null` 을 돌려주어 배지를 그리지 않는다. 등급 체계가 늘어도
/// 앱이 낯선 값을 그대로 노출하지 않는다.
String? _confidenceLabel(String? confidence) => switch (confidence) {
  'STRONG' => '근거가 강해요',
  'MODERATE' => '근거가 어느 정도 있어요',
  'WEAK' => '근거가 약해요',
  _ => null,
};

/// 확신도 배지 색이다.
///
/// **경고색을 쓰지 않는다.** 근거가 약한 것은 나쁜 소식이 아니라 "덜 확신한다"는
/// 표시일 뿐인데, 빨강을 쓰면 보호자가 아이에게 문제가 있다는 신호로 읽는다.
/// 강함은 초록, 그 아래는 따뜻한 중립색과 회색으로 세기만 낮춘다.
({Color fg, Color bg}) _confidenceColors(String? confidence) =>
    switch (confidence) {
      'STRONG' => (fg: AppColors.leaf, bg: AppColors.leafSoft),
      'MODERATE' => (fg: AppColors.tangerine, bg: AppColors.tangerineSoft),
      _ => (fg: AppColors.inkMuted, bg: AppColors.surfaceSoft),
    };

String _evidenceSourceLabel(String? sourceType) => switch (sourceType) {
  'VISION' => '그림에서 확인',
  'CHILD_ANSWER' => '아이의 답변',
  'SELECTED_EMOTION' => '아이가 선택한 감정',
  'STATED_EMOTION' => '아이가 말한 감정',
  'ACTIVITY_METRIC' => '활동 기록',
  'REPEATED_SUBJECT' => '여러 그림에서 반복',
  'LONGITUDINAL' => '이전 활동에서도 반복',
  _ => '관찰 근거',
};

/// 계약 §2 `activityType` 코드를 화면 문구로 바꾼다. 모르는 코드는 화면에
/// 코드값을 흘리지 않도록 null(줄 숨김)로 둔다.
String? _activityTypeLabel(String? activityType) => switch (activityType) {
  'HTP' => '집·나무·사람 그림',
  'ART_DIARY' => '그림일기',
  'FREE_DRAWING' => '자유 그림',
  _ => null,
};

String _subjectLabel(String? subjectType) => switch (subjectType) {
  'HOUSE' => '집',
  'TREE' => '나무',
  'PERSON' => '사람',
  _ => '그림',
};

/// §3 심리 경향 카드. 근거·범위 문구를 tendencyText와 항상 함께 보여준다.
class _InterpretationCard extends StatelessWidget {
  const _InterpretationCard({
    required this.index,
    required this.interpretation,
    required this.evidenceById,
    this.showConfidence = true,
    this.flat = false,
  });

  final int index;
  final ReportInterpretationDto interpretation;
  final Map<int, ReportEvidenceItemDto> evidenceById;

  /// 확신도 배지("근거가 강해요")를 보일지 여부.
  ///
  /// 그림일기 리포트에서는 끈다(S15P11B209-996) — 근거는 "근거 보기"에서 실제
  /// 문장으로 확인할 수 있고, 등급까지 같이 두면 카드가 판정처럼 읽힌다.
  /// HTP 리포트는 그대로 배지를 쓴다.
  final bool showConfidence;

  /// 흰 카드 테두리 없이 본문에 바로 얹을지 여부.
  ///
  /// 그림일기 리포트는 관찰·경향·가이드가 한 블럭에 들어가므로, 경향만 흰
  /// 카드를 두르면 블럭 안에 블럭이 생긴다(S15P11B209-996).
  final bool flat;

  @override
  Widget build(BuildContext context) {
    final color = _categoryColor(interpretation.category);
    final evidence = [
      for (final ref in interpretation.evidenceRefs) ?evidenceById[ref],
    ];
    final confidenceLabel = showConfidence
        ? _confidenceLabel(interpretation.confidence)
        : null;
    final content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(_categoryIcon(interpretation.category), color: color),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    _interpretationTitle(interpretation),
                    style: const TextStyle(
                      color: AppColors.ink,
                      fontSize: 17,
                      height: 1.3,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
          // 확신도는 경향 문장 **바로 위**에 둔다. 문장을 읽기 전에 어느 정도
          // 무게로 받아들일지 먼저 알려야 한다(CLAUDE.md 9절). 등급이 없으면
          // 배지만 빠지고 카드는 그대로 나온다.
          if (confidenceLabel case final label?) ...[
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: _ConfidenceBadge(
                index: index,
                label: label,
                confidence: interpretation.confidence,
              ),
            ),
          ],
          if (interpretation.tendencyText case final tendency?) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              tendency,
              style: const TextStyle(color: AppColors.ink, height: 1.65),
            ),
          ],
          if (interpretation.scopeText case final scope?) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              scope,
              style: const TextStyle(
                color: AppColors.inkMuted,
                height: 1.5,
                fontSize: 14,
              ),
            ),
          ],
          if (evidence.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            _EvidenceExpansion(index: index, evidence: evidence),
          ],
          if (interpretation.homeObservationGuide case final guide?) ...[
            const SizedBox(height: AppSpacing.sm),
            _HomeObservationGuide(text: guide, flat: flat),
          ],
        ],
    );
    if (flat) {
      return KeyedSubtree(
        key: ValueKey('report-interpretation-$index'),
        child: content,
      );
    }
    return Container(
      key: ValueKey('report-interpretation-$index'),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: content,
    );
  }
}

/// 경향 카드에 붙는 "집에서 이렇게 살펴봐 주세요" 한 줄.
///
/// [flat]이면 상자를 두르지 않고 아이콘 색도 블럭 강조색(라벤더)에 맞춘다.
/// 그림일기 리포트는 관찰·경향·가이드가 한 블럭이라, 여기만 초록 상자를 두면
/// 블럭 안에 블럭이 생기고 같은 눈 아이콘이 두 색으로 갈린다(S15P11B209-996).
/// HTP 리포트는 경향 카드가 독립돼 있어 기존 초록 상자를 그대로 쓴다.
class _HomeObservationGuide extends StatelessWidget {
  const _HomeObservationGuide({required this.text, required this.flat});

  final String text;
  final bool flat;

  @override
  Widget build(BuildContext context) {
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(top: flat ? 3 : 0),
          child: Icon(
            Icons.visibility_outlined,
            size: 18,
            color: flat ? AppColors.lavender : AppColors.leaf,
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(color: AppColors.ink, height: 1.5),
          ),
        ),
      ],
    );
    if (flat) return row;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.leafSoft,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: row,
    );
  }
}

/// 해석 카드의 확신도 배지(S15P11B209-982).
///
/// 근거 종류로 서버가 계산한 등급을 그대로 보여준다 — 앱은 판정하지 않는다.
/// 확신도를 감추면 아이 발화가 직접 뒷받침하는 해석과 그림 한 장에서 나온
/// 추측이 같은 무게로 읽힌다(CLAUDE.md 9절).
class _ConfidenceBadge extends StatelessWidget {
  const _ConfidenceBadge({
    required this.index,
    required this.label,
    required this.confidence,
  });

  final int index;
  final String label;
  final String? confidence;

  @override
  Widget build(BuildContext context) {
    final colors = _confidenceColors(confidence);
    return Semantics(
      // 배지만 따로 읽히면 무엇의 근거인지 알 수 없다. 스크린 리더에는 대상을
      // 붙여 읽어 준다.
      label: '이 해석의 $label',
      excludeSemantics: true,
      child: DecoratedBox(
        key: ValueKey('report-interpretation-$index-confidence'),
        decoration: BoxDecoration(
          color: colors.bg,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: colors.fg.withValues(alpha: 0.35)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          child: Text(
            label,
            style: TextStyle(
              color: colors.fg,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

/// "근거 보기" — 근거를 접었다 펴는 목록. sourceType은 라벨로만 노출한다.
class _EvidenceExpansion extends StatefulWidget {
  const _EvidenceExpansion({required this.index, required this.evidence});

  final int index;
  final List<ReportEvidenceItemDto> evidence;

  @override
  State<_EvidenceExpansion> createState() => _EvidenceExpansionState();
}

class _EvidenceExpansionState extends State<_EvidenceExpansion> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) => Theme(
    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
    child: ExpansionTile(
      key: ValueKey('report-interpretation-evidence-${widget.index}'),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: AppSpacing.xs),
      // expandedAlignment 기본값이 center라 근거 목록이 가운데로 몰린다.
      // 본문과 같은 왼쪽 기준선에 맞춘다(S15P11B209-996).
      expandedAlignment: Alignment.centerLeft,
      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
      shape: const Border(),
      collapsedShape: const Border(),
      onExpansionChanged: (value) => setState(() => _expanded = value),
      // 기본 trailing은 카드 오른쪽 끝에 붙어 글자와 멀찍이 떨어진다. 화살표를
      // 글자 바로 옆으로 옮겨 무엇을 펼치는 버튼인지 붙여 읽히게 한다.
      trailing: const SizedBox.shrink(),
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedRotation(
            turns: _expanded ? 0.5 : 0,
            duration: const Duration(milliseconds: 180),
            child: const Icon(
              Icons.expand_more_rounded,
              size: 20,
              color: AppColors.lavender,
            ),
          ),
          const SizedBox(width: AppSpacing.xxs),
          // 큰 글자·좁은 화면에서 글자와 화살표가 폭을 넘기지 않도록 글자가
          // 먼저 줄어든다. Flexible이 없으면 320px·textScale 2.0에서 넘친다.
          const Flexible(
            child: Text(
              '근거 보기',
              style: TextStyle(
                color: AppColors.lavender,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      children: [
        for (final item in widget.evidence)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _evidenceSourceLabel(item.sourceType),
                  style: AppTypography.label,
                ),
                if (item.text case final text?)
                  Text(
                    text,
                    style: const TextStyle(color: AppColors.ink, height: 1.5),
                  ),
              ],
            ),
          ),
      ],
    ),
  );
}

/// §6 문답 목록 — 대표 문답 최대 3개, 나머지는 "대화 더 보기"로 접는다.
class _QaPairList extends StatefulWidget {
  const _QaPairList({required this.pairs});

  final List<ReportQaPairDto> pairs;

  @override
  State<_QaPairList> createState() => _QaPairListState();
}

class _QaPairListState extends State<_QaPairList> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final representative = [
      for (final pair in widget.pairs)
        if (pair.isRepresentative) pair,
    ];
    final ordered = representative.isEmpty ? widget.pairs : representative;
    final rest = [
      for (final pair in widget.pairs)
        if (!ordered.take(3).contains(pair)) pair,
    ];
    final primary = ordered.take(3).toList();
    final overflow = _expanded ? rest : const <ReportQaPairDto>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final pair in [...primary, ...overflow]) _QaPairTile(pair: pair),
        if (rest.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const ValueKey('report-qa-more'),
              onPressed: () => setState(() => _expanded = !_expanded),
              child: Text(_expanded ? '대화 접기' : '대화 더 보기'),
            ),
          ),
      ],
    );
  }
}

class _QaPairTile extends StatelessWidget {
  const _QaPairTile({required this.pair});

  final ReportQaPairDto pair;

  @override
  Widget build(BuildContext context) {
    final String answerText;
    if (pair.state == 'SKIPPED') {
      answerText = '이 질문은 건너뛰었어요';
    } else if (pair.answer == null || pair.answer!.trim().isEmpty) {
      answerText = '답하지 않았어요';
    } else {
      answerText = pair.answer!;
    }
    final needsVoiceConfirm =
        pair.inputType == 'VOICE' && pair.sttNeedsConfirmation;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (pair.question case final question?)
            Text(
              'Q. $question',
              style: const TextStyle(
                color: AppColors.ink,
                fontWeight: FontWeight.w700,
                height: 1.5,
              ),
            ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'A. $answerText',
            style: const TextStyle(color: AppColors.inkMuted, height: 1.5),
          ),
          if (needsVoiceConfirm) ...[
            const SizedBox(height: AppSpacing.xxs),
            const Text(
              '음성 인식 내용을 확인해 주세요',
              style: TextStyle(color: AppColors.inkMuted, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }
}

/// §2-1 관찰 특징 한 건. 제목·내용·근거 요약을 위아래로 쌓고, 근거는 라벨 없이
/// 조용한 보조 문장으로 둔다(경고·위험 표현 금지).
class _ObservedFeatureTile extends StatelessWidget {
  const _ObservedFeatureTile({required this.feature});

  final ReportObservedFeatureDto feature;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Icon(
            Icons.visibility_outlined,
            size: 18,
            color: AppColors.lavender,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (feature.title case final title?)
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.ink,
                    height: 1.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              if (feature.description case final description?)
                Text(
                  description,
                  style: const TextStyle(color: AppColors.ink, height: 1.55),
                ),
              if (feature.evidenceSummary case final evidence?)
                Text(
                  evidence,
                  style: const TextStyle(
                    color: AppColors.inkMuted,
                    height: 1.45,
                    fontSize: 13,
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({
    required this.child,
    this.backgroundColor = AppColors.surface,
    this.borderColor = AppColors.outline,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    super.key,
  });
  final Widget child;
  final Color backgroundColor;
  final Color borderColor;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      border: Border.all(color: borderColor),
      boxShadow: const [
        BoxShadow(
          color: Color(0x10000000),
          blurRadius: 18,
          offset: Offset(0, 6),
        ),
      ],
    ),
    child: child,
  );
}

class _ReportSection extends StatelessWidget {
  const _ReportSection({
    required this.title,
    required this.children,
    this.backgroundColor = AppColors.surface,
    this.accentColor = AppColors.lavender,
    this.flat = false,
    super.key,
  });
  final String title;
  final List<Widget> children;
  final Color backgroundColor;
  final Color accentColor;

  /// 카드 없이 제목과 내용만 돌려줄지 여부.
  ///
  /// 그림일기 리포트는 전체가 한 장이라 섹션마다 카드를 두르면 블럭 안에 블럭이
  /// 생긴다(S15P11B209-996). 색은 배경이 아니라 제목 글자가 나른다.
  final bool flat;

  @override
  Widget build(BuildContext context) {
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            title,
            style: TextStyle(
              color: accentColor,
              fontSize: 20,
              height: 1.3,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        ...children,
      ],
    );
    if (flat) return body;
    return _ReportCard(
      backgroundColor: backgroundColor,
      borderColor: accentColor.withValues(alpha: 0.45),
      child: body,
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final labelText = Text(
          label,
          style: const TextStyle(color: AppColors.inkMuted),
        );
        final valueText = Text(
          value,
          style: const TextStyle(
            color: AppColors.ink,
            fontWeight: FontWeight.w700,
          ),
        );
        if (constraints.maxWidth < 280) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              labelText,
              const SizedBox(height: AppSpacing.xxs),
              valueText,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 96, child: labelText),
            Expanded(child: valueText),
          ],
        );
      },
    ),
  );
}

class _StatisticTile extends StatelessWidget {
  const _StatisticTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minWidth: 104, maxWidth: 176),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.76),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.outline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: AppColors.inkMuted)),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              value,
              style: const TextStyle(
                color: AppColors.ink,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Bullet extends StatelessWidget {
  const _Bullet({required this.title});
  final String title;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 7),
          child: Icon(Icons.circle, size: 7, color: AppColors.lavender),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: AppColors.ink,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

class _NumberedBullet extends StatelessWidget {
  const _NumberedBullet({required this.number, required this.title});

  final int number;
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          constraints: const BoxConstraints(
            minWidth: AppSizes.minTouchTarget / 2,
            minHeight: AppSizes.minTouchTarget / 2,
          ),
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: AppColors.surface,
            shape: BoxShape.circle,
          ),
          child: Text(
            '$number',
            style: const TextStyle(
              color: AppColors.leaf,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xxs),
            child: Text(
              title,
              style: const TextStyle(
                color: AppColors.ink,
                height: 1.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

/// 대표 발화 텍스트를 유지하면서 저장 음성으로 확인된 항목만 재생한다.
class _Utterance extends StatelessWidget {
  const _Utterance({required this.utterance, required this.playbackController});

  final ReportUtteranceDto utterance;
  final VoiceAnswerPlaybackController? playbackController;

  @override
  Widget build(BuildContext context) {
    final text = utterance.text;
    final messageId = _playableVoiceMessageId(utterance);
    final canPlay = messageId != null && playbackController != null;
    if (text == null && !canPlay) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (text != null)
            Text('“$text”', style: const TextStyle(color: AppColors.ink)),
          if (text != null && canPlay) const SizedBox(height: AppSpacing.xxs),
          if (canPlay)
            VoiceAnswerPlaybackControl(
              controller: playbackController!,
              messageId: messageId,
              // 발화가 줄줄이 이어지는 자리라 "재생이 끝났어요" 줄이 남으면
              // 문단이 끊긴다. 낭독기 안내는 그대로 나간다(S15P11B209-996).
              showStatusText: false,
            ),
        ],
      ),
    );
  }
}

int? _playableVoiceMessageId(ReportUtteranceDto utterance) {
  final messageId = utterance.messageId;
  return utterance.source == 'STT' && messageId != null && messageId > 0
      ? messageId
      : null;
}

class _ReportActionSection extends StatelessWidget {
  const _ReportActionSection({
    required this.pdfAction,
    required this.onSavePdf,
    required this.onSharePdf,
    this.flat = false,
  });

  final _ReportPdfAction? pdfAction;
  final VoidCallback onSavePdf;
  final VoidCallback onSharePdf;

  /// 카드 없이 내용만 돌려줄지 여부(S15P11B209-996).
  final bool flat;

  @override
  Widget build(BuildContext context) {
    final body = LayoutBuilder(
      builder: (context, constraints) {
        // 넓으면 제목과 저장·공유 버튼을 한 줄에 세운다(S15P11B209-996).
        // 버튼이 바로 옆에 있으면 "저장하거나 공유하세요" 설명은 군더더기다.
        final inline = constraints.maxWidth >= 640;
        final save = AppButton(
          key: const ValueKey('report-save-pdf'),
          label: 'PDF 저장',
          leading: const Icon(Icons.download_rounded),
          isLoading: pdfAction == _ReportPdfAction.save,
          onPressed: pdfAction == null ? onSavePdf : null,
        );
        final share = AppButton(
          key: const ValueKey('report-share-pdf'),
          label: '공유',
          leading: const Icon(Icons.ios_share_rounded),
          variant: AppButtonVariant.secondary,
          isLoading: pdfAction == _ReportPdfAction.share,
          onPressed: pdfAction == null ? onSharePdf : null,
        );
        final home = AppButton(
          key: const ValueKey('report-home-cta'),
          label: '보호자 홈으로 돌아가기',
          variant: AppButtonVariant.secondary,
          onPressed: () => AppRouter.goGuardianHome(context),
        );
        final title = Semantics(
          header: true,
          child: const Text(
            '돌아보기를 마쳤어요',
            style: TextStyle(
              color: AppColors.ink,
              fontSize: 22,
              height: 1.3,
              fontWeight: FontWeight.w900,
            ),
          ),
        );
        const mascot = SizedBox(
          width: 84,
          child: ReportMascotImage(
            assetPath: ReportMascotAssets.complete,
            maxWidth: 84,
            mascotKey: ValueKey('report-mascot-complete'),
          ),
        );
        if (!inline) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  mascot,
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: title),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              save,
              const SizedBox(height: AppSpacing.sm),
              share,
              const SizedBox(height: AppSpacing.sm),
              home,
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                mascot,
                const SizedBox(width: AppSpacing.md),
                Expanded(flex: 3, child: title),
                Expanded(flex: 2, child: save),
                const SizedBox(width: AppSpacing.sm),
                Expanded(flex: 2, child: share),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            home,
          ],
        );
      },
    );
    if (flat) return body;
    return _ReportCard(
      backgroundColor: const Color(0xFFFFF4D5),
      borderColor: AppColors.sunshine,
      child: body,
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder();
  @override
  Widget build(BuildContext context) => const ColoredBox(
    key: ValueKey('report-image-placeholder'),
    color: AppColors.surfaceSoft,
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.image_outlined, color: AppColors.inkMuted, size: 44),
          SizedBox(height: AppSpacing.sm),
          Text('그림을 불러오지 못했어요', style: TextStyle(color: AppColors.inkMuted)),
        ],
      ),
    ),
  );
}

String _date(String isoDate) => isoDate.length >= 10
    ? isoDate.substring(0, 10).replaceAll('-', '.')
    : isoDate;

/// 입력 방식 코드를 보호자가 읽을 수 있는 말로 바꾼다.
///
/// `CANVAS`·`UPLOAD` 는 서버 코드다. 그대로 보여 주면 보호자는 뜻을 알 수 없다. 서버가
/// PDF 에 쓰는 문구와 같은 말을 쓴다(`ReportPdfTemplate.inputMethodText`) — 화면과 저장한
/// 파일이 같은 값을 다르게 부르면 같은 활동인지 알기 어렵다.
///
/// 모르는 값은 감추지 않고 그대로 낸다. 새 입력 방식이 생겼을 때 조용히 사라지는 편이 더 나쁘다.
String _inputMethodLabel(String inputMethod) => switch (inputMethod) {
  'CANVAS' => '앱에서 그리기',
  'UPLOAD' => '그린 그림 올리기',
  _ => inputMethod,
};

String _emotionLabel(String emotion) => switch (emotion) {
  'HAPPY' || 'JOY' => '기쁨',
  'SAD' => '슬픔',
  'ANGRY' => '화남',
  'SCARED' => '무서움',
  'CALM' => '편안함',
  'UNKNOWN' || 'UNSURE' => '잘 모르겠음',
  _ => emotion,
};
