import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';
import '../../../conversation/application/voice_answer_playback_controller.dart';
import '../../../conversation/presentation/widgets/voice_answer_playback_control.dart';
import '../../data/dto/diary_insights_dto.dart';
import '../../data/dto/report_dtos.dart';

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
  const DiaryReportV2Body({
    required this.insights,
    this.qaPairs = const [],
    this.playbackController,
    super.key,
  });

  /// 서버가 근거와 대조해 남긴 구조화 결과.
  final DiaryInsightsDto insights;

  /// 아이와 나눈 문답 전체.
  ///
  /// **질문이 없으면 아이 답이 무슨 말인지 알 수 없다.** 구조화 결과의
  /// `childVoiceItems` 는 아이 발화만 담고 질문을 담지 않으므로, 대화의 척추는
  /// 이 목록이 맡는다. 건너뛴 질문도 여기에만 있다 — "넘긴 질문이 있어요"라는
  /// 문장만으로는 무엇을 넘겼는지 보호자가 알 수 없다.
  final List<ReportQaPairDto> qaPairs;

  /// 아이 음성 원본 재생기이며 없으면 재생 버튼을 숨긴다.
  ///
  /// 아이 목소리가 해석의 최상위 근거인데, 글로 옮긴 문장만 남으면 보호자가
  /// 원본을 확인할 길이 없다.
  final VoiceAnswerPlaybackController? playbackController;

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
      // 질문과 함께 보여 준다. 아이 답만 늘어놓으면 "보기에서 고름" 같은 라벨이
      //   무슨 보기였는지 알 수 없고, 건너뛴 질문은 아예 보이지 않는다.
      if (qaPairs.isNotEmpty)
        _DiarySection(
          title: '아이와 나눈 이야기',
          child: _DiaryTranscript(
            qaPairs: qaPairs,
            voices: insights.childVoiceItems,
            playbackController: playbackController,
          ),
        )
      else if (insights.childVoiceItems.isNotEmpty)
        // 문답을 주지 않는 구 응답에서는 예전처럼 발화만 보여 준다.
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
      if (insights.developmentalObservations.isNotEmpty)
        _DiarySection(
          title: '연령에 비춰 본 이번 활동',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final observation in insights.developmentalObservations)
                _DevelopmentalObservationCard(observation: observation),
            ],
          ),
        ),
      if (insights.listeningTip != null)
        _ListeningTipCard(tip: insights.listeningTip!),
      // 확인하지 못한 것을 마지막에 둔다. 섹션이 없으면 보호자는 '문제가 없었다'로 읽는다.
      if (insights.unknownItems.isNotEmpty)
        _DiarySection(
          title: '이번에는 확인하지 못했어요',
          child: _UnknownItemList(items: insights.unknownItems),
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
        // 주장의 세기를 카드 맨 위에 적는다. 이 한 줄이 "아이가 이렇게 말했다"와
        //   "이렇게 볼 수도 있다"를 가른다 — 없으면 둘이 같은 무게로 읽힌다.
        _Badge(text: diaryInsightTypeLabel(observation.insightType)),
        const SizedBox(height: AppSpacing.xs),
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
        // 가설과 다른 설명은 **함께** 나간다. 가설만 보이면 보호자는 그것을 결론으로 읽는다.
        if (observation.hypothesis != null) ...[
          const SizedBox(height: AppSpacing.sm),
          _LabeledLine(label: '이렇게 볼 수도 있어요', text: observation.hypothesis!),
        ],
        if (observation.alternativeExplanations.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          for (final alternative in observation.alternativeExplanations)
            _LabeledLine(label: '다른 설명', text: alternative),
        ],
        if (observation.clarificationQuestion != null) ...[
          const SizedBox(height: AppSpacing.xs),
          _LabeledLine(
            label: '다음에 물어보면',
            text: observation.clarificationQuestion!,
          ),
        ],
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

/// 아이와 나눈 이야기 — 질문·답·재생을 한 줄로 묶는다.
///
/// 문답이 척추다. 아이 답만 보여 주면 "보기에서 고름"이 무슨 보기였는지 알 수
/// 없고, 건너뛴 질문은 화면에서 통째로 사라진다.
///
/// 질문 방식 라벨과 재생은 구조화 결과(`childVoiceItems`)에서 온다. 그쪽은
/// 검증을 통과한 발화만 담으므로 **모든 답에 라벨이 붙지는 않는다** — 라벨이
/// 없는 답도 대화에는 그대로 남긴다. 없는 것을 지어 붙이지 않는다.
class _DiaryTranscript extends StatelessWidget {
  const _DiaryTranscript({
    required this.qaPairs,
    required this.voices,
    required this.playbackController,
  });

  final List<ReportQaPairDto> qaPairs;
  final List<DiaryChildVoiceDto> voices;
  final VoiceAnswerPlaybackController? playbackController;

  @override
  Widget build(BuildContext context) {
    // 답 문장으로 짝을 찾는다. 같은 말을 두 번 했을 수 있어 쓴 것은 빼 가며 본다.
    final remaining = [...voices];
    final tiles = <Widget>[];
    for (final pair in qaPairs) {
      final answer = pair.answer?.trim();
      DiaryChildVoiceDto? voice;
      if (answer != null && answer.isNotEmpty) {
        final index = remaining.indexWhere((item) => item.text.trim() == answer);
        if (index >= 0) voice = remaining.removeAt(index);
      }
      tiles.add(
        _DiaryQaTile(
          pair: pair,
          voice: voice,
          playbackController: playbackController,
        ),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: tiles);
  }
}

/// 문답 한 쌍.
class _DiaryQaTile extends StatelessWidget {
  const _DiaryQaTile({
    required this.pair,
    required this.voice,
    required this.playbackController,
  });

  final ReportQaPairDto pair;
  final DiaryChildVoiceDto? voice;
  final VoiceAnswerPlaybackController? playbackController;

  @override
  Widget build(BuildContext context) {
    final answer = pair.answer?.trim();
    final skipped = pair.state == 'SKIPPED' || answer == null || answer.isEmpty;
    final messageId = int.tryParse(voice?.sourceRef?.id ?? '');
    final canPlay =
        !skipped &&
        pair.inputType == 'VOICE' &&
        messageId != null &&
        messageId > 0 &&
        playbackController != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (pair.question case final question?)
            Text(
              question,
              style: const TextStyle(
                color: AppColors.inkMuted,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                height: 1.45,
              ),
            ),
          const SizedBox(height: 2),
          // 건너뛴 질문은 아이가 한 말이 아니다. 인용으로 세우지 않고 흐리게 남긴다.
          if (skipped)
            const Text(
              '이 질문은 건너뛰었어요',
              style: TextStyle(
                color: AppColors.inkMuted,
                fontSize: 15,
                height: 1.55,
              ),
            )
          else
            Text(
              '"$answer"',
              style: const TextStyle(
                color: AppColors.ink,
                fontSize: 16,
                height: 1.55,
                fontWeight: FontWeight.w700,
              ),
            ),
          if (!skipped) ...[
            const SizedBox(height: 2),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: 2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (voice != null)
                  Text(
                    diaryElicitationLabel(voice!.elicitationType),
                    style: const TextStyle(
                      color: AppColors.inkMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                if (pair.sttNeedsConfirmation)
                  const _Badge(text: '음성 확인 필요'),
              ],
            ),
          ],
          if (canPlay) ...[
            const SizedBox(height: AppSpacing.xxs),
            VoiceAnswerPlaybackControl(
              controller: playbackController!,
              messageId: messageId,
              // 문답이 줄줄이 이어지는 자리라 "재생이 끝났어요" 줄이 남으면 문단이 끊긴다.
              showStatusText: false,
            ),
          ],
        ],
      ),
    );
  }
}

/// 연령 발달 맥락 카드.
///
/// **세 조각을 항상 함께 그린다** — 연령 맥락 → 이번 활동에서 확인된 것 → 범위 고지.
/// 맥락만 남으면 규준 설명이 되고, 범위 고지가 빠지면 한 회차 활동이 발달 평가로 읽힌다.
///
/// 확인하지 못한 도메인도 감추지 않는다. 감추면 남은 것만 보여 '전부 확인했다'로
/// 읽히고, 보이면 '이번에는 여기까지 봤다'가 된다 — 아이가 못한다는 뜻이 아니다.
class _DevelopmentalObservationCard extends StatelessWidget {
  const _DevelopmentalObservationCard({required this.observation});

  final DiaryDevelopmentalObservationDto observation;

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
        // Wrap 이다. 도메인 이름이 길면('함께 있던 사람 이야기하기') 좁은 화면에서
        //   Row 가 넘친다 — 실제로 리포트 화면 폭에서 6.4px 넘쳤다.
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: 4,
          children: [
            _Badge(text: diaryDevelopmentDomainLabel(observation.domain)),
            _Badge(text: diaryDevelopmentStatusLabel(observation.status)),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          observation.ageContext,
          style: const TextStyle(
            color: AppColors.inkMuted,
            fontSize: 14,
            height: 1.55,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          observation.observation,
          style: const TextStyle(
            color: AppColors.ink,
            fontSize: 15,
            height: 1.55,
          ),
        ),
        // 범위 고지. 이 줄이 빠지면 한 회차가 발달 판정으로 읽힌다.
        const SizedBox(height: AppSpacing.sm),
        Text(
          observation.scopeText,
          style: const TextStyle(color: AppColors.inkMuted, fontSize: 13),
        ),
        // 출처는 있을 때만 밝힌다. 비어 있다는 것은 연령 규준을 주장하지 않는
        //   문장이라는 뜻이라, 없는 출처를 지어 붙이지 않는다.
        if (observation.sourceIds.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            '출처 ${observation.sourceIds.join(', ')}',
            style: const TextStyle(color: AppColors.inkMuted, fontSize: 12),
          ),
        ],
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

/// 라벨이 붙은 한 줄. 가설·다른 설명·확인 질문이 서로 구분되게 한다.
class _LabeledLine extends StatelessWidget {
  const _LabeledLine({required this.label, required this.text});

  final String label;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.inkMuted,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          text,
          style: const TextStyle(
            color: AppColors.ink,
            fontSize: 15,
            height: 1.55,
          ),
        ),
      ],
    ),
  );
}

/// 확인하지 못한 것 목록.
class _UnknownItemList extends StatelessWidget {
  const _UnknownItemList({required this.items});

  final List<DiaryUnknownItemDto> items;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final item in items)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 5),
                child: Icon(
                  Icons.remove_circle_outline,
                  size: 16,
                  color: AppColors.inkMuted,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  item.text,
                  style: const TextStyle(
                    color: AppColors.inkMuted,
                    fontSize: 15,
                    height: 1.55,
                  ),
                ),
              ),
            ],
          ),
        ),
    ],
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

/// 주장의 세기를 사용자 문구로 바꾼다.
///
/// 이 라벨이 카드의 무게를 정한다 — 아이가 한 말인지, 이번에만 그렇게 볼 수 있다는 것인지,
/// 아직 뜻을 모르는 단서인지. 모르는 코드는 가장 약한 쪽으로 읽는다.
String diaryInsightTypeLabel(String insightType) => switch (insightType) {
  'CONFIRMED_EXPRESSION' => '아이가 들려준 것',
  'SESSION_HYPOTHESIS' => '이번 활동에서 볼 수 있는 것',
  _ => '더 확인해 볼 것',
};

/// 발달 관찰 도메인 코드를 사용자 문구로 바꾼다.
///
/// 검사 항목처럼 읽히지 않게 '영역' 대신 아이가 한 일로 적는다.
String diaryDevelopmentDomainLabel(String domain) => switch (domain) {
  'NARRATIVE_LANGUAGE' => '이야기로 풀기',
  'EMOTION_EXPRESSION' => '마음 표현하기',
  'SOCIAL_UNDERSTANDING' => '함께 있던 사람 이야기하기',
  'COPING_HELP_SEEKING' => '어려울 때 하기',
  'SELF_REFLECTION' => '바람과 이유 말하기',
  _ => '이번 활동',
};

/// 발달 관찰 상태 코드를 사용자 문구로 바꾼다.
///
/// **`NOT_ASSESSED` 를 '못함'으로 옮기면 안 된다.** 이번 활동에서 확인할 자료가
/// 없었다는 뜻이지 아이가 못한다는 뜻이 아니다 — 모르는 코드도 같은 쪽으로 읽는다.
String diaryDevelopmentStatusLabel(String status) => switch (status) {
  'OBSERVED_THIS_SESSION' => '이번에 확인됨',
  'PARTIALLY_OBSERVED' => '일부 확인됨',
  _ => '이번에는 확인 안 함',
};

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
