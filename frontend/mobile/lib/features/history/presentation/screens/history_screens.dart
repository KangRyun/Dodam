import 'package:flutter/material.dart';

import '../../../../app/router/app_routes.dart';
import '../../../../app/state/guardian_child_controller.dart';
import '../../../../app/widgets/app_placeholder_scaffold.dart';
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
    setState(() => _status = _HistoryStatus.loading);
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
    } on Object {
      if (mounted) setState(() => _status = _HistoryStatus.error);
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
      content: AppRetryView(
        key: const ValueKey('activity-history-error'),
        title: '활동 기록을 불러오지 못했어요',
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

class ActivityDetailScreen extends StatelessWidget {
  const ActivityDetailScreen({required this.activityId, super.key});

  final String activityId;

  @override
  Widget build(BuildContext context) => const AppPlaceholderScaffold(
    title: '활동 상세',
    description: '선택한 활동의 그림, 감정과 진행 정보를 확인하는 화면이에요.',
  );
}
