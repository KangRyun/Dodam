import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';
import '../../../conversation/application/voice_answer_playback_controller.dart';
import '../../../conversation/presentation/widgets/voice_answer_playback_control.dart';
import '../../data/dto/diary_insights_dto.dart';

/// 근거의 범위와 해석의 한계를 함께 보여 주는 그림일기 V3 본문.
///
/// 자료 범위 → 관찰 사실 → 아이 이야기 → 제한적 해석 순서를 지킨다. 단일 활동을
/// 성향이나 진단처럼 보이지 않게 하며, 자료가 LIMITED이면 가설을 표시하지 않는다.
final class DiaryReportV3Body extends StatelessWidget {
  const DiaryReportV3Body({
    required this.insights,
    this.playbackController,
    super.key,
  });

  final DiaryInsightsDto insights;
  final VoiceAnswerPlaybackController? playbackController;

  @override
  Widget build(BuildContext context) {
    final limited = insights.dataScope?.evidenceLevel == 'LIMITED';
    final confirmed = insights.sessionObservations
        .where((item) => item.insightType != 'SESSION_HYPOTHESIS')
        .toList(growable: false);
    final hypotheses = limited
        ? const <DiarySessionObservationDto>[]
        : insights.sessionObservations
              .where((item) => item.insightType == 'SESSION_HYPOTHESIS')
              .toList(growable: false);
    final sections = <Widget>[
      if (insights.storySnapshot case final story?) _StoryLead(story: story),
      if (insights.dataScope case final scope?) _DataScopeCard(scope: scope),
      if (insights.drawingObservations.isNotEmpty)
        _Section(
          title: '그림에서 확인된 표현',
          caption: '그림에서 직접 확인한 사실만 적었어요.',
          child: _DrawingObservations(items: insights.drawingObservations),
        ),
      if (insights.storyComponents.isNotEmpty)
        _Section(
          title: '이야기 구성 지도',
          caption: '확인된 내용과 아직 모르는 내용을 구분했어요.',
          child: _StoryMap(items: insights.storyComponents),
        ),
      if (insights.childVoiceItems.isNotEmpty)
        _Section(
          title: '아이가 직접 들려준 말',
          child: _ChildVoices(items: insights.childVoiceItems),
        ),
      if (confirmed.isNotEmpty)
        _Section(
          title: '이번 활동에서 확인된 표현',
          child: _ObservationCards(items: confirmed),
        ),
      if (hypotheses.isNotEmpty)
        _Section(
          title: '그림과 대화에서 생각해 볼 수 있는 가능성',
          caption: '이번 활동에서만 조심스럽게 생각해 본 내용이며 결론이 아니에요.',
          child: _ObservationCards(items: hypotheses, showReasoning: true),
        ),
      if (insights.unknownItems.isNotEmpty)
        _Section(
          title: '이번에는 확인하지 못했어요',
          child: _UnknownItems(items: insights.unknownItems),
        ),
      if (insights.caregiverQuestions.isNotEmpty ||
          insights.listeningTip != null)
        _Section(
          title: '오늘 마음 나누기',
          caption: insights.listeningTip,
          child: _CaregiverQuestions(items: insights.caregiverQuestions),
        ),
      if (insights.developmentalObservations.isNotEmpty)
        _Section(
          title: '연령에 비춰 본 이번 활동',
          caption: '한 번의 활동만으로 발달 수준을 평가하거나 진단하지 않아요.',
          child: _DevelopmentalContext(
            items: insights.developmentalObservations,
          ),
        ),
      if (insights.transcript.isNotEmpty)
        _TranscriptDetails(
          items: insights.transcript,
          playbackController: playbackController,
        ),
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

final class _StoryLead extends StatelessWidget {
  const _StoryLead({required this.story});

  final DiaryStorySnapshotDto story;

  @override
  Widget build(BuildContext context) => _Surface(
    color: AppColors.tangerineSoft,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (story.headline case final headline?)
          Text(
            headline,
            style: const TextStyle(
              color: AppColors.ink,
              fontSize: 22,
              height: 1.35,
              fontWeight: FontWeight.w900,
            ),
          ),
        if (story.summary case final summary?) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(summary, style: _bodyStyle),
        ],
      ],
    ),
  );
}

final class _DataScopeCard extends StatelessWidget {
  const _DataScopeCard({required this.scope});

  final DiaryDataScopeDto scope;

  @override
  Widget build(BuildContext context) => _Section(
    title: '이번 기록의 자료 범위',
    child: _Surface(
      color: _scopeColor(scope.evidenceLevel),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.fact_check_outlined, color: AppColors.ink),
              const SizedBox(width: AppSpacing.xs),
              Text(
                _scopeLabel(scope.evidenceLevel),
                style: const TextStyle(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          if (scope.summary.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(scope.summary, style: _bodyStyle),
          ],
          const SizedBox(height: AppSpacing.sm),
          Text(
            '아이 직접 발화 ${scope.confirmedVoiceCount}개 · 선택 답변 '
            '${scope.optionAnswerCount}개 · 그림 관찰 ${scope.visualObservationCount}개',
            style: _captionStyle,
          ),
          if (scope.skippedCount > 0 || scope.sttConfirmationCount > 0)
            Text(
              '건너뜀 ${scope.skippedCount}개 · 확인 필요한 음성 '
              '${scope.sttConfirmationCount}개',
              style: _captionStyle,
            ),
        ],
      ),
    ),
  );
}

final class _DrawingObservations extends StatelessWidget {
  const _DrawingObservations({required this.items});

  final List<DiaryDrawingObservationDto> items;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final item in items) ...[
        _Surface(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.visibility_outlined, color: AppColors.leaf),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(item.text, style: _bodyStyle),
                    if (item.childConfirmed) ...[
                      const SizedBox(height: AppSpacing.xs),
                      const Text('아이의 말로도 확인했어요.', style: _captionStyle),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        if (item != items.last) const SizedBox(height: AppSpacing.sm),
      ],
    ],
  );
}

final class _StoryMap extends StatelessWidget {
  const _StoryMap({required this.items});

  final List<DiaryStoryComponentDto> items;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: AppSpacing.sm,
    runSpacing: AppSpacing.sm,
    children: [
      for (final item in items)
        SizedBox(
          width: 220,
          child: _Surface(
            color: item.confirmationStatus == 'UNKNOWN'
                ? AppColors.surfaceSoft
                : AppColors.leafSoft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _componentLabel(item.componentType),
                  style: const TextStyle(
                    color: AppColors.inkMuted,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(item.text ?? '아직 확인하지 못했어요.', style: _bodyStyle),
              ],
            ),
          ),
        ),
    ],
  );
}

final class _ChildVoices extends StatelessWidget {
  const _ChildVoices({required this.items});

  final List<DiaryChildVoiceDto> items;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final item in items) ...[
        _Surface(
          color: AppColors.lavenderSoft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('“${item.text}”', style: _bodyStyle),
              const SizedBox(height: AppSpacing.xs),
              Text(
                _elicitationLabel(item.elicitationType),
                style: _captionStyle,
              ),
              if (item.sttNeedsConfirmation)
                const Text('음성 인식 내용을 확인해 주세요.', style: _captionStyle),
            ],
          ),
        ),
        if (item != items.last) const SizedBox(height: AppSpacing.sm),
      ],
    ],
  );
}

final class _ObservationCards extends StatelessWidget {
  const _ObservationCards({required this.items, this.showReasoning = false});

  final List<DiarySessionObservationDto> items;
  final bool showReasoning;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final item in items) ...[
        _Surface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(item.title, style: _cardTitleStyle),
              const SizedBox(height: AppSpacing.xs),
              Text(item.description, style: _bodyStyle),
              if (showReasoning && item.hypothesis != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(item.hypothesis!, style: _bodyStyle),
              ],
              if (showReasoning && item.alternativeExplanations.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                const Text('다르게 볼 수도 있어요', style: _cardTitleStyle),
                for (final alternative in item.alternativeExplanations)
                  Text('• $alternative', style: _bodyStyle),
              ],
              if (showReasoning && item.clarificationQuestion != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  '다음에 이렇게 물어보세요: ${item.clarificationQuestion!}',
                  style: _bodyStyle,
                ),
              ],
              if (item.scopeText case final scope?) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(scope, style: _captionStyle),
              ],
            ],
          ),
        ),
        if (item != items.last) const SizedBox(height: AppSpacing.sm),
      ],
    ],
  );
}

final class _UnknownItems extends StatelessWidget {
  const _UnknownItems({required this.items});

  final List<DiaryUnknownItemDto> items;

  @override
  Widget build(BuildContext context) => _Surface(
    color: AppColors.surfaceSoft,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in items) Text('• ${item.text}', style: _bodyStyle),
      ],
    ),
  );
}

final class _CaregiverQuestions extends StatelessWidget {
  const _CaregiverQuestions({required this.items});

  final List<DiaryCaregiverQuestionDto> items;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final item in items) ...[
        _Surface(
          color: AppColors.tangerineSoft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(item.question, style: _cardTitleStyle),
              if (item.responseGuide case final guide?) ...[
                const SizedBox(height: AppSpacing.sm),
                Text('마음으로 답하기 · $guide', style: _bodyStyle),
              ],
              if (item.coRegulationAction case final action?) ...[
                const SizedBox(height: AppSpacing.xs),
                Text('함께 해보기 · $action', style: _bodyStyle),
              ],
            ],
          ),
        ),
        if (item != items.last) const SizedBox(height: AppSpacing.sm),
      ],
    ],
  );
}

final class _DevelopmentalContext extends StatelessWidget {
  const _DevelopmentalContext({required this.items});

  final List<DiaryDevelopmentalObservationDto> items;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final item in items) ...[
        _Surface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(item.ageContext, style: _cardTitleStyle),
              const SizedBox(height: AppSpacing.xs),
              Text(item.observation, style: _bodyStyle),
              const SizedBox(height: AppSpacing.sm),
              Text(item.scopeText, style: _captionStyle),
              if (item.caregiverQuestion case final question?) ...[
                const SizedBox(height: AppSpacing.sm),
                Text('이어 물어보기 · $question', style: _bodyStyle),
              ],
            ],
          ),
        ),
        if (item != items.last) const SizedBox(height: AppSpacing.sm),
      ],
    ],
  );
}

final class _TranscriptDetails extends StatelessWidget {
  const _TranscriptDetails({required this.items, this.playbackController});

  final List<DiaryTranscriptEntryDto> items;
  final VoiceAnswerPlaybackController? playbackController;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surface,
    shape: RoundedRectangleBorder(
      side: const BorderSide(color: AppColors.outline),
      borderRadius: BorderRadius.circular(AppRadius.md),
    ),
    clipBehavior: Clip.antiAlias,
    child: ExpansionTile(
      title: const Text(
        '전체 대화와 활동 상세',
        style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w900),
      ),
      subtitle: Text('질문과 답변 ${items.length}개', style: _captionStyle),
      childrenPadding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.md,
      ),
      children: [
        for (final (index, item) in items.indexed) ...[
          if (index > 0) const Divider(height: AppSpacing.lg),
          _TranscriptEntry(item: item, playbackController: playbackController),
        ],
      ],
    ),
  );
}

final class _TranscriptEntry extends StatelessWidget {
  const _TranscriptEntry({required this.item, this.playbackController});

  final DiaryTranscriptEntryDto item;
  final VoiceAnswerPlaybackController? playbackController;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (item.questionText case final question?) ...[
        Text('도담 · $question', style: _cardTitleStyle),
        const SizedBox(height: AppSpacing.xs),
      ],
      Text(
        item.answerText ?? _emptyAnswerLabel(item.responseType),
        style: _bodyStyle,
      ),
      const SizedBox(height: AppSpacing.xs),
      Text(_responseTypeLabel(item.responseType), style: _captionStyle),
      if (item.hasPlayableAudio && playbackController != null) ...[
        const SizedBox(height: AppSpacing.sm),
        VoiceAnswerPlaybackControl(
          controller: playbackController!,
          messageId: item.answerMessageId!,
          showStatusText: false,
        ),
      ] else if (item.responseType == 'VOICE' && !item.audioAvailable) ...[
        const SizedBox(height: AppSpacing.xs),
        const Text('원본 음성은 더 이상 재생할 수 없어요.', style: _captionStyle),
      ],
    ],
  );
}

final class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.caption});

  final String title;
  final String? caption;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        title,
        style: const TextStyle(
          color: AppColors.lavender,
          fontSize: 20,
          height: 1.3,
          fontWeight: FontWeight.w900,
        ),
      ),
      if (caption case final text?) ...[
        const SizedBox(height: AppSpacing.xs),
        Text(text, style: _captionStyle),
      ],
      const SizedBox(height: AppSpacing.md),
      child,
    ],
  );
}

final class _Surface extends StatelessWidget {
  const _Surface({required this.child, this.color = AppColors.surface});

  final Widget child;
  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: color,
      border: Border.all(color: AppColors.outline),
      borderRadius: BorderRadius.circular(AppRadius.md),
    ),
    child: Padding(padding: const EdgeInsets.all(AppSpacing.md), child: child),
  );
}

const _bodyStyle = TextStyle(color: AppColors.ink, fontSize: 15, height: 1.55);
const _captionStyle = TextStyle(
  color: AppColors.inkMuted,
  fontSize: 13,
  height: 1.45,
);
const _cardTitleStyle = TextStyle(
  color: AppColors.ink,
  fontSize: 16,
  height: 1.45,
  fontWeight: FontWeight.w800,
);

Color _scopeColor(String level) => switch (level) {
  'RICH' => AppColors.leafSoft,
  'PARTIAL' => AppColors.brandYellowSoft,
  _ => AppColors.surfaceSoft,
};

String _scopeLabel(String level) => switch (level) {
  'RICH' => '이야기와 그림을 함께 살펴봤어요',
  'PARTIAL' => '확인된 내용 안에서 살펴봤어요',
  _ => '확인할 수 있는 자료가 적어요',
};

String _componentLabel(String type) => switch (type) {
  'ACTOR' => '누가',
  'EVENT' => '무슨 일',
  'CHILD_ACTION' => '아이의 행동',
  'OTHER_RESPONSE' => '상대의 반응',
  'EMOTION' => '마음',
  'WISH' => '바람',
  'OUTCOME' => '그 뒤',
  _ => '이야기 단서',
};

String _elicitationLabel(String type) => switch (type) {
  'OPEN_INVITATION' => '열린 질문에 스스로 이야기함',
  'OPTION' || 'FORCED_CHOICE' => '선택지에서 고름',
  'YES_NO' => '예·아니오 질문에 답함',
  _ => '아이의 답변',
};

String _responseTypeLabel(String type) => switch (type) {
  'VOICE' => '음성으로 답함',
  'OPTION' => '선택지에서 고름',
  'TEXT' => '글로 답함',
  'CORRECTION' => '음성 인식 내용을 고침',
  'SKIPPED' => '질문을 건너뜀',
  _ => '답변',
};

String _emptyAnswerLabel(String type) =>
    type == 'SKIPPED' ? '이 질문은 건너뛰었어요.' : '남긴 답변이 없어요.';
