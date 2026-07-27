import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../../domain/entities/push_message.dart';
import 'local_push_presenter.dart';

/// 앱이 백그라운드·종료 상태일 때 도착한 메시지를 처리한다.
///
/// 계약(§0-1)상 `data`-only라 OS가 알림을 대신 띄워 주지 않는다. 이 격리(isolate)
/// 에서 직접 띄우지 않으면 사용자는 아무것도 보지 못한다.
///
/// 별도 격리에서 실행되므로 앱 상태(로그인·현재 화면)에 접근할 수 없다. 중복
/// 방지도 여기선 동작하지 않지만, 포그라운드 경로와 동시에 실행되지 않아 문제가
/// 되지 않는다.
@pragma('vm:entry-point')
Future<void> handlePushInBackground(RemoteMessage message) async {
  final parsed = PushMessage.tryParse(message.data);
  if (parsed == null) return;

  await Firebase.initializeApp();

  final presenter = LocalPushPresenter();
  try {
    await presenter.initialize();
    await presenter.show(parsed);
  } finally {
    await presenter.dispose();
  }
}
