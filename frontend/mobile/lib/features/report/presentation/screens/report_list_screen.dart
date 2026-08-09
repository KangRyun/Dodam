import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../app/router/app_navigation.dart';
import '../../../../app/router/app_routes.dart';
import '../../../../app/state/guardian_child_controller.dart';
import '../../../../app/widgets/app_failure_view.dart';
import '../../../../core/domain/report_status.dart';
import '../../../../design_system/design_system.dart';
import '../../data/dto/report_dtos.dart';
import '../../domain/repositories/report_repository.dart';

enum _ReportListStatus { loading, success, empty, error, noChild }

enum _ReportPeriod { all, recent30Days }

class ReportListScreen extends StatefulWidget {
  const ReportListScreen({
    required this.childController,
    required this.repository,
    super.key,
  });

  final GuardianChildController childController;
  final ReportRepository repository;

  @override
  State<ReportListScreen> createState() => _ReportListScreenState();
}

class _ReportListScreenState extends State<ReportListScreen> {
  _ReportListStatus _status = _ReportListStatus.loading;
  List<ReportSummaryDto> _reports = const [];
  Object? _failure;
  int? _loadedChildId;
  String? _reportStatus;
  String? _drawingTypeCode;
  _ReportPeriod _period = _ReportPeriod.all;
  bool _hasNext = false;
  bool _loadingMore = false;
  int _requestEpoch = 0;
  Map<String, String> _knownTypes = const {};

  @override
  void initState() {
    super.initState();
    widget.childController.addListener(_onChildChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    widget.childController.removeListener(_onChildChanged);
    super.dispose();
  }

  void _onChildChanged() {
    if (_loadedChildId == widget.childController.selectedChildId) return;
    _drawingTypeCode = null;
    _knownTypes = const {};
    unawaited(_load());
  }

  Future<void> _load({bool append = false}) async {
    final requestEpoch = ++_requestEpoch;
    final childId = widget.childController.selectedChildId;
    _loadedChildId = childId;
    if (childId == null) {
      setState(() {
        _reports = const [];
        _status = _ReportListStatus.noChild;
      });
      return;
    }
    if (append) {
      if (!_hasNext || _loadingMore) return;
      setState(() => _loadingMore = true);
    } else {
      setState(() {
        _status = _ReportListStatus.loading;
        _failure = null;
      });
    }
    try {
      final now = DateTime.now();
      final page = append ? (_reports.length / 20).floor() : 0;
      final response = await widget.repository.getReports(
        childId,
        filter: ReportFilterDto(
          from: _period == _ReportPeriod.recent30Days
              ? _dateOnly(now.subtract(const Duration(days: 30)))
              : null,
          to: _period == _ReportPeriod.recent30Days ? _dateOnly(now) : null,
          drawingTypeCode: _drawingTypeCode,
          reportStatus: _reportStatus,
          page: page,
        ),
      );
      if (!mounted ||
          requestEpoch != _requestEpoch ||
          childId != widget.childController.selectedChildId) {
        return;
      }
      final reports = append
          ? [..._reports, ...response.content]
          : response.content;
      final knownTypes = <String, String>{
        ..._knownTypes,
        for (final report in response.content)
          report.drawingTypeCode: report.drawingTypeName,
      };
      setState(() {
        _reports = reports;
        _knownTypes = knownTypes;
        _hasNext = response.hasNext;
        _loadingMore = false;
        _status = reports.isEmpty
            ? _ReportListStatus.empty
            : _ReportListStatus.success;
      });
    } on Object catch (error) {
      if (!mounted || requestEpoch != _requestEpoch) return;
      setState(() {
        _failure = error;
        _loadingMore = false;
        if (!append) _status = _ReportListStatus.error;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.canvas,
    appBar: AppTopBar(
      title: 'AI 관찰 리포트',
      onBack: () => Navigator.of(context).maybePop(),
    ),
    // 넓은 태블릿에서 리스트가 화면 끝까지 늘어나지 않도록 폭을 가둔다(S15P11B209-787).
    body: SafeArea(
      top: false,
      child: ResponsiveContent(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ReportListHeader(
              childName: widget.childController.selectedChild?.nickname,
              period: _period,
              reportStatus: _reportStatus,
              drawingTypeCode: _drawingTypeCode,
              drawingTypes: _knownDrawingTypes,
              onPeriodChanged: (value) {
                setState(() => _period = value);
                _load();
              },
              onStatusChanged: (value) {
                setState(() => _reportStatus = value);
                _load();
              },
              onDrawingTypeChanged: (value) {
                setState(() => _drawingTypeCode = value);
                _load();
              },
            ),
            Expanded(child: _body()),
          ],
        ),
      ),
    ),
  );

  List<(String, String)> get _knownDrawingTypes {
    return _knownTypes.entries
        .map((entry) => (entry.key, entry.value))
        .toList();
  }

  Widget _body() => switch (_status) {
    _ReportListStatus.loading => const AppLoadingView(
      key: ValueKey('report-list-loading'),
      message: '관찰 리포트를 불러오고 있어요',
    ),
    _ReportListStatus.noChild => const AppEmptyView(
      key: ValueKey('report-list-no-child'),
      title: '확인할 아이를 먼저 선택해 주세요',
      message: '보호자 홈에서 아이를 선택하면 관찰 리포트를 볼 수 있어요.',
    ),
    _ReportListStatus.empty => AppEmptyView(
      key: const ValueKey('report-list-empty'),
      title: '아직 관찰 리포트가 없어요',
      message: '그림 활동과 대화를 마치면 AI 분석 후 이곳에 리포트가 표시돼요.',
      actionLabel: '새로고침',
      onAction: _load,
    ),
    _ReportListStatus.error => AppFailureView(
      key: const ValueKey('report-list-error'),
      title: '관찰 리포트를 불러오지 못했어요',
      failure: _failure,
      onRetry: _load,
    ),
    _ReportListStatus.success => RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        key: const ValueKey('report-list'),
        padding: const EdgeInsets.all(AppSpacing.lg),
        itemCount: _reports.length + (_hasNext ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (context, index) {
          if (index == _reports.length) {
            return Center(
              child: AppButton(
                label: _loadingMore ? '불러오는 중' : '더 보기',
                variant: AppButtonVariant.secondary,
                onPressed: _loadingMore ? null : () => _load(append: true),
              ),
            );
          }
          return _ReportCard(report: _reports[index], onRefresh: _load);
        },
      ),
    ),
  };
}

class _ReportListHeader extends StatelessWidget {
  const _ReportListHeader({
    required this.childName,
    required this.period,
    required this.reportStatus,
    required this.drawingTypeCode,
    required this.drawingTypes,
    required this.onPeriodChanged,
    required this.onStatusChanged,
    required this.onDrawingTypeChanged,
  });

  final String? childName;
  final _ReportPeriod period;
  final String? reportStatus, drawingTypeCode;
  final List<(String, String)> drawingTypes;
  final ValueChanged<_ReportPeriod> onPeriodChanged;
  final ValueChanged<String?> onStatusChanged, onDrawingTypeChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.lg,
      AppSpacing.lg,
      AppSpacing.lg,
      0,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          childName == null ? '아이의 관찰 리포트' : '$childName의 관찰 리포트',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: AppColors.ink,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        const Text(
          '그림과 대화에서 확인된 활동 사실을 보호자와 함께 살펴보세요.',
          style: TextStyle(color: AppColors.inkMuted),
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            _ReportFilterDropdown<_ReportPeriod>(
              label: '기간',
              value: period,
              items: const [
                (_ReportPeriod.all, '전체 기간'),
                (_ReportPeriod.recent30Days, '최근 30일'),
              ],
              onChanged: (value) {
                if (value != null) onPeriodChanged(value);
              },
            ),
            _ReportFilterDropdown<String?>(
              label: '상태',
              value: reportStatus,
              items: const [
                (null, '전체 상태'),
                ('COMPLETED', '리포트 완료'),
                ('GENERATING', '분석 중'),
                ('FAILED', '다시 확인 필요'),
              ],
              onChanged: onStatusChanged,
            ),
            if (drawingTypes.isNotEmpty)
              _ReportFilterDropdown<String?>(
                label: '활동 종류',
                value: drawingTypeCode,
                items: [const (null, '전체 활동'), ...drawingTypes],
                onChanged: onDrawingTypeChanged,
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
      ],
    ),
  );
}

class _ReportFilterDropdown<T> extends StatelessWidget {
  const _ReportFilterDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final T? value;
  final List<(T, String)> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 180,
    child: DropdownButtonFormField<T>(
      isExpanded: true,
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
      ),
      items: [
        for (final item in items)
          DropdownMenuItem<T>(value: item.$1, child: Text(item.$2)),
      ],
      onChanged: onChanged,
    ),
  );
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.report, required this.onRefresh});

  final ReportSummaryDto report;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final completed = report.reportStatus == 'COMPLETED';
    return Material(
      key: ValueKey('report-card-${report.reportId}'),
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        onTap: completed
            ? () => AppNavigation.pushNamed(
                context,
                AppRoutes.report(report.reportId.toString()),
              )
            : null,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.outline),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: completed ? AppColors.leafSoft : AppColors.canvas,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(
                  completed
                      ? Icons.description_outlined
                      : Icons.auto_awesome_outlined,
                  color: completed ? AppColors.leaf : AppColors.inkMuted,
                  size: 32,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            report.title ?? report.drawingTypeName,
                            style: const TextStyle(
                              color: AppColors.ink,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        _ReportStatusBadge(status: report.reportStatus),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      [
                        report.drawingTypeName,
                        if (report.activityDate case final date?)
                          '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}',
                      ].join(' · '),
                      style: const TextStyle(color: AppColors.inkMuted),
                    ),
                    if (report.selectedEmotions.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        '아이가 고른 감정: ${report.selectedEmotions.join(', ')}',
                        style: const TextStyle(color: AppColors.ink),
                      ),
                    ],
                    if (!completed) ...[
                      const SizedBox(height: AppSpacing.sm),
                      TextButton.icon(
                        onPressed: onRefresh,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('상태 다시 확인'),
                      ),
                    ],
                  ],
                ),
              ),
              if (completed) const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReportStatusBadge extends StatelessWidget {
  const _ReportStatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, background, foreground) = switch (status) {
      'COMPLETED' => ('리포트 완료', AppColors.leafSoft, AppColors.leaf),
      final value when isReportFailureVisibleToGuardian(value) => (
        '다시 확인 필요',
        AppColors.errorSoft,
        AppColors.error,
      ),
      // FAILED_RETRYABLE 을 포함해 나머지는 분석 중으로 둔다.
      _ => ('분석 중', AppColors.tangerineSoft, AppColors.tangerine),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: 13,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

String _dateOnly(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';
