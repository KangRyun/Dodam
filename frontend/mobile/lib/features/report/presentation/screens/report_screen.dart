import 'package:flutter/material.dart';

import '../../../../app/router/app_router.dart';
import '../../../../app/widgets/app_failure_view.dart';
import '../../../../core/network/network.dart';
import '../../../../design_system/design_system.dart';
import '../../data/dto/report_dtos.dart';
import '../../domain/repositories/report_repository.dart';

enum _ReportViewStatus {
  loading,
  completed,
  generating,
  failed,
  empty,
  error,
  invalidId,
}

class ReportScreen extends StatefulWidget {
  const ReportScreen({
    required this.reportId,
    required this.repository,
    super.key,
  });

  final String reportId;
  final ReportRepository repository;

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  _ReportViewStatus _status = _ReportViewStatus.loading;
  ReportDetailDto? _report;
  Object? _failure;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
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
    _ReportViewStatus.completed => _ReportContent(report: _report!),
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
  const _ReportContent({required this.report});
  final ReportDetailDto report;

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
                    Expanded(flex: 6, child: _ReportDetails(report: report)),
                  ],
                )
              else ...[
                _ReportOverview(report: report),
                const SizedBox(height: AppSpacing.lg),
                _ReportDetails(report: report),
              ],
              const SizedBox(height: AppSpacing.lg),
              _NoticeCard(text: report.limitationsText),
              const SizedBox(height: AppSpacing.lg),
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

class _ReportOverview extends StatelessWidget {
  const _ReportOverview({required this.report});
  final ReportDetailDto report;

  @override
  Widget build(BuildContext context) {
    final summary = report.activitySummary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ReportCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                summary?.title ?? '그림 활동 관찰 기록',
                style: const TextStyle(
                  color: AppColors.ink,
                  fontSize: 23,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '${_date(report.createdAt)} · 리포트 v${report.reportVersion}',
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
            child: report.drawingImageUrl == null
                ? const _ImagePlaceholder()
                : Image.network(
                    report.drawingImageUrl!,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const _ImagePlaceholder(),
                  ),
          ),
        ),
        if (summary != null) ...[
          const SizedBox(height: AppSpacing.md),
          _ReportSection(
            title: '활동 정보',
            children: [
              _InfoLine(
                label: '활동 유형',
                value:
                    summary.drawingType['name']?.toString() ??
                    summary.drawingType['code']?.toString() ??
                    '-',
              ),
              _InfoLine(label: '입력 방식', value: summary.inputMethod),
              _InfoLine(label: '활동 시간', value: '${summary.durationMinutes}분'),
              _InfoLine(label: '완료일', value: _date(summary.completedAt)),
              if (summary.selectedEmotions.isNotEmpty) ...[
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
                    for (final emotion in summary.selectedEmotions)
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
  const _ReportDetails({required this.report});
  final ReportDetailDto report;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (report.observedFeatures case final features? when features.isNotEmpty)
        _ReportSection(
          key: const ValueKey('report-observed-features'),
          title: '이런 모습이 보였어요',
          children: [
            for (final feature in features)
              _Bullet(title: feature.label, description: feature.description),
          ],
        ),
      if (report.keyConversations case final conversations?
          when conversations.isNotEmpty) ...[
        if (report.observedFeatures?.isNotEmpty == true)
          const SizedBox(height: AppSpacing.md),
        _ReportSection(
          key: const ValueKey('report-conversations'),
          title: '주요 대화',
          children: [
            for (final item in conversations) _Conversation(item: item),
          ],
        ),
      ],
      if (report.followUp != null ||
          report.guardianQuestions?.isNotEmpty == true) ...[
        const SizedBox(height: AppSpacing.md),
        _ReportSection(
          key: const ValueKey('report-follow-up'),
          title: '함께 확인해볼 점',
          children: [
            if (report.followUp case final followUp?) ...[
              for (final point in followUp.attentionPoints)
                _Bullet(title: point),
              if (followUp.guidance.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(
                    followUp.guidance,
                    style: const TextStyle(color: AppColors.ink),
                  ),
                ),
            ],
            if (report.guardianQuestions case final questions?
                when questions.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              const Text(
                '이런 질문으로 대화해 보세요',
                style: TextStyle(
                  color: AppColors.inkMuted,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              for (final question in questions) _Bullet(title: question),
            ],
          ],
        ),
      ],
      if (report.observedFeatures?.isNotEmpty != true &&
          report.keyConversations?.isNotEmpty != true &&
          report.followUp == null &&
          report.guardianQuestions?.isNotEmpty != true)
        const _ReportCard(
          child: Text(
            '아직 표시할 관찰 기록이 없어요.',
            style: TextStyle(color: AppColors.inkMuted),
          ),
        ),
    ],
  );
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.child});
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
  const _Bullet({required this.title, this.description});
  final String title;
  final String? description;
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (description case final description?) ...[
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  description,
                  style: const TextStyle(color: AppColors.inkMuted),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

class _Conversation extends StatelessWidget {
  const _Conversation({required this.item});
  final KeyConversationDto item;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Q. ${item.question}',
          style: const TextStyle(
            color: AppColors.inkMuted,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text('A. ${item.answer}', style: const TextStyle(color: AppColors.ink)),
        if (item.answerType == 'VOICE') ...[
          const SizedBox(height: AppSpacing.xxs),
          const Text(
            '음성으로 답했어요 · 재생 파일 미제공',
            style: TextStyle(color: AppColors.inkMuted, fontSize: 12),
          ),
        ],
      ],
    ),
  );
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({required this.text});
  final String text;
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
          child: Text(
            text,
            style: const TextStyle(color: AppColors.inkMuted, height: 1.45),
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
