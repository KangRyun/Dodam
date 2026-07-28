import 'package:flutter/material.dart';

import '../../../../app/router/app_routes.dart';
import '../../../../app/state/guardian_child_controller.dart';
import '../../../../app/widgets/app_failure_view.dart';
import '../../../../design_system/design_system.dart';
import '../../../activity/data/dto/activity_dtos.dart';
import '../../../activity/domain/repositories/activity_repository.dart';
import '../../../child/data/dto/child_dtos.dart';

enum _HistoryStatus { loading, success, empty, error, noChild }

enum _PeriodFilter { all, recent30Days }

class ActivityHistoryScreen extends StatefulWidget {
  const ActivityHistoryScreen({
    required this.childController,
    required this.repository,
    super.key,
  });

  final GuardianChildController childController;
  final ActivityRepository repository;

  @override
  State<ActivityHistoryScreen> createState() => _ActivityHistoryScreenState();
}

class _ActivityHistoryScreenState extends State<ActivityHistoryScreen> {
  _HistoryStatus _status = _HistoryStatus.loading;
  Object? _failure;
  List<ActivitySummaryDto> _activities = const [];
  List<ActivityDrawingTypeDto> _knownTypes = const [];
  int? _selectedActivityId;
  String? _drawingType;
  _PeriodFilter _period = _PeriodFilter.all;

  ActivitySummaryDto? get _selectedActivity {
    for (final activity in _activities) {
      if (activity.activityId == _selectedActivityId) return activity;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final childId = widget.childController.selectedChildId;
    if (childId == null) {
      setState(() {
        _status = _HistoryStatus.noChild;
        _activities = const [];
        _selectedActivityId = null;
      });
      return;
    }
    setState(() {
      _status = _HistoryStatus.loading;
      _failure = null;
    });
    try {
      final now = DateTime.now().toUtc();
      final response = await widget.repository.getActivities(
        childId,
        filter: ActivityFilterDto(
          from: _period == _PeriodFilter.recent30Days
              ? now.subtract(const Duration(days: 30)).toIso8601String()
              : null,
          to: _period == _PeriodFilter.recent30Days
              ? now.toIso8601String()
              : null,
          drawingType: _drawingType,
        ),
      );
      if (!mounted) return;
      final activities = response.content;
      final knownTypes = <String, ActivityDrawingTypeDto>{
        for (final type in _knownTypes) type.code: type,
        for (final activity in activities)
          activity.drawingType.code: activity.drawingType,
      }.values.toList(growable: false);
      final selectedStillExists = activities.any(
        (activity) => activity.activityId == _selectedActivityId,
      );
      setState(() {
        _activities = activities;
        _knownTypes = knownTypes;
        _selectedActivityId = selectedStillExists
            ? _selectedActivityId
            : activities.firstOrNull?.activityId;
        _status = activities.isEmpty
            ? _HistoryStatus.empty
            : _HistoryStatus.success;
      });
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _failure = error;
          _status = _HistoryStatus.error;
        });
      }
    }
  }

  Future<void> _selectChild(int childId) async {
    final child = widget.childController.children
        .where((item) => item.childId == childId)
        .firstOrNull;
    if (child == null) return;
    widget.childController.selectChild(child);
    _drawingType = null;
    _selectedActivityId = null;
    await _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.canvas,
    appBar: AppTopBar(
      title: '활동 이력',
      onBack: () => Navigator.of(context).maybePop(),
    ),
    body: SafeArea(
      top: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final body = _buildBody();
          if (constraints.maxWidth < 900) {
            return Column(
              children: [
                _HistoryNavigation(compact: true),
                Expanded(child: body),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(width: 220, child: _HistoryNavigation()),
              const VerticalDivider(width: 1),
              Expanded(child: body),
            ],
          );
        },
      ),
    ),
  );

  Widget _buildBody() => switch (_status) {
    _HistoryStatus.loading => const AppLoadingView(
      key: ValueKey('activity-history-loading'),
      message: '활동 기록을 불러오고 있어요',
    ),
    _HistoryStatus.noChild => const AppEmptyView(
      key: ValueKey('activity-history-no-child'),
      title: '확인할 아이를 먼저 선택해 주세요',
      message: '보호자 홈에서 아이를 선택하면 활동 이력을 볼 수 있어요.',
    ),
    _HistoryStatus.empty => _HistoryContent(
      filter: _buildFilter(),
      content: const AppEmptyView(
        key: ValueKey('activity-history-empty'),
        title: '아직 활동 기록이 없어요',
        message: '그림 활동을 마치면 이곳에서 기록을 확인할 수 있어요.',
      ),
    ),
    _HistoryStatus.error => _HistoryContent(
      filter: _buildFilter(),
      content: AppFailureView(
        key: const ValueKey('activity-history-error'),
        title: '활동 기록을 불러오지 못했어요',
        failure: _failure,
        onRetry: _load,
      ),
    ),
    _HistoryStatus.success => _HistoryContent(
      filter: _buildFilter(),
      content: LayoutBuilder(
        builder: (context, constraints) {
          Widget list({bool embedded = false}) => _ActivityList(
            activities: _activities,
            selectedActivityId: _selectedActivityId,
            embedded: embedded,
            onSelected: (activityId) =>
                setState(() => _selectedActivityId = activityId),
          );
          final summary = _ActivitySummary(activity: _selectedActivity);
          if (constraints.maxWidth < 760) {
            return ListView(
              key: const ValueKey('activity-history-small-layout'),
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                list(embedded: true),
                const SizedBox(height: AppSpacing.lg),
                summary,
              ],
            );
          }
          return Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 5, child: list()),
                const SizedBox(width: AppSpacing.lg),
                Expanded(flex: 4, child: summary),
              ],
            ),
          );
        },
      ),
    ),
  };

  Widget _buildFilter() => _ActivityFilters(
    children: widget.childController.children,
    selectedChildId: widget.childController.selectedChildId,
    period: _period,
    drawingType: _drawingType,
    drawingTypes: _knownTypes,
    onChildChanged: _selectChild,
    onPeriodChanged: (value) {
      setState(() => _period = value);
      _load();
    },
    onDrawingTypeChanged: (value) {
      setState(() => _drawingType = value);
      _load();
    },
  );
}

class _HistoryContent extends StatelessWidget {
  const _HistoryContent({required this.filter, required this.content});
  final Widget filter, content;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
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
              '아이의 지난 활동을 살펴보세요',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: AppColors.ink,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            const Text(
              '그림 활동을 선택하면 간단한 내용을 미리 확인할 수 있어요.',
              style: TextStyle(color: AppColors.inkMuted),
            ),
            const SizedBox(height: AppSpacing.md),
            filter,
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.sm),
      Expanded(child: content),
    ],
  );
}

class _HistoryNavigation extends StatelessWidget {
  const _HistoryNavigation({this.compact = false});
  final bool compact;
  @override
  Widget build(BuildContext context) => Container(
    color: AppColors.surface,
    padding: const EdgeInsets.all(AppSpacing.md),
    child: compact
        ? Row(
            children: [
              Expanded(
                child: _NavButton(
                  icon: Icons.home_outlined,
                  label: '보호자 홈',
                  onTap: () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              const Expanded(
                child: _NavButton(
                  icon: Icons.history_rounded,
                  label: '활동 이력',
                  selected: true,
                ),
              ),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '도담',
                style: TextStyle(
                  color: AppColors.ink,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              _NavButton(
                icon: Icons.home_outlined,
                label: '보호자 홈',
                onTap: () => Navigator.of(context).pop(),
              ),
              const SizedBox(height: AppSpacing.sm),
              const _NavButton(
                icon: Icons.history_rounded,
                label: '활동 이력',
                selected: true,
              ),
            ],
          ),
  );
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.icon,
    required this.label,
    this.selected = false,
    this.onTap,
  });
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: selected ? AppColors.leafSoft : Colors.transparent,
    borderRadius: BorderRadius.circular(AppRadius.md),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Row(
          children: [
            Icon(icon, color: selected ? AppColors.leaf : AppColors.inkMuted),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: selected ? AppColors.leaf : AppColors.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ActivityFilters extends StatelessWidget {
  const _ActivityFilters({
    required this.children,
    required this.selectedChildId,
    required this.period,
    required this.drawingType,
    required this.drawingTypes,
    required this.onChildChanged,
    required this.onPeriodChanged,
    required this.onDrawingTypeChanged,
  });
  final List<ChildSummaryDto> children;
  final int? selectedChildId;
  final _PeriodFilter period;
  final String? drawingType;
  final List<ActivityDrawingTypeDto> drawingTypes;
  final ValueChanged<int> onChildChanged;
  final ValueChanged<_PeriodFilter> onPeriodChanged;
  final ValueChanged<String?> onDrawingTypeChanged;

  @override
  Widget build(BuildContext context) => Wrap(
    key: const ValueKey('activity-history-filters'),
    spacing: AppSpacing.sm,
    runSpacing: AppSpacing.sm,
    children: [
      _FilterDropdown<int>(
        key: const ValueKey('activity-child-filter'),
        label: '아동',
        value: selectedChildId,
        items: [for (final child in children) (child.childId, child.nickname)],
        onChanged: (value) {
          if (value != null) onChildChanged(value);
        },
      ),
      _FilterDropdown<_PeriodFilter>(
        key: const ValueKey('activity-period-filter'),
        label: '기간',
        value: period,
        items: const [
          (_PeriodFilter.all, '전체 기간'),
          (_PeriodFilter.recent30Days, '최근 30일'),
        ],
        onChanged: (value) {
          if (value != null) onPeriodChanged(value);
        },
      ),
      _FilterDropdown<String?>(
        key: const ValueKey('activity-type-filter'),
        label: '활동 종류',
        value: drawingType,
        items: [
          const (null, '전체 활동'),
          for (final type in drawingTypes) (type.code, type.name),
        ],
        onChanged: onDrawingTypeChanged,
      ),
    ],
  );
}

class _FilterDropdown<T> extends StatelessWidget {
  const _FilterDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    super.key,
  });
  final String label;
  final T? value;
  final List<(T, String)> items;
  final ValueChanged<T?> onChanged;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 190,
    child: DropdownButtonFormField<T>(
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

class _ActivityList extends StatelessWidget {
  const _ActivityList({
    required this.activities,
    required this.selectedActivityId,
    required this.onSelected,
    this.embedded = false,
  });
  final List<ActivitySummaryDto> activities;
  final int? selectedActivityId;
  final ValueChanged<int> onSelected;
  final bool embedded;
  @override
  Widget build(BuildContext context) => ListView.separated(
    key: const ValueKey('activity-history-list'),
    shrinkWrap: embedded,
    physics: embedded ? const NeverScrollableScrollPhysics() : null,
    itemCount: activities.length,
    separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
    itemBuilder: (context, index) {
      final activity = activities[index];
      return AppChoiceCard(
        key: ValueKey('activity-${activity.activityId}'),
        label: activity.title ?? activity.drawingType.name,
        description:
            '${_date(activity.completedAt ?? activity.startedAt)} · ${activity.drawingType.name}',
        isSelected: activity.activityId == selectedActivityId,
        onTap: () => onSelected(activity.activityId),
        leading: _Thumbnail(url: activity.thumbnailUrl, size: 72),
      );
    },
  );
}

class _ActivitySummary extends StatelessWidget {
  const _ActivitySummary({required this.activity});
  final ActivitySummaryDto? activity;
  @override
  Widget build(BuildContext context) {
    final activity = this.activity;
    if (activity == null) {
      return const AppEmptyView(title: '활동을 선택해 주세요');
    }
    return Container(
      key: const ValueKey('activity-history-summary'),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.outline),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 16 / 10,
              child: _Thumbnail(url: activity.thumbnailUrl),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              activity.title ?? activity.drawingType.name,
              style: const TextStyle(
                color: AppColors.ink,
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            _SummaryLine(
              label: '활동 날짜',
              value: _date(activity.completedAt ?? activity.startedAt),
            ),
            _SummaryLine(label: '활동 종류', value: activity.drawingType.name),
            _SummaryLine(label: '진행 상태', value: activity.sessionStatus),
            if (activity.selectedEmotions.isNotEmpty)
              _SummaryLine(
                label: '선택한 감정',
                value: activity.selectedEmotions.join(', '),
              ),
            const SizedBox(height: AppSpacing.lg),
            AppButton(
              key: const ValueKey('activity-detail-cta'),
              label: '자세히 보기',
              onPressed: () => Navigator.of(context).pushNamed(
                AppRoutes.activityDetail(activity.activityId.toString()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
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

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.url, this.size});
  final String? url;
  final double? size;
  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      key: const ValueKey('activity-thumbnail-placeholder'),
      color: AppColors.surfaceSoft,
      alignment: Alignment.center,
      child: const Icon(Icons.image_outlined, color: AppColors.inkMuted),
    );
    final image = url == null
        ? placeholder
        : Image.network(
            url!,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => placeholder,
          );
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: size == null
          ? image
          : SizedBox(width: size, height: size, child: image),
    );
  }
}

String _date(String isoDate) => isoDate.length >= 10
    ? isoDate.substring(0, 10).replaceAll('-', '.')
    : isoDate;

enum _DetailStatus { loading, success, empty, error, invalidId }

class ActivityDetailScreen extends StatefulWidget {
  const ActivityDetailScreen({
    required this.activityId,
    required this.repository,
    super.key,
  });

  final String activityId;
  final ActivityRepository repository;

  @override
  State<ActivityDetailScreen> createState() => _ActivityDetailScreenState();
}

class _ActivityDetailScreenState extends State<ActivityDetailScreen> {
  _DetailStatus _status = _DetailStatus.loading;
  ActivityDetailDto? _activity;
  Object? _failure;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final activityId = int.tryParse(widget.activityId);
    if (activityId == null || activityId <= 0) {
      setState(() => _status = _DetailStatus.invalidId);
      return;
    }
    setState(() {
      _status = _DetailStatus.loading;
      _failure = null;
    });
    try {
      final activity = await widget.repository.getActivity(activityId);
      if (!mounted) return;
      setState(() {
        _activity = activity.activityId == activityId ? activity : null;
        _status = _activity == null
            ? _DetailStatus.empty
            : _DetailStatus.success;
      });
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _failure = error;
          _status = _DetailStatus.error;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.canvas,
    appBar: AppTopBar(
      title: '활동 상세',
      onBack: () => Navigator.of(context).maybePop(),
    ),
    body: SafeArea(top: false, child: _body()),
  );

  Widget _body() => switch (_status) {
    _DetailStatus.loading => const AppLoadingView(
      key: ValueKey('activity-detail-loading'),
      message: '활동 상세를 불러오고 있어요',
    ),
    _DetailStatus.error => AppFailureView(
      key: const ValueKey('activity-detail-error'),
      title: '활동 상세를 불러오지 못했어요',
      failure: _failure,
      onRetry: _load,
    ),
    _DetailStatus.invalidId => const AppErrorView(
      key: ValueKey('activity-detail-invalid-id'),
      title: '활동 정보가 올바르지 않아요',
      message: '활동 이력에서 다시 선택해 주세요.',
    ),
    _DetailStatus.empty => const AppEmptyView(
      key: ValueKey('activity-detail-empty'),
      title: '활동 상세 정보가 없어요',
      message: '이력 목록으로 돌아가 다른 활동을 선택해 주세요.',
    ),
    _DetailStatus.success => _ActivityDetailContent(activity: _activity!),
  };
}

class _ActivityDetailContent extends StatelessWidget {
  const _ActivityDetailContent({required this.activity});
  final ActivityDetailDto activity;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final left = _ActivityArtwork(activity: activity);
      final right = _ActivityInformation(activity: activity);
      return SingleChildScrollView(
        key: ValueKey(
          constraints.maxWidth >= 900
              ? 'activity-detail-wide-layout'
              : 'activity-detail-small-layout',
        ),
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: constraints.maxWidth >= 900
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 5, child: left),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(flex: 6, child: right),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  left,
                  const SizedBox(height: AppSpacing.lg),
                  right,
                ],
              ),
      );
    },
  );
}

class _ActivityArtwork extends StatelessWidget {
  const _ActivityArtwork({required this.activity});
  final ActivityDetailDto activity;

  ActivityAssetDto? get _asset {
    for (final asset in activity.assets.reversed) {
      if (asset.assetType == 'FINAL') return asset;
    }
    return activity.assets.lastOrNull;
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _DetailCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              activity.title ?? activity.drawingType.name,
              style: const TextStyle(
                color: AppColors.ink,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${_date(activity.completedAt ?? activity.startedAt)} · ${activity.drawingType.name}',
              style: const TextStyle(color: AppColors.inkMuted),
            ),
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.md),
      AspectRatio(
        aspectRatio: 16 / 10,
        child: Container(
          key: const ValueKey('activity-detail-image'),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.outline),
          ),
          clipBehavior: Clip.antiAlias,
          child: _asset == null
              ? const _DetailImagePlaceholder()
              : Image.network(
                  _asset!.fileUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const _DetailImagePlaceholder(),
                ),
        ),
      ),
    ],
  );
}

class _ActivityInformation extends StatelessWidget {
  const _ActivityInformation({required this.activity});
  final ActivityDetailDto activity;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _DetailSection(
        title: '활동 정보',
        key: const ValueKey('activity-detail-basic-info'),
        children: [
          _DetailLine(label: '활동 유형', value: activity.drawingType.name),
          _DetailLine(label: '입력 방식', value: activity.inputMethod),
          _DetailLine(label: '진행 상태', value: activity.sessionStatus),
          _DetailLine(label: '현재 단계', value: activity.currentStage),
          _DetailLine(label: '시작', value: _dateTime(activity.startedAt)),
          if (activity.completedAt case final completedAt?)
            _DetailLine(label: '완료', value: _dateTime(completedAt)),
        ],
      ),
      const SizedBox(height: AppSpacing.md),
      _DetailSection(
        title: '아동이 선택한 감정',
        key: const ValueKey('activity-detail-emotions'),
        children: [
          if (activity.selectedEmotions.isEmpty)
            const Text(
              '선택한 감정 정보가 없어요.',
              style: TextStyle(color: AppColors.inkMuted),
            )
          else
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final emotion in activity.selectedEmotions)
                  Chip(label: Text(_emotionLabel(emotion))),
              ],
            ),
          if (activity.expressedEmotionText case final text?) ...[
            const SizedBox(height: AppSpacing.md),
            Text('“$text”', style: const TextStyle(color: AppColors.ink)),
          ],
        ],
      ),
      const SizedBox(height: AppSpacing.md),
      _DetailSection(
        title: '대화 정보',
        key: const ValueKey('activity-detail-conversation'),
        children: [
          if (activity.conversation case final conversation?) ...[
            _DetailLine(label: '대화 상태', value: conversation.conversationStatus),
            _DetailLine(label: '질문 수', value: '${conversation.questionCount}개'),
            if (conversation.completedAt case final completedAt?)
              _DetailLine(label: '대화 완료', value: _dateTime(completedAt)),
          ] else
            const Text(
              '이 활동에서 제공된 대화 정보가 없어요.',
              style: TextStyle(color: AppColors.inkMuted),
            ),
        ],
      ),
      const SizedBox(height: AppSpacing.md),
      _DetailSection(
        title: '분석과 관찰 요약',
        key: const ValueKey('activity-detail-analysis'),
        children: [
          if (activity.analysis case final analysis?)
            _DetailLine(label: '분석 상태', value: analysis.analysisStatus)
          else
            const Text(
              '아직 생성된 요약이 없어요.',
              style: TextStyle(color: AppColors.inkMuted),
            ),
        ],
      ),
      if (activity.report case final report?) ...[
        const SizedBox(height: AppSpacing.md),
        AppButton(
          key: const ValueKey('activity-report-cta'),
          label: '관찰 리포트 보기',
          onPressed: () => Navigator.of(
            context,
          ).pushNamed(AppRoutes.report(report.reportId.toString())),
        ),
      ],
    ],
  );
}

class _DetailCard extends StatelessWidget {
  const _DetailCard({required this.child});
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

class _DetailSection extends StatelessWidget {
  const _DetailSection({
    required this.title,
    required this.children,
    super.key,
  });
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => _DetailCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AppColors.leaf,
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

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 96,
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

class _DetailImagePlaceholder extends StatelessWidget {
  const _DetailImagePlaceholder();
  @override
  Widget build(BuildContext context) => const ColoredBox(
    key: ValueKey('activity-detail-image-placeholder'),
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

String _dateTime(String isoDate) {
  final parsed = DateTime.tryParse(isoDate)?.toLocal();
  if (parsed == null) return isoDate;
  String two(int value) => value.toString().padLeft(2, '0');
  return '${parsed.year}.${two(parsed.month)}.${two(parsed.day)} '
      '${two(parsed.hour)}:${two(parsed.minute)}';
}

String _emotionLabel(String emotion) => switch (emotion) {
  'HAPPY' || 'JOY' => '기쁨',
  'SAD' => '슬픔',
  'ANGRY' => '화남',
  'SCARED' => '무서움',
  'CALM' => '편안함',
  'UNKNOWN' || 'UNSURE' => '잘 모르겠음',
  _ => emotion,
};
