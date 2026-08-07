import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';
import '../../data/dto/diary_insights_dto.dart';

/// 그림일기 리포트 V2 본문.
///
/// 한 회차의 그림일기를 '주요 심리 경향'으로 만들지 않는 것이 이 화면의 목적이다.
/// 대신 아이가 들려준 이야기를 순서대로 보여 주고, 각 항목이 어떤 답변에서 나왔는지
/// 함께 표시한다.
///
/// 데이터가 없는 섹션은 그리지 않는다. 빈 섹션을 일반론으로 채우지 않는 것이
/// 서버 쪽 계약이라, 화면도 같은 규칙을 따른다.
class DiaryReportV2Body extends StatelessWidget {
  /// 구조화 결과로 본문을 만든다.
  const DiaryReportV2Body({required this.insights, super.key});

  /// 서버가 근거와 대조해 남긴 구조화 결과.
  final DiaryInsightsDto insights;

  @override
  Widget build(BuildContext context) {
    final snapshot = insights.storySnapshot;
    final sections = <Widget>[
      if (snapshot != null) _StorySnapshotCard(snapshot: snapshot),
      if (insights.narrativeFlow.isNotEmpty)
        _DiarySection(
          title: '이야기 흐름',
          child: _NarrativeTimeline(steps: insights.narrativeFlow),
        ),
      if (insights.childVoiceItems.isNotEmpty)
        _DiarySection(
          title: '아이가 들려준 말',
          child: _ChildVoiceList(items: insights.childVoiceItems),
        ),
      if (insights.sessionObservations.isNotEmpty)
        _DiarySection(
          title: '이번 활동에서 확인된 표현',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final observation in insights.sessionObservations)
                _SessionObservationCard(observation: observation),
            ],
          ),
        ),
      if (insights.caregiverQuestions.isNotEmpty)
        _DiarySection(
          title: '이어서 물어보면 좋아요',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final question in insights.caregiverQuestions)
                _CaregiverQuestionTile(question: question),
            ],
          ),
        ),
      if (insights.listeningTip != null)
        _ListeningTipCard(tip: insights.listeningTip!),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, section) in sections.indexed) ...[
          if (index > 0) const SizedBox(height: AppSpacing.lg),
          section,
        ],
      ],
    );
  }
}

/// 제목과 본문을 묶는 V2 섹션.
class _DiarySection extends StatelessWidget {
  const _DiarySection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Semantics(
        header: true,
        child: Text(
          title,
          style: const TextStyle(
            color: AppColors.lavender,
            fontSize: 20,
            height: 1.3,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      const SizedBox(height: AppSpacing.md),
      child,
    ],
  );
}

/// 핵심 이야기 한 장.
class _StorySnapshotCard extends StatelessWidget {
  const _StorySnapshotCard({required this.snapshot});

  final DiaryStorySnapshotDto snapshot;

  @override
  Widget build(BuildContext context) {
    final badges = <String>[
      ?diaryRealityLabel(snapshot.realityStatus),
      ?diaryTimeScopeLabel(snapshot.timeScope),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (snapshot.headline != null)
          Text(
            snapshot.headline!,
            style: const TextStyle(
              color: AppColors.ink,
              fontSize: 22,
              height: 1.35,
              fontWeight: FontWeight.w900,
            ),
          ),
        if (badges.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [for (final badge in badges) _Badge(text: badge)],
          ),
        ],
        if (snapshot.summary != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            snapshot.summary!,
            style: const TextStyle(
              color: AppColors.ink,
              fontSize: 16,
              height: 1.6,
            ),
          ),
        ],
      ],
    );
  }
}

/// 사건 → 행동 → 반응 순서를 세로로 잇는다.
class _NarrativeTimeline extends StatelessWidget {
  const _NarrativeTimeline({required this.steps});

  final List<DiaryNarrativeStepDto> steps;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final (index, step) in steps.indexed)
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    margin: const EdgeInsets.only(top: 6),
                    decoration: const BoxDecoration(
                      color: AppColors.lavender,
                      shape: BoxShape.circle,
                    ),
                  ),
                  if (index < steps.length - 1)
                    const Expanded(
                      child: VerticalDivider(
                        width: 10,
                        thickness: 1,
                        color: AppColors.outline,
                      ),
                    ),
                ],
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        diaryStepLabel(step.stepType),
                        style: const TextStyle(
                          color: AppColors.inkMuted,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        step.text,
                        style: const TextStyle(
                          color: AppColors.ink,
                          fontSize: 16,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
    ],
  );
}

/// 아이 발화 목록. 어떻게 나온 말인지 함께 보여 준다.
class _ChildVoiceList extends StatelessWidget {
  const _ChildVoiceList({required this.items});

  final List<DiaryChildVoiceDto> items;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final item in items)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '"${item.text}"',
                style: const TextStyle(
                  color: AppColors.ink,
                  fontSize: 16,
                  height: 1.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  _Badge(text: diaryElicitationLabel(item.elicitationType)),
                  if (item.sttNeedsConfirmation)
                    const _Badge(text: '음성 확인 필요'),
                ],
              ),
            ],
          ),
        ),
    ],
  );
}

/// 이번 활동 관찰 카드. 범위 문구를 반드시 함께 보여 준다.
class _SessionObservationCard extends StatelessWidget {
  const _SessionObservationCard({required this.observation});

  final DiarySessionObservationDto observation;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: AppSpacing.sm),
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.surfaceSoft,
      borderRadius: BorderRadius.circular(AppRadius.md),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          observation.title,
          style: const TextStyle(
            color: AppColors.ink,
            fontSize: 16,
            height: 1.4,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          observation.description,
          style: const TextStyle(
            color: AppColors.ink,
            fontSize: 15,
            height: 1.55,
          ),
        ),
        // 범위 문구는 장식이 아니다. 이 한 줄이 없으면 한 번의 활동이 아이의
        //   지속적인 성향으로 읽힌다.
        if (observation.scopeText != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            observation.scopeText!,
            style: const TextStyle(color: AppColors.inkMuted, fontSize: 13),
          ),
        ],
      ],
    ),
  );
}

/// 보호자가 그대로 물어볼 질문.
class _CaregiverQuestionTile extends StatelessWidget {
  const _CaregiverQuestionTile({required this.question});

  final DiaryCaregiverQuestionDto question;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.md),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 3),
          child: Icon(
            Icons.chat_bubble_outline,
            size: 18,
            color: AppColors.lavender,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                question.question,
                style: const TextStyle(
                  color: AppColors.ink,
                  fontSize: 16,
                  height: 1.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (question.purpose != null) ...[
                const SizedBox(height: 2),
                Text(
                  question.purpose!,
                  style: const TextStyle(
                    color: AppColors.inkMuted,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

/// 듣는 방법 한 줄.
class _ListeningTipCard extends StatelessWidget {
  const _ListeningTipCard({required this.tip});

  final String tip;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.surfaceSoft,
      borderRadius: BorderRadius.circular(AppRadius.md),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.hearing_outlined, size: 18, color: AppColors.lavender),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            tip,
            style: const TextStyle(
              color: AppColors.ink,
              fontSize: 15,
              height: 1.55,
            ),
          ),
        ),
      ],
    ),
  );
}

/// 작은 상태 표시.
class _Badge extends StatelessWidget {
  const _Badge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.sm,
      vertical: 2,
    ),
    decoration: BoxDecoration(
      color: AppColors.surfaceSoft,
      borderRadius: BorderRadius.circular(AppRadius.sm),
    ),
    child: Text(
      text,
      style: const TextStyle(
        color: AppColors.inkMuted,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

/// 이야기 단계 코드를 사용자 문구로 바꾼다. 모르는 코드는 표시하지 않는다.
String diaryStepLabel(String stepType) => switch (stepType) {
  'EVENT' => '있었던 일',
  'CHILD_ACTION' => '아이가 한 행동',
  'OTHER_RESPONSE' => '함께 있던 사람의 반응',
  'EMOTION' => '아이가 말한 마음',
  'WISH' => '아이가 바란 것',
  'OUTCOME' => '이야기의 끝',
  _ => '이야기',
};

/// 질문 방식 코드를 사용자 문구로 바꾼다.
///
/// 선택지에서 고른 답과 아이가 스스로 만든 문장을 화면에서도 갈라 보여 주기 위한 값이다.
String diaryElicitationLabel(String elicitationType) => switch (elicitationType) {
  'OPEN_INVITATION' => '스스로 이야기함',
  'CUED_INVITATION' => '앞의 말에서 이어짐',
  'FOCUSED_WH' => '좁혀 물었을 때 답함',
  'YES_NO' => '예·아니오로 답함',
  'MULTIPLE_CHOICE' => '보기에서 고름',
  'CORRECTION' => '아이가 바로잡음',
  _ => '답변',
};

/// 실제/상상 코드를 사용자 문구로 바꾼다.
///
/// **모르면 아무 말도 붙이지 않는다**(`null`). 아이가 말하지 않은 것을 화면이
/// 정해 버리면, 상상한 이야기가 있었던 일로 보호자에게 전달된다.
String? diaryRealityLabel(String realityStatus) => switch (realityStatus) {
  'REAL' => '실제로 있었던 일',
  'IMAGINED' => '상상한 이야기',
  'MIXED' => '실제와 상상이 섞인 이야기',
  _ => null,
};

/// 사건 시점 코드를 사용자 문구로 바꾼다. 아이가 말하지 않았으면 `null`.
String? diaryTimeScopeLabel(String timeScope) => switch (timeScope) {
  'TODAY' => '오늘 있었던 일',
  'YESTERDAY' => '어제 있었던 일',
  'RECENT' => '최근에 있었던 일',
  'PAST' => '예전에 있었던 일',
  _ => null,
};
