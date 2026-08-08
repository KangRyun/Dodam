import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';
import '../../data/dto/screening_summary_dto.dart';

/// 검사 기록 카드.
///
/// **이 앱은 표준화 선별검사를 제공하지 않는다.** 여기 보이는 것은 보호자가 다른
/// 곳에서 받아 와 직접 옮겨 적은 결과이며, 앱이 실시하거나 채점한 값이 아니다.
///
/// 그래서 세 가지를 화면이 반드시 지킨다.
///
/// 1. 그림일기 관찰과 **자리를 나눈다.** 한 덩어리로 보이면 보호자는 앱이 검사를
///    해 줬다고 읽는다.
/// 2. 기록마다 **'보호자가 입력한 기록'임을 붙인다.** 검증 주체가 없는 값을 공식
///    결과처럼 보여 주는 것이 이 화면에서 가장 위험한 실패다.
/// 3. 기록이 없어도 **문구는 그린다.** 침묵은 '앱이 선별을 해 준다'는 오해를 남긴다.
class ScreeningSummaryCard extends StatelessWidget {
  /// 검사 기록 요약으로 카드를 만든다.
  const ScreeningSummaryCard({required this.summary, super.key});

  /// 서버가 만든 검사 기록 요약.
  final ScreeningSummaryDto summary;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Semantics(
        header: true,
        child: const Text(
          '검사 기록',
          style: TextStyle(
            color: AppColors.lavender,
            fontSize: 20,
            height: 1.3,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      const SizedBox(height: AppSpacing.md),
      if (summary.message != null)
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surfaceSoft,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Text(
            summary.message!,
            style: const TextStyle(
              color: AppColors.inkMuted,
              fontSize: 14,
              height: 1.55,
            ),
          ),
        ),
      for (final record in summary.records) ...[
        const SizedBox(height: AppSpacing.sm),
        _ScreeningRecordTile(record: record),
      ],
    ],
  );
}

/// 기록 한 건.
class _ScreeningRecordTile extends StatelessWidget {
  const _ScreeningRecordTile({required this.record});

  final ScreeningRecordDto record;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.surfaceSoft,
      borderRadius: BorderRadius.circular(AppRadius.md),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 출처 표시가 먼저다. 결과 문구를 먼저 읽으면 그다음에 붙는 단서는 잘 안 읽힌다.
        Text(
          screeningSourceLabel(record.sourceVerified),
          style: const TextStyle(
            color: AppColors.inkMuted,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          record.instrumentDisplayName,
          style: const TextStyle(
            color: AppColors.ink,
            fontSize: 16,
            height: 1.4,
            fontWeight: FontWeight.w800,
          ),
        ),
        if (record.completedAt != null) ...[
          const SizedBox(height: 2),
          Text(
            '${record.completedAt!.year}년 ${record.completedAt!.month}월 '
            '${record.completedAt!.day}일'
            '${record.sourceAuthorityName == null ? '' : ' · ${record.sourceAuthorityName}'}',
            style: const TextStyle(color: AppColors.inkMuted, fontSize: 13),
          ),
        ],
        const SizedBox(height: AppSpacing.xs),
        Text(
          record.officialResultText,
          style: const TextStyle(
            color: AppColors.ink,
            fontSize: 15,
            height: 1.55,
          ),
        ),
        for (final domain in record.domainResults) ...[
          const SizedBox(height: 2),
          Text(
            '${domain.domainName} · ${domain.resultLabel}',
            style: const TextStyle(
              color: AppColors.ink,
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ],
        if (record.followupMessage != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            record.followupMessage!,
            style: const TextStyle(
              color: AppColors.ink,
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ],
        if (record.referralOptions.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            '상담 가능한 곳 · ${record.referralOptions.join(', ')}',
            style: const TextStyle(color: AppColors.inkMuted, fontSize: 13),
          ),
        ],
        // 필수 고지는 등록부가 소유한다. 선별은 진단이 아니라는 말이 결과와 떨어지면 안 된다.
        if (record.requiredDisclosure != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            record.requiredDisclosure!,
            style: const TextStyle(color: AppColors.inkMuted, fontSize: 13),
          ),
        ],
      ],
    ),
  );
}

/// 기록의 출처를 사용자 문구로 바꾼다.
///
/// **검증되지 않은 기록을 공식 결과로 부르지 않는다.** 공식 서비스 연동이 없어
/// 지금은 언제나 '보호자가 입력한 기록'이며, 그 사실을 감추면 앱이 확인해 준
/// 결과처럼 읽힌다.
String screeningSourceLabel(bool sourceVerified) =>
    sourceVerified ? '확인된 공식 결과' : '보호자가 입력한 기록';
