import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../app/router/app_router.dart';
import '../../../../app/widgets/app_failure_view.dart';
import '../../../../core/network/network.dart';
import '../../../../design_system/design_system.dart';
import '../../../conversation/conversation.dart';
import '../../data/dto/report_dtos.dart';
import '../../data/services/platform_report_file_actions.dart';
import '../../domain/repositories/report_repository.dart';
import '../../domain/services/report_file_actions.dart';

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
    ReportFileActions? fileActions,
    this.voiceAnswerPlaybackRepository,
    this.voiceAnswerAudioPlayerFactory,
    super.key,
  }) : fileActions = fileActions ?? const PlatformReportFileActions();

  final String reportId;
  final ReportRepository repository;
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
  Object? _failure;
  _ReportPdfAction? _pdfAction;
  VoiceAnswerPlaybackController? _playbackController;

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
    WidgetsBinding.instance.removeObserver(this);
    _playbackController?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    unawaited(_playbackController?.reset());
    final reportId = int.tryParse(widget.reportId);
    if (reportId == null || reportId <= 0) {
      setState(() => _status = _ReportViewStatus.invalidId);
      return;
    }
    setState(() {
      _status = _ReportViewStatus.loading;
      _failure = null;
    });
    try {
      final report = await widget.repository.getReport(reportId);
      if (!mounted) return;
      if (report.reportId != reportId) {
        setState(() {
          _report = null;
          _status = _ReportViewStatus.empty;
        });
        return;
      }
      setState(() {
        _report = report;
        _status = switch (report.reportStatus) {
          'COMPLETED' => _ReportViewStatus.completed,
          'GENERATING' => _ReportViewStatus.generating,
          'FAILED' => _ReportViewStatus.failed,
          _ => _ReportViewStatus.generating,
        };
      });
    } on ApiResponseFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _failure = failure;
        _status = failure.statusCode == 404
            ? _ReportViewStatus.empty
            : _ReportViewStatus.error;
      });
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _failure = error;
          _status = _ReportViewStatus.error;
        });
      }
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
        message: '잠시 후 상태를 다시 확인해 주세요.',
        retryLabel: '다시 확인',
        onRetry: _load,
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
    ),
  };
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
  });
  final ReportDetailDto report;
  final _ReportPdfAction? pdfAction;
  final VoidCallback onSavePdf;
  final VoidCallback onSharePdf;
  final VoiceAnswerPlaybackController? playbackController;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      key: ValueKey(
        constraints.maxWidth >= 900
            ? 'report-wide-layout'
            : 'report-small-layout',
      ),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppSizes.wideContentMaxWidth,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (constraints.maxWidth >= 900)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 5, child: _ReportOverview(report: report)),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(
                      flex: 6,
                      child: _ReportDetails(
                        report: report,
                        playbackController: playbackController,
                      ),
                    ),
                  ],
                )
              else ...[
                _ReportOverview(report: report),
                const SizedBox(height: AppSpacing.lg),
                _ReportDetails(
                  report: report,
                  playbackController: playbackController,
                ),
              ],
              if (report.limitations.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                _NoticeCard(lines: report.limitations),
              ],
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: AppButton(
                      key: const ValueKey('report-save-pdf'),
                      label: 'PDF 저장',
                      leading: const Icon(Icons.download_rounded),
                      isLoading: pdfAction == _ReportPdfAction.save,
                      onPressed: pdfAction == null ? onSavePdf : null,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: AppButton(
                      key: const ValueKey('report-share-pdf'),
                      label: '공유',
                      leading: const Icon(Icons.ios_share_rounded),
                      variant: AppButtonVariant.secondary,
                      isLoading: pdfAction == _ReportPdfAction.share,
                      onPressed: pdfAction == null ? onSharePdf : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              AppButton(
                key: const ValueKey('report-home-cta'),
                label: '보호자 홈으로 돌아가기',
                variant: AppButtonVariant.secondary,
                onPressed: () => AppRouter.goGuardianHome(context),
              ),
            ],
          ),
        ),
      ),
    ),
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

class _ReportOverview extends StatelessWidget {
  const _ReportOverview({required this.report});
  final ReportDetailDto report;

  @override
  Widget build(BuildContext context) {
    final session = report.drawingSession;
    final emotions = report.childExpression?.selectedEmotions ?? const [];
    // 서버는 완성본이 없으면 finalImageUrl을 비우므로 썸네일로 물러난다.
    final imageUrl =
        report.drawing?.finalImageUrl ?? report.drawing?.thumbnailUrl;
    final activityLines = <Widget>[
      if ((session?.drawingTypeName ?? session?.drawingTypeCode)
          case final type?)
        _InfoLine(label: '활동 유형', value: type),
      if (session?.inputMethod case final inputMethod?)
        _InfoLine(label: '입력 방식', value: inputMethod),
      if (_minutes(session?.durationMs) case final duration?)
        _InfoLine(label: '활동 시간', value: duration),
      if (session?.completedAt case final completedAt?)
        _InfoLine(label: '완료일', value: _date(completedAt)),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ReportCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                session?.title ?? '그림 활동 관찰 기록',
                style: const TextStyle(
                  color: AppColors.ink,
                  fontSize: 23,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                [
                  if (report.createdAt case final createdAt?) _date(createdAt),
                  '리포트 v${report.reportVersion}',
                ].join(' · '),
                style: const TextStyle(color: AppColors.inkMuted),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        AspectRatio(
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
                : Image.network(
                    imageUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const _ImagePlaceholder(),
                  ),
          ),
        ),
        if (activityLines.isNotEmpty || emotions.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          _ReportSection(
            key: const ValueKey('report-activity-info'),
            title: '활동 정보',
            children: [
              ...activityLines,
              if (emotions.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                const Text(
                  '아이가 선택한 감정',
                  style: TextStyle(color: AppColors.inkMuted),
                ),
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
          ),
        ],
      ],
    );
  }
}

class _ReportDetails extends StatelessWidget {
  const _ReportDetails({
    required this.report,
    required this.playbackController,
  });
  final ReportDetailDto report;
  final VoiceAnswerPlaybackController? playbackController;

  @override
  Widget build(BuildContext context) {
    final expression = report.childExpression;
    final facts = report.activityFacts;
    final conversation = report.conversationSummary;
    final guide = report.guardianConversationGuide;

    final sections = <Widget>[
      if (expression != null && !expression.isEmpty)
        _ReportSection(
          key: const ValueKey('report-child-expression'),
          title: '아이가 표현한 것',
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
        ),
      if (facts != null && !facts.isEmpty)
        _ReportSection(
          key: const ValueKey('report-activity-facts'),
          title: '활동 기록',
          children: [
            if (facts.detectedObjects.isNotEmpty)
              _InfoLine(label: '그린 것', value: facts.detectedObjects.join(', ')),
            if (facts.pauseCount case final count?)
              _InfoLine(label: '멈춤', value: '$count회'),
            if (facts.eraseCount case final count?)
              _InfoLine(label: '지우기', value: '$count회'),
            for (final note in facts.notes) _Bullet(title: note),
          ],
        ),
      if (conversation != null && !conversation.isEmpty)
        _ReportSection(
          key: const ValueKey('report-conversation-summary'),
          title: '대화 요약',
          children: [
            if (conversation.questionCount case final count?)
              _InfoLine(label: '질문', value: '$count개'),
            if (conversation.answeredCount case final count?)
              _InfoLine(label: '대답', value: '$count개'),
            if (conversation.skippedCount case final count?)
              _InfoLine(label: '건너뜀', value: '$count개'),
            if (conversation.summary case final summary?) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(summary, style: const TextStyle(color: AppColors.ink)),
            ],
          ],
        ),
      if (guide.isNotEmpty)
        _ReportSection(
          key: const ValueKey('report-conversation-guide'),
          title: '이런 질문으로 대화해 보세요',
          children: [for (final question in guide) _Bullet(title: question)],
        ),
    ];

    if (sections.isEmpty) {
      return const _ReportCard(
        key: ValueKey('report-no-observations'),
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
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, section) in sections.indexed) ...[
          if (index > 0) const SizedBox(height: AppSpacing.md),
          section,
        ],
      ],
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.child, super.key});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.lg),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      border: Border.all(color: AppColors.outline),
    ),
    child: child,
  );
}

class _ReportSection extends StatelessWidget {
  const _ReportSection({
    required this.title,
    required this.children,
    super.key,
  });
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => _ReportCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AppColors.lavender,
            fontSize: 18,
            fontWeight: FontWeight.w800,
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
    child: Row(
      children: [
        SizedBox(
          width: 88,
          child: Text(label, style: const TextStyle(color: AppColors.inkMuted)),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: AppColors.ink,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
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

/// 서버가 주는 밀리초 활동 시간을 분 단위 문구로 바꾼다. 값이 없으면 표시하지 않는다.
String? _minutes(int? durationMs) =>
    durationMs == null ? null : '${(durationMs / 60000).round()}분';

String _emotionLabel(String emotion) => switch (emotion) {
  'HAPPY' || 'JOY' => '기쁨',
  'SAD' => '슬픔',
  'ANGRY' => '화남',
  'SCARED' => '무서움',
  'CALM' => '편안함',
  'UNKNOWN' || 'UNSURE' => '잘 모르겠음',
  _ => emotion,
};
