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
      return SingleChildScrollView(
        key: ValueKey(isWide ? 'report-wide-layout' : 'report-small-layout'),
        padding: EdgeInsets.all(pagePadding),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppSizes.wideContentMaxWidth,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ReportHero(report: report),
                const SizedBox(height: AppSpacing.lg),
                _ReportOverview(
                  report: report,
                  imageFetcher: imageFetcher,
                  activityRepository: activityRepository,
                ),
                const SizedBox(height: AppSpacing.lg),
                _ReportDetails(
                  report: report,
                  playbackController: playbackController,
                  wide: isWide,
                ),
                if (report.limitations.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.lg),
                  _NoticeCard(lines: report.limitations),
                ],
                const SizedBox(height: AppSpacing.lg),
                _ReportActionSection(
                  pdfAction: pdfAction,
                  onSavePdf: onSavePdf,
                  onSharePdf: onSharePdf,
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

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
  const _ReportHero({required this.report});

  final ReportDetailDto report;

  @override
  Widget build(BuildContext context) => _ReportCard(
    backgroundColor: AppColors.brandYellowSoft,
    borderColor: AppColors.sunshine,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 520;
        final mascot = const ReportMascotImage(
          assetPath: ReportMascotAssets.intro,
          maxWidth: 188,
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
              child: const Text(
                '그림 속 이야기를 함께 돌아볼까요?',
                textAlign: TextAlign.start,
                style: TextStyle(
                  color: AppColors.ink,
                  fontSize: 27,
                  height: 1.25,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              '돌아보기 친구가 아이의 그림과 이야기를 차근차근 정리했어요.',
              style: TextStyle(color: AppColors.inkMuted, height: 1.5),
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                if (report.createdAt case final createdAt?)
                  _MetadataPill(label: _date(createdAt)),
                _MetadataPill(label: '리포트 v${report.reportVersion}'),
              ],
            ),
          ],
        );
        if (compact) {
          return Column(
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 132),
                child: mascot,
              ),
              const SizedBox(height: AppSpacing.md),
              copy,
            ],
          );
        }
        return Row(
          children: [
            SizedBox(width: 172, child: mascot),
            const SizedBox(width: AppSpacing.xl),
            Expanded(child: copy),
          ],
        );
      },
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

class _ReportOverview extends StatelessWidget {
  const _ReportOverview({
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
    final isHtp = session?.drawingTypeCode?.toUpperCase() == 'HTP';
    // 서버는 완성본이 없으면 finalImageUrl을 비우므로 썸네일로 물러난다.
    final imageUrl =
        report.drawing?.finalImageUrl ?? report.drawing?.thumbnailUrl;
    final singleImagePreview = _ReportSingleImagePreview(
      imageUrl: imageUrl,
      imageFetcher: imageFetcher,
    );
    final preview = isHtp
        ? HtpReportGallery(
            childId: session?.childId ?? -1,
            reportDrawingSessionId: session?.drawingSessionId ?? -1,
            repository: activityRepository,
            fallback: singleImagePreview,
          )
        : singleImagePreview;

    return _ReportSection(
      key: const ValueKey('report-drawings-section'),
      title: '완성한 그림',
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

class _ReportDetails extends StatelessWidget {
  const _ReportDetails({
    required this.report,
    required this.playbackController,
    required this.wide,
  });
  final ReportDetailDto report;
  final VoiceAnswerPlaybackController? playbackController;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final expression = report.childExpression;
    final facts = report.activityFacts;
    final conversation = report.conversationSummary;
    final guide = report.guardianConversationGuide;
    final hasExpression =
        expression != null &&
        (expression.expressedEmotionText != null ||
            expression.representativeUtterances.isNotEmpty);
    final hasFacts =
        facts != null && (!facts.isEmpty || facts.pressureAvailable);
    final hasConversation = conversation != null && !conversation.isEmpty;
    final hasGuide = guide.isNotEmpty;
    final hasObservations =
        hasExpression || hasFacts || hasConversation || hasGuide;

    final expressionSection = hasExpression
        ? _ReportSection(
            key: const ValueKey('report-child-expression'),
            title: '아이가 표현한 말과 음성',
            backgroundColor: AppColors.lavenderSoft,
            accentColor: AppColors.lavender,
            children: [
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
          )
        : null;
    final factsSection = hasFacts
        ? _ReportSection(
            key: const ValueKey('report-activity-facts'),
            title: '활동에서 관찰된 내용',
            backgroundColor: AppColors.leafSoft,
            accentColor: AppColors.leaf,
            children: [
              if (facts.detectedObjects.isNotEmpty)
                _InfoLine(
                  label: '그린 것',
                  value: facts.detectedObjects.join(', '),
                ),
              if (facts.pauseCount != null ||
                  facts.eraseCount != null ||
                  facts.pressureAvailable) ...[
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    if (facts.pauseCount case final count?)
                      _StatisticTile(label: '멈춤', value: '$count회'),
                    if (facts.eraseCount case final count?)
                      _StatisticTile(label: '지우기', value: '$count회'),
                    if (facts.pressureAvailable)
                      const _StatisticTile(label: '필압 정보', value: '기록됨'),
                  ],
                ),
              ],
              if (facts.notes.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                for (final note in facts.notes) _Bullet(title: note),
              ],
            ],
          )
        : null;
    final conversationSection = hasConversation
        ? _ReportSection(
            key: const ValueKey('report-conversation-summary'),
            title: '대화 요약',
            backgroundColor: AppColors.tangerineSoft,
            accentColor: AppColors.tangerine,
            children: [
              if (conversation.questionCount != null ||
                  conversation.answeredCount != null ||
                  conversation.skippedCount != null)
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
                if (conversation.questionCount != null ||
                    conversation.answeredCount != null ||
                    conversation.skippedCount != null)
                  const SizedBox(height: AppSpacing.md),
                Text(
                  summary,
                  style: const TextStyle(color: AppColors.ink, height: 1.55),
                ),
              ],
            ],
          )
        : null;
    final activitySection = _activitySection(report);
    final guideSection = hasGuide
        ? _ReportSection(
            key: const ValueKey('report-conversation-guide'),
            title: '보호자 대화 가이드',
            backgroundColor: const Color(0xFFF2F6E8),
            accentColor: AppColors.leaf,
            children: [
              for (final (index, question) in guide.indexed)
                _NumberedBullet(number: index + 1, title: question),
            ],
          )
        : null;
    const noObservations = _ReportCard(
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

    if (!wide) {
      return _SectionColumn(
        children: [
          ?expressionSection,
          ?factsSection,
          ?conversationSection,
          if (!hasObservations) noObservations,
          ?activitySection,
          ?guideSection,
        ],
      );
    }

    final left = <Widget>[?activitySection, ?expressionSection];
    final right = <Widget>[
      ?factsSection,
      ?conversationSection,
      ?guideSection,
      if (!hasObservations) noObservations,
    ];
    if (left.isEmpty) return _SectionColumn(children: right);
    if (right.isEmpty) return _SectionColumn(children: left);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _SectionColumn(children: left)),
        const SizedBox(width: AppSpacing.lg),
        Expanded(child: _SectionColumn(children: right)),
      ],
    );
  }
}

Widget? _activitySection(ReportDetailDto report) {
  final session = report.drawingSession;
  final emotions = report.childExpression?.selectedEmotions ?? const [];
  final lines = <Widget>[
    if (session?.title case final title?)
      _InfoLine(label: '활동 이름', value: title),
    if ((session?.drawingTypeName ?? session?.drawingTypeCode) case final type?)
      _InfoLine(label: '활동 유형', value: type),
    if (session?.inputMethod case final inputMethod?)
      _InfoLine(label: '입력 방식', value: inputMethod),
    if (formatActivityDuration(session?.durationMs) case final duration?)
      _InfoLine(label: '활동 시간', value: duration),
    if (session?.completedAt case final completedAt?)
      _InfoLine(label: '완료일', value: _date(completedAt)),
  ];
  if (lines.isEmpty && emotions.isEmpty) return null;
  return _ReportSection(
    key: const ValueKey('report-activity-info'),
    title: '활동 정보와 선택 감정',
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

class _SectionColumn extends StatelessWidget {
  const _SectionColumn({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final (index, section) in children.indexed) ...[
        if (index > 0) const SizedBox(height: AppSpacing.md),
        section,
      ],
    ],
  );
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({
    required this.child,
    this.backgroundColor = AppColors.surface,
    this.borderColor = AppColors.outline,
    super.key,
  });
  final Widget child;
  final Color backgroundColor;
  final Color borderColor;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.lg),
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
    super.key,
  });
  final String title;
  final List<Widget> children;
  final Color backgroundColor;
  final Color accentColor;

  @override
  Widget build(BuildContext context) => _ReportCard(
    backgroundColor: backgroundColor,
    borderColor: accentColor.withValues(alpha: 0.45),
    child: Column(
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
    ),
  );
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
  });

  final _ReportPdfAction? pdfAction;
  final VoidCallback onSavePdf;
  final VoidCallback onSharePdf;

  @override
  Widget build(BuildContext context) => _ReportCard(
    backgroundColor: const Color(0xFFFFF4D5),
    borderColor: AppColors.sunshine,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 640;
        final copy = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
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
            ),
            const SizedBox(height: AppSpacing.xs),
            const Text(
              '리포트를 저장하거나 공유하고, 보호자 홈에서 다음 활동을 이어가세요.',
              style: TextStyle(color: AppColors.inkMuted, height: 1.5),
            ),
          ],
        );
        final intro = Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(
              width: 108,
              child: ReportMascotImage(
                assetPath: ReportMascotAssets.complete,
                maxWidth: 108,
                mascotKey: ValueKey('report-mascot-complete'),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: copy),
          ],
        );
        final buttons = _ReportActionButtons(
          horizontal: !compact,
          pdfAction: pdfAction,
          onSavePdf: onSavePdf,
          onSharePdf: onSharePdf,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            intro,
            const SizedBox(height: AppSpacing.lg),
            buttons,
          ],
        );
      },
    ),
  );
}

class _ReportActionButtons extends StatelessWidget {
  const _ReportActionButtons({
    required this.horizontal,
    required this.pdfAction,
    required this.onSavePdf,
    required this.onSharePdf,
  });

  final bool horizontal;
  final _ReportPdfAction? pdfAction;
  final VoidCallback onSavePdf;
  final VoidCallback onSharePdf;

  @override
  Widget build(BuildContext context) {
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (horizontal)
          Row(
            children: [
              Expanded(child: save),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: share),
            ],
          )
        else ...[
          save,
          const SizedBox(height: AppSpacing.sm),
          share,
        ],
        const SizedBox(height: AppSpacing.sm),
        AppButton(
          key: const ValueKey('report-home-cta'),
          label: '보호자 홈으로 돌아가기',
          variant: AppButtonVariant.secondary,
          onPressed: () => AppRouter.goGuardianHome(context),
        ),
      ],
    );
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({required this.lines});
  final List<String> lines;
  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('report-non-diagnostic-notice'),
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.lavenderSoft,
      borderRadius: BorderRadius.circular(AppRadius.md),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline_rounded, color: AppColors.lavender),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final line in lines)
                Padding(
                  padding: EdgeInsets.only(
                    bottom: line == lines.last ? 0 : AppSpacing.xs,
                  ),
                  child: Text(
                    line,
                    style: const TextStyle(
                      color: AppColors.inkMuted,
                      height: 1.45,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
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

String _emotionLabel(String emotion) => switch (emotion) {
  'HAPPY' || 'JOY' => '기쁨',
  'SAD' => '슬픔',
  'ANGRY' => '화남',
  'SCARED' => '무서움',
  'CALM' => '편안함',
  'UNKNOWN' || 'UNSURE' => '잘 모르겠음',
  _ => emotion,
};
