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
      // 계약 §11의 확정 섹션 순서를 그대로 세로로 쌓는다. 데이터가 없는 섹션은
      // 각 빌더가 null을 돌려주어 자연스럽게 빠진다(오류 아님).
      final sections = <Widget>[
        _ReportHero(report: report),
        ?_nonDiagnosticNoticeSection(report),
        ?_overviewSection(report),
        ?_interpretationsSection(report),
        _ReportDrawings(
          report: report,
          imageFetcher: imageFetcher,
          activityRepository: activityRepository,
        ),
        ?_childExpressionSection(report, playbackController),
        ?_conversationSummarySection(report),
        ?_activityFactsSection(report),
        ..._parentGuideSections(report),
        ?_legacyGuideSection(report),
        if (report.hasNoObservations) _noObservationsCard,
        ?_limitationsReferencesSection(report),
        _ReportActionSection(
          pdfAction: pdfAction,
          onSavePdf: onSavePdf,
          onSharePdf: onSharePdf,
        ),
      ];
      return SingleChildScrollView(
        key: ValueKey(isWide ? 'report-wide-layout' : 'report-small-layout'),
        padding: EdgeInsets.all(pagePadding),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppSizes.contentMaxWidth,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (index, section) in sections.indexed) ...[
                  if (index > 0) const SizedBox(height: AppSpacing.lg),
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

/// 계약 §4·§5: 집·나무·사람 완성 그림과 주제별 관찰·문답.
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

    final subjectReports = report.orderedSubjectReports;

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
        if (subjectReports.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          for (final subject in subjectReports)
            _SubjectReportCard(
              report: subject,
              imageFetcher: imageFetcher,
            ),
        ],
      ],
    );
  }
}

/// 계약 §5·§6: 한 주제(집/나무/사람)의 완성 그림·관찰 사실·문답.
class _SubjectReportCard extends StatelessWidget {
  const _SubjectReportCard({required this.report, required this.imageFetcher});

  final ReportSubjectReportDto report;
  final ImageByteFetcher imageFetcher;

  @override
  Widget build(BuildContext context) {
    final label = _subjectLabel(report.subjectType);
    final imageUrl = report.imageUrl;
    return Container(
      key: ValueKey('report-subject-${report.subjectType ?? 'UNKNOWN'}'),
      margin: const EdgeInsets.only(top: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.ink,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (imageUrl != null) ...[
            const SizedBox(height: AppSpacing.sm),
            AspectRatio(
              aspectRatio: 4 / 3,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: AuthenticatedImage(
                  url: imageUrl,
                  fetcher: imageFetcher,
                  fit: BoxFit.contain,
                  semanticLabel: '$label 완성 그림',
                  placeholderBuilder: (_) => const _ImagePlaceholder(),
                ),
              ),
            ),
          ],
          if (report.visionObservations.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            for (final observation in report.visionObservations)
              _Bullet(title: observation),
          ],
          if (report.qaPairs.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            _QaPairList(pairs: report.qaPairs),
          ],
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

/// §1 비진단 안내 — 경고 배너가 아니라 중립 정보 카드.
Widget? _nonDiagnosticNoticeSection(ReportDetailDto report) {
  final notice = report.nonDiagnosticNotice?.trim();
  if (notice == null || notice.isEmpty) return null;
  return _NoticeCard(lines: [notice]);
}

/// §2 한눈에 보는 이번 활동 — 활동 정보와 아이가 고른 감정.
Widget? _overviewSection(ReportDetailDto report) {
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

const _interpretationOrder = <String>[
  'RELATIONSHIP',
  'EMOTION',
  'SELF_EXPRESSION',
  'ACTIVITY_STYLE',
  'ADAPTATION',
];

/// §3 주요 심리 경향 — publicInterpretations 카드. 배열이 비면 숨긴다.
Widget? _interpretationsSection(ReportDetailDto report) {
  if (report.publicInterpretations.isEmpty) return null;
  int rank(ReportInterpretationDto item) {
    final index = _interpretationOrder.indexOf(item.category ?? '');
    return index < 0 ? _interpretationOrder.length : index;
  }

  final interpretations = [...report.publicInterpretations]
    ..sort((a, b) => rank(a).compareTo(rank(b)));
  final evidenceById = <int, ReportEvidenceItemDto>{
    for (final item in report.evidenceItems) ?item.evidenceId: item,
  };
  return _ReportSection(
    key: const ValueKey('report-interpretations'),
    title: '주요 심리 경향',
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
          children: [for (final word in expression.keywords) Chip(label: Text(word))],
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

/// §7 객관적인 활동 기록 — activityFacts. 수치만, 심리 해석을 붙이지 않는다.
Widget? _activityFactsSection(ReportDetailDto report) {
  final facts = report.activityFacts;
  if (facts == null || facts.isEmpty) return null;
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
    if (facts.hasPressureValue)
      _StatisticTile(
        label: '평균 필압',
        value: facts.pressureValue!.toStringAsFixed(2),
      ),
  ];
  final durationLines = <Widget>[
    if (_secToDuration(facts.totalDurationSec) case final value?)
      _InfoLine(label: '총 활동 시간', value: value),
    if (_secToDuration(facts.drawingDurationSec) case final value?)
      _InfoLine(label: '그린 시간', value: value),
  ];
  return _ReportSection(
    key: const ValueKey('report-activity-facts'),
    title: '객관적인 활동 기록',
    backgroundColor: AppColors.leafSoft,
    accentColor: AppColors.leaf,
    children: [
      if (facts.detectedObjects.isNotEmpty)
        _InfoLine(label: '그린 것', value: facts.detectedObjects.join(', ')),
      ...durationLines,
      if (tiles.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.xs),
        Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: tiles),
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

/// §8·§9·§10 보호자 가이드 — parentGuides를 guideType별 섹션으로 나눈다.
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

/// §11 한계와 참고 자료 — limitations + references.
Widget? _limitationsReferencesSection(ReportDetailDto report) {
  final limitations = report.limitations;
  final references = [
    for (final reference in report.references)
      if ((reference.title?.trim().isNotEmpty ?? false) ||
          (reference.url?.trim().isNotEmpty ?? false))
        reference,
  ];
  if (limitations.isEmpty && references.isEmpty) return null;
  return _ReportSection(
    key: const ValueKey('report-limitations'),
    title: '한계와 참고 자료',
    backgroundColor: AppColors.surfaceSoft,
    accentColor: AppColors.inkMuted,
    children: [
      for (final line in limitations) _Bullet(title: line),
      if (references.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.sm),
        const Text('참고 자료', style: TextStyle(color: AppColors.inkMuted)),
        const SizedBox(height: AppSpacing.xs),
        for (final reference in references) _ReferenceLine(reference: reference),
      ],
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
  });

  final int index;
  final ReportInterpretationDto interpretation;
  final Map<int, ReportEvidenceItemDto> evidenceById;

  @override
  Widget build(BuildContext context) {
    final color = _categoryColor(interpretation.category);
    final evidence = [
      for (final ref in interpretation.evidenceRefs) ?evidenceById[ref],
    ];
    return Container(
      key: ValueKey('report-interpretation-$index'),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
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
          if (interpretation.tendencyText case final tendency?) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              tendency,
              style: const TextStyle(
                color: AppColors.ink,
                height: 1.65,
              ),
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
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.leafSoft,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.visibility_outlined,
                    size: 18,
                    color: AppColors.leaf,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      guide,
                      style: const TextStyle(
                        color: AppColors.ink,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// "근거 보기" — 근거를 접었다 펴는 목록. sourceType은 라벨로만 노출한다.
class _EvidenceExpansion extends StatelessWidget {
  const _EvidenceExpansion({required this.index, required this.evidence});

  final int index;
  final List<ReportEvidenceItemDto> evidence;

  @override
  Widget build(BuildContext context) => Theme(
    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
    child: ExpansionTile(
      key: ValueKey('report-interpretation-evidence-$index'),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: AppSpacing.xs),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      shape: const Border(),
      collapsedShape: const Border(),
      title: const Text(
        '근거 보기',
        style: TextStyle(
          color: AppColors.lavender,
          fontWeight: FontWeight.w700,
        ),
      ),
      children: [
        for (final item in evidence)
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

class _ReferenceLine extends StatelessWidget {
  const _ReferenceLine({required this.reference});

  final ReportReferenceDto reference;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (reference.title case final title?)
          Text(
            title,
            style: const TextStyle(
              color: AppColors.ink,
              fontWeight: FontWeight.w700,
            ),
          ),
        if (reference.url case final url?)
          Text(url, style: AppTypography.caption),
      ],
    ),
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
