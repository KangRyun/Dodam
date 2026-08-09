import 'package:flutter/material.dart';

import '../../core/network/network.dart';
import '../../design_system/design_system.dart';

/// 실패 객체 하나로 "어떤 안내를 보여줄지"까지 정하는 화면 조각.
///
/// 화면마다 `AppRetryView`와 `AppErrorView` 중 무엇을 쓸지 손으로 고르면
/// 오프라인인데 서버 오류 문구가 뜨는 식의 어긋남이 생긴다. 판단을
/// [ApiFailurePresentation] 한 곳에 모으고, 화면은 "무엇을 못 했는지"만
/// [title]로 알려준다.
///
/// 디자인 시스템이 아니라 앱 계층에 두는 이유: 네트워크 타입을 아는 위젯이라
/// `design_system`이 `core/network`에 의존하게 만들지 않기 위함이다.
class AppFailureView extends StatelessWidget {
  const AppFailureView({
    required this.title,
    required this.failure,
    this.onRetry,
    this.childFriendly = false,
    super.key,
  });

  /// 무엇을 하지 못했는지. 예: '활동 기록을 불러오지 못했어요'.
  final String title;

  /// 잡아둔 실패 객체. [ApiFailure]가 아니어도 되고 null이어도 된다.
  final Object? failure;

  /// 재시도 동작. 재시도해도 결과가 같은 실패(401·403·404 등)에서는
  /// 넘겨도 무시하고 버튼을 감춘다.
  final VoidCallback? onRetry;

  final bool childFriendly;

  @override
  Widget build(BuildContext context) {
    final presentation = ApiFailurePresentation.of(
      failure,
      childFriendly: childFriendly,
    );
    final retry = presentation.canRetry ? onRetry : null;

    if (presentation.isConnectivity && retry != null) {
      return AppRetryView(
        title: title,
        message: presentation.message,
        onRetry: retry,
        childFriendly: childFriendly,
      );
    }

    return AppErrorView(
      title: title,
      message: presentation.message,
      onRetry: retry,
      childFriendly: childFriendly,
    );
  }
}
