import 'package:flutter/foundation.dart';

import '../../application/canvas_tutorial_controller.dart';
import '../widgets/canvas_tutorial_target_registry.dart';

/// 한 단계에서 아이에게 보여 줄 말과 가리킬 자리다.
///
/// 문구는 지금 툴바가 실제로 하는 일에 맞춘다. 도구는 크레용·연필·붓·물감통이고,
/// 지우개는 선·영역·전체 세 가지이며, 굵기는 단계 버튼이 아니라 막대와 미리보기
/// 동그라미다. 없는 조작을 설명하면 아이가 그 버튼을 찾다가 막힌다.
@immutable
final class CanvasTutorialStepContent {
  const CanvasTutorialStepContent({
    required this.step,
    required this.title,
    required this.description,
    required this.target,
    required this.allowsTargetTap,
    this.practiceLabel,
    this.practicePraise,
    this.trialNotice,
  });

  final CanvasTutorialStep step;
  final String title;
  final String description;

  /// 가리킬 자리다. 화면에 그 조작이 없으면 null 이다.
  final CanvasTutorialTargetId? target;

  /// 안내 중에 그 버튼을 직접 눌러 볼 수 있는지.
  ///
  /// 완료 버튼만 막는다. 실제 완료는 확인 창을 띄우고 활동을 끝내므로, 안내를
  /// 보다가 눌러 그림이 끝나 버리면 안 된다.
  final bool allowsTargetTap;

  /// 이 단계에서 한 번 해 보면 좋은 일이다. 없으면 표시하지 않는다.
  ///
  /// 해내야 다음으로 갈 수 있는 조건이 아니다. 아이가 해 보면 체크만 켜진다.
  final String? practiceLabel;

  /// 해냈을 때 설명 자리에 대신 넣을 칭찬이다.
  final String? practicePraise;

  /// HTP 체험 중에만 덧붙이는 한 줄이다.
  ///
  /// 사람·나무·집 그림은 검은 연필로만 그린다. 안내에서 잠깐 열어 준 도구가
  /// 그림에서는 다시 사라지므로, 사라진다는 말을 미리 해 줘야 한다.
  final String? trialNotice;

  int get stepNumber => step.index + 1;
  static int get stepCount => CanvasTutorialStep.values.length;

  /// [htpTrial] 은 사람·나무·집 그림에서 안내를 위해 도구를 잠시 열어 둔 상태다.
  static CanvasTutorialStepContent of(
    CanvasTutorialStep step, {
    required bool htpTrial,
  }) => switch (step) {
    CanvasTutorialStep.pen => CanvasTutorialStepContent(
      step: step,
      title: '도구를 골라 그려요',
      description: '크레용·연필·붓은 자국이 서로 달라요. 물감통을 고르면 닿은 칸이 한 번에 칠해져요.',
      target: CanvasTutorialTargetId.tools,
      allowsTargetTap: true,
      practiceLabel: '도구를 하나 눌러 보기',
      practicePraise: '좋아요! 이제 종이에 그으면 그 도구 자국이 남아요.',
      trialNotice: htpTrial
          ? '지금은 다 눌러 볼 수 있어요. 사람·나무·집 그림은 검은 연필로 그려요.'
          : null,
    ),
    CanvasTutorialStep.eraser => CanvasTutorialStepContent(
      step: step,
      title: '지우개로 고쳐요',
      description: '지우개를 누르면 선 지우개·영역 지우개·전체 지우기를 고를 수 있어요.',
      target: CanvasTutorialTargetId.eraser,
      allowsTargetTap: true,
      practiceLabel: '지우개를 눌러 보기',
      practicePraise: '잘했어요! 고른 지우개로 문지르면 지워져요.',
    ),
    CanvasTutorialStep.color => CanvasTutorialStepContent(
      step: step,
      title: '좋아하는 색을 골라요',
      description: '색 동그라미를 누르면 바로 바뀌어요. 팔레트에서는 더 많은 색을 고를 수 있어요.',
      target: CanvasTutorialTargetId.colors,
      allowsTargetTap: true,
      practiceLabel: '색을 하나 골라 보기',
      practicePraise: '멋진 색이에요! 도구 끝이 그 색으로 바뀌었어요.',
      trialNotice: htpTrial ? '색은 지금만 골라 볼 수 있어요. 검사 그림은 검은색으로 그려요.' : null,
    ),
    CanvasTutorialStep.thickness => CanvasTutorialStepContent(
      step: step,
      title: '선 굵기를 바꿔요',
      description: '막대를 움직이면 옆 동그라미가 실제로 그려질 굵기를 보여 줘요.',
      target: CanvasTutorialTargetId.thickness,
      allowsTargetTap: true,
      practiceLabel: '막대를 움직여 보기',
      practicePraise: '잘했어요! 옆 동그라미가 같이 커졌어요.',
    ),
    CanvasTutorialStep.undoRedo => CanvasTutorialStepContent(
      step: step,
      title: '되돌리고 다시 그려요',
      description: '왼쪽 화살표는 방금 그린 것을 되돌리고, 오른쪽 화살표는 다시 살려요.',
      target: CanvasTutorialTargetId.history,
      allowsTargetTap: true,
      // 되돌릴 것이 없으면 화살표가 비활성이라 눌러 볼 수 없다. 해보기를 걸지 않는다.
    ),
    CanvasTutorialStep.complete => CanvasTutorialStepContent(
      step: step,
      title: '그림을 마쳐요',
      description: '다 그렸으면 오른쪽 아래 다 그렸어요! 를 눌러요.',
      target: CanvasTutorialTargetId.complete,
      allowsTargetTap: false,
      trialNotice: htpTrial ? '안내를 마치면 검은 연필로 돌아가요. 그때부터 그림을 그려요.' : null,
    ),
  };
}
