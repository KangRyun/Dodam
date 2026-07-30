import 'package:flutter/foundation.dart';

import '../../../core/network/api_failure.dart';

// 대화 API 실패 원인을 개발 터미널에서 구분
void debugConversationFailure({
  required String operation,
  required Object error,
}) {
  if (!kDebugMode) return;

  switch (error) {
    case ApiResponseFailure(:final statusCode, :final error):
      debugPrint(
        '[CONVERSATION_FLOW] $operation failed '
        'status=${statusCode ?? 'unknown'} '
        'code=${error?.code ?? 'unknown'} '
        'message=${error?.message ?? 'unknown'}',
      );
    case ApiTransportFailure(:final type):
      debugPrint(
        '[CONVERSATION_FLOW] $operation failed '
        'transport=${type.name}',
      );
    default:
      debugPrint(
        '[CONVERSATION_FLOW] $operation failed '
        'exceptionType=${error.runtimeType}',
      );
  }
}
