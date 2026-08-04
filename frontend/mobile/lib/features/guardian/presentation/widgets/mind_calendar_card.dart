import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../activity/data/dto/activity_dtos.dart';
import '../../../activity/domain/repositories/activity_repository.dart';
import 'guardian_home_theme.dart';
import 'mind_emotion.dart';

/// 활동 이력에서 "그 달 각 날짜의 감정"을 계산한다.
///
/// 규칙(제품 결정): 하루에 활동이 여러 개면 그날 마지막 활동(startedAt 최신)의
/// 감정을 쓰고, 한 활동의 감정은 첫 값만 본다. 표시 대상이 아닌 감정은 "기록 없음".
Map<int, MindEmotion> reduceDailyEmotions(
  List<ActivitySummaryDto> activities,
  int year,
  int month,
) {
  final latestByDay = <int, DateTime>{};
  final emotionByDay = <int, MindEmotion>{};
  for (final activity in activities) {
    final started = DateTime.tryParse(activity.startedAt)?.toLocal();
    if (started == null || started.year != year || started.month != month) {
      continue;
    }
    final day = started.day;
    final previous = latestByDay[day];
    if (previous != null && !started.isAfter(previous)) continue;
    latestByDay[day] = started;

    final emotion = activity.selectedEmotions.isEmpty
        ? null
        : MindEmotion.fromApi(activity.selectedEmotions.first);
    if (emotion != null) {
      emotionByDay[day] = emotion;
    } else {
      emotionByDay.remove(day);
    }
  }
  return emotionByDay;
}

class _MonthData {
  const _MonthData(this.emotions, this.activityCount, this.top, this.reports);
  final Map<int, MindEmotion> emotions;
  final int activityCount;
  final MindEmotion? top;
  final int reports;
}

/// 마음 달력 카드(시안 1:1). 상단 연·월(선택) + "이번 달 마음 달력" + 활동 합산,
/// 인사이트 문구, 요일, 도담이 표정 그리드, 범례.
class MindCalendarCard extends StatefulWidget {
  const MindCalendarCard({
    required this.childId,
    required this.repository,
    this.childName,
    this.initialMonth,
    super.key,
  });

  final int childId;
  final ActivityRepository repository;
  final String? childName;
  final DateTime? initialMonth;

  @override
  State<MindCalendarCard> createState() => _MindCalendarCardState();
}

class _MindCalendarCardState extends State<MindCalendarCard> {
  late int _year;
  late int _month;
  late Future<_MonthData> _future;

  @override
  void initState() {
    super.initState();
    final base = widget.initialMonth ?? DateTime.now();
    _year = base.year;
    _month = base.month;
    _future = _load();
  }

  Future<_MonthData> _load() async {
    final lastDay = DateTime(_year, _month + 1, 0).day;
    final page = await widget.repository.getActivities(
      widget.childId,
      filter: ActivityFilterDto(
        from: _dateString(_year, _month, 1),
        to: _dateString(_year, _month, lastDay),
        size: 100,
      ),
    );
    final emotions = reduceDailyEmotions(page.content, _year, _month);
    var count = 0;
    var reports = 0;
    final freq = <MindEmotion, int>{};
    for (final a in page.content) {
      final started = DateTime.tryParse(a.startedAt)?.toLocal();
      if (started == null || started.year != _year || started.month != _month) {
        continue;
      }
      count++;
      final e = a.selectedEmotions.isEmpty
          ? null
          : MindEmotion.fromApi(a.selectedEmotions.first);
      if (e != null) freq[e] = (freq[e] ?? 0) + 1;
      if (a.report?.reportStatus == 'COMPLETED') reports++;
    }
    MindEmotion? top;
    var best = 0;
    freq.forEach((k, v) {
      if (v > best) {
        best = v;
        top = k;
      }
    });
    return _MonthData(emotions, count, top, reports);
  }

  void _setMonth(int year, int month) {
    setState(() {
      _year = year;
      _month = month;
      _future = _load();
    });
  }

  Future<void> _openPicker() async {
    final picked = await showDialog<DateTime>(
      context: context,
      builder: (_) => _MonthPickerDialog(year: _year, month: _month),
    );
    if (picked != null) _setMonth(picked.year, picked.month);
  }

  static String _dateString(int y, int m, int d) =>
      '${y.toString().padLeft(4, '0')}-'
      '${m.toString().padLeft(2, '0')}-'
      '${d.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: DodamHome.surface,
        border: Border.all(color: DodamHome.line),
        borderRadius: BorderRadius.circular(22),
        boxShadow: DodamHome.cardShadow,
      ),
      child: FutureBuilder<_MonthData>(
        future: _future,
        builder: (context, snapshot) {
          final data = snapshot.data;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _CalHead(
                year: _year,
                month: _month,
                activityCount: data?.activityCount ?? 0,
                onPick: _openPicker,
              ),
              const SizedBox(height: 12),
              _Insight(
                childName: widget.childName,
                top: data?.top,
                reports: data?.reports ?? 0,
              ),
              const SizedBox(height: 12),
              const _WeekdayRow(),
              const SizedBox(height: 8),
              Expanded(
                child: _MonthGrid(
                  year: _year,
                  month: _month,
                  emotions: data?.emotions ?? const {},
                ),
              ),
              const SizedBox(height: 12),
              const _Legend(),
            ],
          );
        },
      ),
    );
  }
}

class _CalHead extends StatelessWidget {
  const _CalHead({
    required this.year,
    required this.month,
    required this.activityCount,
    required this.onPick,
  });
  final int year;
  final int month;
  final int activityCount;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 34,
    // 폭에 따라 유연하게 배치한다(옛 Stack은 좁아지면 겹쳤다). 연·월은 최후에
    // 줄임표로 줄고, 장식용 가운데 제목은 폭이 빠듯하면 숨겨 연·월·활동수를 지킨다.
    child: LayoutBuilder(
      builder: (context, c) {
        final showTitle = c.maxWidth >= 300;
        return Row(
          children: [
            // 좌: 연·월(선택). 폭이 모자라면 제목·여백이 먼저 양보하고,
            // 그래도 부족하면 연·월 텍스트가 줄임표로 줄어든다.
            Flexible(
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: onPick,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          '$year년 $month월',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            color: DodamHome.ink,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: DodamHome.inkFaint,
                            width: 1.6,
                          ),
                        ),
                        child: const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 15,
                          color: DodamHome.inkSoft,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // 중: 제목 — 남는 공간을 차지하며 좁으면 줄임표. 아주 좁으면 숨긴다.
            if (showTitle)
              const Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    '이번 달 마음 달력',
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: DodamHome.inkSoft,
                    ),
                  ),
                ),
              )
            else
              const Spacer(),
            const SizedBox(width: 8),
            // 우: 활동 합산
            Text.rich(
              TextSpan(
                text: '활동 ',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: DodamHome.inkSoft,
                ),
                children: [
                  TextSpan(
                    text: '$activityCount',
                    style: const TextStyle(color: DodamHome.pointDeep),
                  ),
                  const TextSpan(text: '회'),
                ],
              ),
            ),
          ],
        );
      },
    ),
  );
}

class _Insight extends StatelessWidget {
  const _Insight({
    required this.childName,
    required this.top,
    required this.reports,
  });
  final String? childName;
  final MindEmotion? top;
  final int reports;

  @override
  Widget build(BuildContext context) {
    final name = childName == null ? '아이' : '$childName는';
    final text = top == null
        ? '이번 달은 아직 기록이 없어요.'
        : '이번 달 $name ${top!.label} 감정이 가장 많았어요 · 리포트 $reports건';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: DodamHome.warm2,
        border: Border.all(color: DodamHome.heroBorder),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Text('🌤️', style: TextStyle(fontSize: 16)),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: DodamHome.navOn,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WeekdayRow extends StatelessWidget {
  const _WeekdayRow();
  static const _labels = ['일', '월', '화', '수', '목', '금', '토'];

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (final label in _labels)
        Expanded(
          child: Center(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: DodamHome.inkFaint,
              ),
            ),
          ),
        ),
    ],
  );
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.year,
    required this.month,
    required this.emotions,
  });
  final int year;
  final int month;
  final Map<int, MindEmotion> emotions;

  @override
  Widget build(BuildContext context) {
    final leadingBlanks = DateTime(year, month, 1).weekday % 7;
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final rows = ((leadingBlanks + daysInMonth) / 7).ceil();
    final now = DateTime.now();
    // 폭(7칸)과 높이(rows줄)에 모두 맞는 원 지름을 계산해 절대 잘리지 않게 한다.
    return LayoutBuilder(
      builder: (context, c) {
        final colW = c.maxWidth / 7;
        final rowH = c.maxHeight / rows;
        // 셀 = 날짜숫자(~13) + 여백 + 원. 남는 공간에 맞춰 원 지름 상한 42.
        final diameter = math
            .min(colW - 6, rowH - 20)
            .clamp(12.0, 42.0)
            .toDouble();
        return Column(
          children: [
            for (var r = 0; r < rows; r++)
              SizedBox(
                height: rowH,
                child: Row(
                  children: [
                    for (var col = 0; col < 7; col++)
                      Expanded(
                        child: Builder(
                          builder: (context) {
                            final day = r * 7 + col - leadingBlanks + 1;
                            if (day < 1 || day > daysInMonth) {
                              return const SizedBox.shrink();
                            }
                            return _DayCell(
                              day: day,
                              emotion: emotions[day],
                              diameter: diameter,
                              isToday: year == now.year &&
                                  month == now.month &&
                                  day == now.day,
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.emotion,
    required this.diameter,
    required this.isToday,
  });
  final int day;
  final MindEmotion? emotion;
  final double diameter;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final emotion = this.emotion;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$day',
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: DodamHome.inkFaint,
          ),
        ),
        const SizedBox(height: 3),
        Container(
          width: diameter,
          height: diameter,
          decoration: BoxDecoration(
            color: emotion?.background ?? DodamHome.emptyCell,
            shape: BoxShape.circle,
            border: isToday
                ? Border.all(color: DodamHome.point, width: 2.5)
                : null,
          ),
          clipBehavior: Clip.antiAlias,
          child: emotion == null
              ? null
              : Padding(
                  padding: const EdgeInsets.all(2),
                  child: Image.asset(
                    emotion.asset,
                    fit: BoxFit.contain,
                    semanticLabel: emotion.label,
                    errorBuilder: (context, error, stackTrace) =>
                        const SizedBox.shrink(),
                  ),
                ),
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.only(top: 12),
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: DodamHome.line)),
    ),
    child: Wrap(
      spacing: 12,
      runSpacing: 6,
      children: [
        for (final emotion in MindEmotion.values)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: emotion.background,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                emotion.label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: DodamHome.inkSoft,
                ),
              ),
            ],
          ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: const BoxDecoration(
                color: DodamHome.emptyCell,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 5),
            const Text(
              '기록 없음',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: DodamHome.inkSoft,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

/// 연·월 선택 다이얼로그(시안 드롭다운 대응). ‹ 연도 › + 12개월 그리드.
class _MonthPickerDialog extends StatefulWidget {
  const _MonthPickerDialog({required this.year, required this.month});
  final int year;
  final int month;

  @override
  State<_MonthPickerDialog> createState() => _MonthPickerDialogState();
}

class _MonthPickerDialogState extends State<_MonthPickerDialog> {
  late int _pickYear = widget.year;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: DodamHome.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 280,
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  onPressed: () => setState(() => _pickYear--),
                  icon: const Icon(Icons.chevron_left_rounded),
                  color: DodamHome.ink,
                ),
                Text(
                  '$_pickYear',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: DodamHome.ink,
                  ),
                ),
                IconButton(
                  onPressed: () => setState(() => _pickYear++),
                  icon: const Icon(Icons.chevron_right_rounded),
                  color: DodamHome.ink,
                ),
              ],
            ),
            const SizedBox(height: 10),
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              childAspectRatio: 1.7,
              children: [
                for (var m = 1; m <= 12; m++)
                  _MonthButton(
                    month: m,
                    selected: _pickYear == widget.year && m == widget.month,
                    onTap: () =>
                        Navigator.of(context).pop(DateTime(_pickYear, m)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthButton extends StatelessWidget {
  const _MonthButton({
    required this.month,
    required this.selected,
    required this.onTap,
  });
  final int month;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? DodamHome.point : DodamHome.surface,
    borderRadius: BorderRadius.circular(10),
    child: InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? DodamHome.pointDeep : DodamHome.line,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          '$month월',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: selected ? DodamHome.onPoint : DodamHome.ink,
          ),
        ),
      ),
    ),
  );
}
