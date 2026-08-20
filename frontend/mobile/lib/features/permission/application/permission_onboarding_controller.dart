import '../../conversation/domain/services/microphone_permission_service.dart';
import '../../drawing/domain/photo_permission_service.dart';
import '../../notification/domain/services/push_permission_service.dart';
import '../domain/permission_onboarding_store.dart';

/// 로그인 직후 한 번만 세우는 권한 안내의 상태와 요청을 담당한다.
///
/// 권한 요청 자체는 이미 각 기능이 쓰는 서비스에 위임한다 — 마이크(음성 답변)·
/// 카메라(종이 그림 촬영)·알림(리포트 안내). 여기서 하는 일은 "미리 한 번에
/// 묻기"뿐이고, 각 기능이 필요한 순간에 다시 묻는 기존 경로는 그대로 살아 있다.
///
/// [isPending] 이 **동기 게터**인 이유: 로그인 화면이 다음 화면으로 넘어가는
/// 콜백(`void Function(BuildContext)`)에는 await 할 자리가 없다. 대신 보호자 세션이
/// 확정되는 지점([load] 호출처)에서 미리 읽어 두고, 라우터는 읽기가 끝난 값만
/// 본다.
final class PermissionOnboardingController {
  PermissionOnboardingController({
    required this.store,
    required this.microphonePermissionService,
    required this.photoPermissionService,
    required this.pushPermissionService,
  });

  final PermissionOnboardingStore store;
  final MicrophonePermissionService microphonePermissionService;
  final PhotoPermissionService photoPermissionService;
  final PushPermissionService pushPermissionService;

  bool _loaded = false;
  bool _answered = false;

  /// 지금 권한 안내를 세워야 하는지.
  ///
  /// [load]를 지나기 전에는 항상 거짓이다 — 읽지 않은 상태에서 참을 돌려주면 이미
  /// 응답한 사용자에게 화면이 한 번 더 스쳐 지나간다.
  bool get isPending => _loaded && !_answered;

  /// 저장된 응답 여부를 읽어 [isPending]을 확정한다.
  ///
  /// 읽기에 실패하면 "아직 안 물었다"로 본다. 건너뛸 수 있는 화면이라 잘못 보여도
  /// 한 번 더 뜨는 것으로 끝나지만, 반대로 잘못 숨기면 기능이 조용히 사라진다.
  Future<void> load() async {
    // 이번 실행에서 이미 응답했다면 저장 성공 여부와 무관하게 다시 묻지 않는다.
    if (_answered) return;
    try {
      _answered = await store.hasAnswered();
    } on Object {
      _answered = false;
    }
    _loaded = true;
  }

  /// "모두 허용" — 마이크·카메라·알림을 차례로 요청하고 응답으로 기록한다.
  ///
  /// 결과(허용·거부)는 보지 않는다. 거부해도 앱은 그대로 진행하고, 그 권한이 실제로
  /// 필요한 순간에 기존 개별 요청이 다시 묻는다.
  Future<void> requestAll() async {
    // 한 번에 하나씩 — Android는 권한 대화상자를 동시에 띄우지 못한다.
    // Android 13(API 33) 미만에서는 알림이 런타임 권한이 아니라 대화상자 없이
    // 즉시 결과가 온다. 결과를 화면에 단정해 보여주지 않는 것도 그래서다.
    await _request(microphonePermissionService.request);
    await _request(
      () => photoPermissionService.request(PhotoPermissionKind.camera),
    );
    await _request(pushPermissionService.request);
    await _remember();
  }

  /// "나중에" — 아무것도 요청하지 않고 응답으로만 기록한다.
  Future<void> skip() => _remember();

  Future<void> _request(Future<Object?> Function() request) async {
    try {
      await request();
    } on Object {
      // 권한 요청 실패는 앱 진행을 막지 않는다. 다음 권한도 계속 묻는다.
    }
  }

  Future<void> _remember() async {
    // 먼저 메모리에 걸어 둔다. 저장이 실패해도 이번 실행에서는 다시 묻지 않는다.
    _answered = true;
    _loaded = true;
    try {
      await store.markAnswered();
    } on Object {
      // 저장 실패로 화면 진행을 막지 않는다.
    }
  }
}
