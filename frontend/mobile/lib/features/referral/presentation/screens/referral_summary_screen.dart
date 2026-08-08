import 'package:flutter/material.dart';

import '../../../../design_system/tokens/app_spacing.dart';
import '../../data/dto/referral_summary_dto.dart';
import '../../referral_feature.dart';
import '../../domain/repositories/referral_summary_repository.dart';

/// 보호자가 전문가에게 가져갈 의뢰 요약 화면 (S15P11B209-1012).
///
/// **이 화면은 진단도 소견도 아니다.** 전문가가 판단하는 데 필요한 원자료를 모아
/// 보여 줄 뿐이고, 앱의 해석을 대신 주장하지 않는다.
///
/// **순서를 바꾸지 않는다.** 아이가 실제로 한 말이 맨 앞, 앱이 본 것은 뒤다. 전문가가
/// 먼저 읽는 것이 앱의 가설이면 판단이 그 방향으로 끌려간다(앵커링). 서버가 그 순서로
/// 조립해 보내고, 화면도 그대로 그린다.
final class ReferralSummaryScreen extends StatefulWidget {
  const ReferralSummaryScreen({
    required this.childId,
    required this.repository,
    this.sessions,
    super.key,
  });

  /// 대상 아동 식별자.
  final int childId;

  /// 의뢰 요약 조회 경계.
  final ReferralSummaryRepository repository;

  /// 가져올 최근 회차 수이며 없으면 서버 기본값.
  final int? sessions;

  @override
  State<ReferralSummaryScreen> createState() => _ReferralSummaryScreenState();
}

class _ReferralSummaryScreenState extends State<ReferralSummaryScreen> {
  late Future<ReferralSummaryDto> _future;

  @override
  void initState() {
    super.initState();
    // 꺼져 있으면 조회하지 않는다. 준비 중 화면에서 서버를 두드릴 이유가 없다.
    _future = ReferralSummaryFeature.enabled
        ? _load()
        : Future.value(const ReferralSummaryDto());
  }

  /// 꺼져 있으면 조회 자체를 하지 않는다 — 준비 중 화면에서 서버를 두드릴 이유가 없다.
  Future<ReferralSummaryDto> _load() =>
      widget.repository.getReferralSummary(
        widget.childId,
        sessions: widget.sessions,
      );

  void _retry() {
    setState(() {
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!ReferralSummaryFeature.enabled) {
      return Scaffold(
        appBar: AppBar(title: const Text('전문가 의뢰 요약')),
        body: const SafeArea(
          child: Center(
            key: ValueKey('referral-summary-disabled'),
            child: Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: Text(
                ReferralSummaryFeature.disabledNotice,
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('전문가 의뢰 요약')),
      body: SafeArea(
        child: FutureBuilder<ReferralSummaryDto>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(
                key: ValueKey('referral-summary-loading'),
                child: CircularProgressIndicator(),
              );
            }
            if (snapshot.hasError) {
              return _ReferralError(onRetry: _retry);
            }
            final summary = snapshot.data;
            if (summary == null) return _ReferralError(onRetry: _retry);
            return ReferralSummaryBody(summary: summary);
          },
        ),
      ),
    );
  }
}

class _ReferralError extends StatelessWidget {
  const _ReferralError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const ValueKey('referral-summary-error'),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '의뢰 요약을 불러오지 못했어요.',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: AppSpacing.xs),
            const Text(
              '잠시 뒤 다시 시도해 주세요.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton(
              key: const ValueKey('referral-summary-retry'),
              onPressed: onRetry,
              child: const Text('다시 시도'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 의뢰 요약 본문.
///
/// 화면과 나눠 둔 이유는 기능 스위치가 꺼져 있어도 **본문 배치를 테스트할 수 있어야** 하기
/// 때문이다. 지켜야 하는 것은 배치가 아니라 순서다 — 아이가 한 말이 앱의 관찰보다 앞이다.
final class ReferralSummaryBody extends StatelessWidget {
  const ReferralSummaryBody({required this.summary, super.key});

  final ReferralSummaryDto summary;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        _PurposeCard(summary: summary),
        const SizedBox(height: AppSpacing.lg),
        // ⚠️ 아이가 한 말이 맨 앞이다. 이 순서를 바꾸면 앵커링이 생긴다.
        if (summary.hasSessions)
          ...[
            const _SectionTitle('아이가 한 말'),
            for (final session in summary.sessions)
              _SessionCard(session: session),
            const SizedBox(height: AppSpacing.lg),
          ]
        else
          const _EmptySessions(),
        if (summary.repeatedObservations.isNotEmpty) ...[
          const _SectionTitle('되풀이해서 보인 것'),
          const _SectionNote(
            '두 회차 이상에서 확인된 것만 담았어요. 한 번뿐인 것은 여기 오지 않아요.',
          ),
          for (final observation in summary.repeatedObservations)
            _RepeatedObservationTile(observation: observation),
          const SizedBox(height: AppSpacing.lg),
        ],
        if (summary.safetySignals.isNotEmpty) ...[
          const _SectionTitle('안전 신호'),
          for (final signal in summary.safetySignals)
            _SafetySignalTile(signal: signal),
          const SizedBox(height: AppSpacing.lg),
        ],
        const _SectionTitle('답변이 무엇으로 이루어졌나'),
        _AnswerCompositionCard(
          composition: summary.answerComposition,
          voiceRecordingAvailable: summary.voiceRecordingAvailable,
        ),
        const SizedBox(height: AppSpacing.lg),
        if (summary.notIncluded.isNotEmpty) ...[
          const _SectionTitle('이 요약에 담지 않은 것'),
          const _SectionNote(
            '빠진 것을 알아야 없는 것을 "문제 없음"으로 읽지 않아요.',
          ),
          _NotIncludedCard(items: summary.notIncluded),
          const SizedBox(height: AppSpacing.lg),
        ],
        if (summary.reviewNotice case final notice?)
          _ReviewNoticeCard(notice: notice),
      ],
    );
  }
}

class _PurposeCard extends StatelessWidget {
  const _PurposeCard({required this.summary});

  final ReferralSummaryDto summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: const ValueKey('referral-summary-purpose'),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (summary.childDisplayName case final name?)
                  Chip(label: Text(name)),
                if (summary.generatedAt case final at?)
                  Chip(label: Text(_formatDate(at))),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              summary.purpose ??
                  '전문가 상담에 필요한 기록을 모아 정리한 자료예요. 진단이나 소견이 아니에요.',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptySessions extends StatelessWidget {
  const _EmptySessions();

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const ValueKey('referral-summary-empty'),
      child: const Padding(
        padding: EdgeInsets.all(AppSpacing.md),
        child: Text(
          '아직 요약에 담을 활동 기록이 없어요. 그림일기를 몇 번 해 보면 이 자리가 채워져요.',
        ),
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.session});

  final ReferralSessionDto session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (session.activityDate case final date?)
                  Text(
                    _formatDate(date),
                    style: theme.textTheme.labelLarge,
                  ),
                // 아이가 말한 경우에만 표시한다. 활동 날짜는 사건 날짜의 근거가 아니다.
                if (_realityLabel(session.realityStatus) case final label?)
                  _Tag(label),
                if (_timeScopeLabel(session.timeScope) case final label?)
                  _Tag(label),
              ],
            ),
            if (session.headline case final headline?) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(headline, style: theme.textTheme.titleMedium),
            ],
            if (session.mainEvent case final event?) ...[
              const SizedBox(height: AppSpacing.xxs),
              Text(event, style: theme.textTheme.bodyMedium),
            ],
            if (session.childVoices.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: AppSpacing.xs),
                child: Text('이 회차에는 아이가 말로 남긴 답이 없어요.'),
              )
            else
              for (final voice in session.childVoices)
                _ChildVoiceTile(voice: voice),
          ],
        ),
      ),
    );
  }
}

class _ChildVoiceTile extends StatelessWidget {
  const _ChildVoiceTile({required this.voice});

  final ReferralChildVoiceDto voice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('"${voice.text}"', style: theme.textTheme.bodyLarge),
          const SizedBox(height: AppSpacing.xxs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xxs,
            children: [
              // 고른 답을 자발 발화로 읽으면 아이가 실제보다 많이 말한 것처럼 보인다.
              _Tag(voice.spontaneous ? '아이가 스스로 말함' : '보기에서 고름'),
              if (_elicitationLabel(voice.elicitationType) case final label?)
                _Tag(label),
              if (voice.sttNeedsConfirmation)
                const _Tag('음성 인식 확인 필요', emphasized: true),
            ],
          ),
        ],
      ),
    );
  }
}

class _RepeatedObservationTile extends StatelessWidget {
  const _RepeatedObservationTile({required this.observation});

  final ReferralRepeatedObservationDto observation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final first = observation.firstSeenOn;
    final last = observation.lastSeenOn;
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(observation.title, style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.xxs),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xxs,
              children: [
                _Tag('${observation.occurrenceCount}회차에서 확인'),
                if (first != null && last != null)
                  _Tag('${_formatDate(first)} ~ ${_formatDate(last)}'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SafetySignalTile extends StatelessWidget {
  const _SafetySignalTile({required this.signal});

  final ReferralSafetySignalDto signal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xxs,
              children: [
                _Tag(signal.reasonCode, emphasized: true),
                if (signal.severity case final severity?) _Tag(severity),
                if (signal.occurredOn case final on?) _Tag(_formatDate(on)),
              ],
            ),
            const SizedBox(height: AppSpacing.xxs),
            // 처리 내역이 없으면 전문가는 방치됐는지 알 수 없다. 비었으면 그렇다고 적는다.
            Text(
              signal.handling ?? '앱이 취한 처리 내역이 기록되지 않았어요.',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _AnswerCompositionCard extends StatelessWidget {
  const _AnswerCompositionCard({
    required this.composition,
    required this.voiceRecordingAvailable,
  });

  final ReferralAnswerCompositionDto composition;
  final bool voiceRecordingAvailable;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const ValueKey('referral-summary-composition'),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                _Tag('스스로 말한 답 ${composition.spokenAnswerCount}'),
                _Tag('보기에서 고른 답 ${composition.optionAnswerCount}'),
                _Tag('건너뛴 질문 ${composition.skippedCount}'),
                if (composition.sttUnconfirmedCount > 0)
                  _Tag(
                    '확인 필요 ${composition.sttUnconfirmedCount}',
                    emphasized: true,
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            const Text(
              '보기에서 고른 답은 아이가 스스로 말한 것으로 세지 않았어요.',
            ),
            if (voiceRecordingAvailable) ...[
              const SizedBox(height: AppSpacing.xxs),
              // 재생 링크는 담지 않는다 — 이 문서는 공유될 수 있다.
              const Text('아이 목소리 원본은 앱에 남아 있어요. 이 요약에는 담기지 않아요.'),
            ],
          ],
        ),
      ),
    );
  }
}

class _NotIncludedCard extends StatelessWidget {
  const _NotIncludedCard({required this.items});

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const ValueKey('referral-summary-not-included'),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
                child: Text('· $item'),
              ),
          ],
        ),
      ),
    );
  }
}

class _ReviewNoticeCard extends StatelessWidget {
  const _ReviewNoticeCard({required this.notice});

  final String notice;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const ValueKey('referral-summary-review-notice'),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline),
            const SizedBox(width: AppSpacing.xs),
            Expanded(child: Text(notice)),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

class _SectionNote extends StatelessWidget {
  const _SectionNote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Text(text, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.label, {this.emphasized = false});

  final String label;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: emphasized
            ? theme.colorScheme.errorContainer
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label, style: theme.textTheme.labelSmall),
    );
  }
}

String _formatDate(DateTime value) =>
    '${value.year}.${value.month.toString().padLeft(2, '0')}'
    '.${value.day.toString().padLeft(2, '0')}';

/// 아이가 말한 경우에만 라벨을 만든다. `UNKNOWN`이면 아무것도 주장하지 않는다.
String? _realityLabel(String status) => switch (status) {
  'REAL' => '실제 있었던 일',
  'IMAGINED' => '상상한 일',
  _ => null,
};

/// 아이가 말하지 않았으면 시점을 만들지 않는다.
String? _timeScopeLabel(String scope) => switch (scope) {
  'TODAY' => '오늘 일',
  'PAST' => '지난 일',
  'RECURRING' => '자주 있는 일',
  'FUTURE' => '앞으로의 일',
  _ => null,
};

String? _elicitationLabel(String? type) => switch (type) {
  'OPEN' => '열린 질문',
  'OPTION' => '보기 제시',
  'FOLLOW_UP' => '이어 묻기',
  _ => null,
};
