import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../../core/network/network.dart';
import '../../domain/models/voice_answer_audio.dart';
import '../../domain/repositories/voice_answer_playback_repository.dart';

const int _maxVoiceAnswerBytes = 20 * 1024 * 1024;
const Set<String> _supportedAudioTypes = {
  'audio/webm',
  'audio/mp4',
  'audio/wav',
  'audio/mpeg',
};

/// 보호자 소유권을 검증하는 Backend proxy에서 음성 답변을 내려받는다.
///
/// 외부 URL을 받거나 따라가지 않고 [messageId]로 고정된 동일 API origin의
/// 상대 경로만 사용하므로 JWT가 외부 host로 전달되지 않는다.
final class RemoteVoiceAnswerPlaybackRepository
    implements VoiceAnswerPlaybackRepository {
  const RemoteVoiceAnswerPlaybackRepository(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<VoiceAnswerAudio> loadVoiceAnswerAudio(
    int messageId, {
    VoiceAnswerPlaybackCancellation? cancellation,
  }) async {
    if (messageId <= 0) {
      throw const VoiceAnswerPlaybackValidationFailure(
        VoiceAnswerPlaybackValidationReason.invalidMessageId,
      );
    }
    final cancelToken = CancelToken();
    var settled = false;
    final cancelFuture = cancellation?.whenCancelled;
    if (cancelFuture != null) {
      unawaited(
        cancelFuture.then((_) {
          if (!settled && !cancelToken.isCancelled) cancelToken.cancel();
        }),
      );
    }
    if (cancellation?.isCancelled ?? false) cancelToken.cancel();

    try {
      final response = await _apiClient.get<ResponseBody>(
        'conversation-messages/$messageId/audio',
        options: Options(
          responseType: ResponseType.stream,
          headers: const {'Accept': 'audio/*'},
        ),
        cancelToken: cancelToken,
      );
      final body = response.data;
      if (body == null) {
        throw const VoiceAnswerPlaybackValidationFailure(
          VoiceAnswerPlaybackValidationReason.invalidResponse,
        );
      }
      final mimeType = _validatedMimeType(response.headers);
      final contentLength = _contentLength(response.headers);
      if (contentLength == 0) {
        throw const VoiceAnswerPlaybackValidationFailure(
          VoiceAnswerPlaybackValidationReason.emptyAudio,
        );
      }
      if (contentLength != null && contentLength > _maxVoiceAnswerBytes) {
        cancelToken.cancel();
        throw const VoiceAnswerPlaybackValidationFailure(
          VoiceAnswerPlaybackValidationReason.tooLarge,
        );
      }

      final bytes = BytesBuilder(copy: false);
      await for (final chunk in body.stream) {
        if (cancellation?.isCancelled ?? false) {
          throw const ApiTransportFailure(
            type: ApiTransportFailureType.cancelled,
          );
        }
        if (bytes.length > _maxVoiceAnswerBytes - chunk.length) {
          cancelToken.cancel();
          throw const VoiceAnswerPlaybackValidationFailure(
            VoiceAnswerPlaybackValidationReason.tooLarge,
          );
        }
        bytes.add(chunk);
      }
      if (bytes.isEmpty) {
        throw const VoiceAnswerPlaybackValidationFailure(
          VoiceAnswerPlaybackValidationReason.emptyAudio,
        );
      }
      return VoiceAnswerAudio(bytes: bytes.takeBytes(), mimeType: mimeType);
    } on VoiceAnswerPlaybackValidationFailure {
      rethrow;
    } on ApiFailure {
      rethrow;
    } on DioException catch (caught) {
      if (cancellation?.isCancelled ?? false) {
        throw const ApiTransportFailure(
          type: ApiTransportFailureType.cancelled,
        );
      }
      throw ApiTransportFailure(
        type: _transportFailureType(caught.type),
        cause: caught.error ?? caught,
      );
    } on Object catch (caught) {
      if (cancellation?.isCancelled ?? false) {
        throw const ApiTransportFailure(
          type: ApiTransportFailureType.cancelled,
        );
      }
      throw ApiTransportFailure(
        type: ApiTransportFailureType.unknown,
        cause: caught,
      );
    } finally {
      settled = true;
    }
  }
}

ApiTransportFailureType _transportFailureType(DioExceptionType type) =>
    switch (type) {
      DioExceptionType.connectionTimeout =>
        ApiTransportFailureType.connectionTimeout,
      DioExceptionType.sendTimeout => ApiTransportFailureType.sendTimeout,
      DioExceptionType.receiveTimeout => ApiTransportFailureType.receiveTimeout,
      DioExceptionType.transformTimeout =>
        ApiTransportFailureType.transformTimeout,
      DioExceptionType.connectionError => ApiTransportFailureType.connection,
      DioExceptionType.cancel => ApiTransportFailureType.cancelled,
      DioExceptionType.badCertificate ||
      DioExceptionType.badResponse ||
      DioExceptionType.unknown => ApiTransportFailureType.unknown,
    };

String _validatedMimeType(Headers headers) {
  final mimeType = headers
      .value(Headers.contentTypeHeader)
      ?.split(';')
      .first
      .trim()
      .toLowerCase();
  if (mimeType == null || !_supportedAudioTypes.contains(mimeType)) {
    throw const VoiceAnswerPlaybackValidationFailure(
      VoiceAnswerPlaybackValidationReason.unsupportedMimeType,
    );
  }
  return mimeType;
}

int? _contentLength(Headers headers) {
  final value = headers.value(Headers.contentLengthHeader);
  if (value == null) return null;
  final parsed = int.tryParse(value);
  if (parsed == null || parsed < 0) {
    throw const VoiceAnswerPlaybackValidationFailure(
      VoiceAnswerPlaybackValidationReason.invalidResponse,
    );
  }
  return parsed;
}
