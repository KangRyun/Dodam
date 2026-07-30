import '../../../core/network/network.dart';

/// 서로 다른 Backend 멱등성 Store의 409 의미를 섞지 않기 위한 endpoint 구분.
enum ConversationRequestEndpoint {
  conversationStart,
  nextQuestion,
  optionAnswer,
  voiceAnswer,
  questionSkip,
  conversationEnd,
}

/// 대화 쓰기 요청의 실패를 "서버가 저장했을 수도 있는가"로 나눈다.
///
/// 백엔드의 모든 대화 쓰기 endpoint는 `Idempotency-Key`와 요청 Body의 SHA-256
/// fingerprint를 함께 저장하고, 같은 Key에 다른 fingerprint가 오면
/// `IDEMPOTENCY_KEY_REUSED`(409)로 거절한다. 따라서 Key와 Body는 항상 하나의
/// snapshot으로 움직여야 한다.
///
/// * `true`  — 연결·timeout·5xx·분류 불가. 서버가 이미 저장했을 수 있으므로
///   **같은 snapshot으로만** 재시도한다. 다른 Body로 바꾸면 중복 답변이 남는다.
/// * `false` — 401·403·404·검증 오류. 서버가 저장 전에 거절한 것이 확정이므로
///   snapshot을 버리고 새 요청(새 Key)을 만들어도 안전하다. 같은 Body 재시도는
///   결과가 같으므로 제공하지 않는다.
bool isOutcomeUncertain(Object? failure) =>
    ApiFailurePresentation.of(failure).canRetry;

/// 같은 Key·Body 재시도로 완료 응답을 회수할 수 있는 대화 처리 충돌인지.
///
/// Backend가 처리 중 대기 만료에 전용 wire code를 쓰는 endpoint만 허용한다.
/// `CONVERSATION_409_002`는 next-question의 실제 저장 충돌에도 함께 쓰여
/// 구분할 수 없고, `OPTION_ANSWER_STORAGE_CONFLICT`는 완료 409로 저장·재생된다.
/// `QUESTION_STORAGE_CONFLICT`는 wire code가 아닌 Backend enum 이름이다.
const _processingConflictCodes = {
  ConversationRequestEndpoint.conversationStart: {
    'CONVERSATION_START_CONFLICT',
  },
  ConversationRequestEndpoint.nextQuestion: <String>{},
  ConversationRequestEndpoint.optionAnswer: <String>{},
  ConversationRequestEndpoint.voiceAnswer: {'VOICE_ANSWER_IN_PROGRESS'},
  ConversationRequestEndpoint.questionSkip: {'QUESTION_SKIP_CONFLICT'},
  ConversationRequestEndpoint.conversationEnd: {'CONVERSATION_END_CONFLICT'},
};

/// 처리 충돌이라 같은 snapshot 재시도로 회복할 수 있는 실패인지.
bool isProcessingConflict(
  Object? failure, {
  required ConversationRequestEndpoint endpoint,
}) =>
    failure is ApiResponseFailure &&
    failure.statusCode == 409 &&
    _processingConflictCodes[endpoint]!.contains(failure.error?.code);

/// 재시도 조작을 제공해도 되는 실패인지.
///
/// 불확실한 실패(같은 snapshot 재시도 안전)와 처리 충돌(응답 회수 가능)만
/// 허용한다. 그 밖의 확정 실패에는 같은 버튼을 다시 누를 수 없게 한다.
///
/// `cancelled`는 서버 결과가 불확실하지만 화면 이탈 등에서 발생하므로 공통 UI
/// 정책대로 즉시 재시도 버튼은 제공하지 않는다.
bool canRetryConversationRequest(
  Object? failure, {
  required ConversationRequestEndpoint endpoint,
}) =>
    isOutcomeUncertain(failure) ||
    isProcessingConflict(failure, endpoint: endpoint);

/// 보류 중인 Key·Body snapshot을 그대로 들고 있어야 하는 실패인지.
///
/// UI 버튼 노출과 별개다. `cancelled`도 POST가 서버에 도달했을 수 있으므로
/// snapshot을 보존한다. 모호한 `CONVERSATION_409_002`도 자동 재시도는 막되,
/// 처리 중이었을 가능성 때문에 Key·Body는 바꾸지 않는다.
bool shouldKeepRequestSnapshot(
  Object? failure, {
  required ConversationRequestEndpoint endpoint,
}) =>
    canRetryConversationRequest(failure, endpoint: endpoint) ||
    _isCancelled(failure) ||
    _isAmbiguousNextQuestionConflict(failure, endpoint);

/// 인증·권한·대상·안전 정책이 바뀌기 전에는 같은 화면 조작으로 해결되지 않는 오류.
///
/// Controller를 직접 호출해도 재요청하지 않도록 UI 차단과 별도로 사용한다.
bool blocksConversationAction(Object? failure) =>
    failure is ApiResponseFailure &&
    const {401, 403, 404, 422}.contains(failure.statusCode);

/// 서버에서 이미 종료된 대화임을 명시한 응답인지.
bool isConversationAlreadyCompleted(Object? failure) =>
    failure is ApiResponseFailure &&
    failure.error?.code == 'CONVERSATION_ALREADY_COMPLETED';

bool _isCancelled(Object? failure) =>
    failure is ApiTransportFailure &&
    failure.type == ApiTransportFailureType.cancelled;

bool _isAmbiguousNextQuestionConflict(
  Object? failure,
  ConversationRequestEndpoint endpoint,
) =>
    endpoint == ConversationRequestEndpoint.nextQuestion &&
    failure is ApiResponseFailure &&
    failure.statusCode == 409 &&
    failure.error?.code == 'CONVERSATION_409_002';
