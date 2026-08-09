import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dodam/design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 1×1 PNG. 실제로 디코딩되는 가장 작은 이미지다.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1Pe'
  'AAAADElEQVR42mP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC',
);

/// 백엔드(S15P11B209-665)가 확정한 그림 주소 형태.
const _validPath = '/api/v1/drawing-assets/12/file';

const _placeholderKey = ValueKey('test-placeholder');
const _loadingKey = ValueKey('authenticated-image-loading');
const _successKey = ValueKey('authenticated-image-success');

void main() {
  group('AuthenticatedImage', () {
    setUp(() {
      // 모든 테스트가 같은 바이트를 쓴다. 앞 테스트가 디코딩 도중에 화면에서
      // 내려가며 남긴 상태가 다음 테스트로 새지 않도록 캐시를 비운다.
      imageCache
        ..clear()
        ..clearLiveImages();
    });

    testWidgets('url이 없으면 내려받지 않고 자리표시자를 보여준다', (tester) async {
      final api = _FakeImageApi();
      await tester.pumpWidget(_host(url: null, fetcher: api.download));
      await tester.pump();

      expect(api.requested, isEmpty);
      expect(find.byKey(_placeholderKey), findsOneWidget);
      expect(find.byKey(_loadingKey), findsNothing);
    });

    testWidgets('빈 url도 내려받지 않고 자리표시자를 보여준다', (tester) async {
      final api = _FakeImageApi();
      await tester.pumpWidget(_host(url: '', fetcher: api.download));
      await tester.pump();

      expect(api.requested, isEmpty);
      expect(find.byKey(_placeholderKey), findsOneWidget);
      expect(find.byKey(_loadingKey), findsNothing);
    });

    testWidgets('그림 경로는 바이트를 내려받아 Image.memory로 보여준다', (tester) async {
      final api = _FakeImageApi();
      await tester.pumpWidget(_host(url: _validPath, fetcher: api.download));
      await tester.pump();

      expect(api.downloaded, [_validPath]);
      expect(find.byKey(_successKey), findsOneWidget);
      expect(find.byKey(_placeholderKey), findsNothing);
      final image = tester.widget<Image>(find.byKey(_successKey));
      expect(image.image, isA<MemoryImage>());
      expect((image.image as MemoryImage).bytes, _png);
    });

    // 인증 헤더가 실려 나가는 요청이므로, 우리 API를 가리키지 않는 주소는
    // 내려받기를 시도하지 않아야 한다.
    for (final (label, url) in const [
      ('절대 URL은', 'https://evil.example/api/v1/drawing-assets/12/file'),
      ('호스트를 바꿔치기한 주소는', '//evil.example/api/v1/drawing-assets/12/file'),
      ('질의가 붙은 주소는', '/api/v1/drawing-assets/12/file?token=abc'),
      ('조각이 붙은 주소는', '/api/v1/drawing-assets/12/file#fragment'),
      ('상위 경로를 타는 주소는', '/api/v1/drawing-assets/../../secrets'),
    ]) {
      testWidgets('$label 요청 전에 거부한다', (tester) async {
        final api = _FakeImageApi();
        await tester.pumpWidget(_host(url: url, fetcher: api.download));
        await tester.pump();

        expect(api.requested, isEmpty);
        expect(find.byKey(_placeholderKey), findsOneWidget);
        expect(find.byKey(_successKey), findsNothing);
      });
    }

    testWidgets('계약에 없는 경로는 네트워크 전에 거절되고 같은 자리표시자를 보여준다', (tester) async {
      const wrongEndpoint = '/api/v1/reports/9/file';
      final api = _FakeImageApi();
      await tester.pumpWidget(_host(url: wrongEndpoint, fetcher: api.download));
      await tester.pump();

      // 주소 형태 자체는 앱 내부 경로라 위젯은 넘긴다. 계약 위반은 그 다음
      // 경계(레포지토리)가 네트워크에 나가기 전에 잡는다.
      expect(api.requested, [wrongEndpoint]);
      expect(api.downloaded, isEmpty);
      expect(find.byKey(_placeholderKey), findsOneWidget);
    });

    for (final (label, failure) in [
      ('401', _badResponse(401)),
      ('404', _badResponse(404)),
      (
        '네트워크 오류',
        DioException(
          requestOptions: RequestOptions(path: _validPath),
          type: DioExceptionType.connectionError,
          error: 'connection failed',
        ),
      ),
      ('빈 응답', const FormatException('Activity image response is empty.')),
    ]) {
      testWidgets('$label 실패는 모두 같은 자리표시자를 보여준다', (tester) async {
        final api = _FakeImageApi(failure: failure);
        await tester.pumpWidget(_host(url: _validPath, fetcher: api.download));
        await tester.pump();

        expect(api.downloaded, [_validPath]);
        expect(find.byKey(_placeholderKey), findsOneWidget);
        expect(find.byKey(_successKey), findsNothing);
        expect(find.byKey(_loadingKey), findsNothing);
      });
    }

    testWidgets('내려받는 동안 로딩 자리를 보여준다', (tester) async {
      final pending = Completer<Uint8List>();
      final api = _FakeImageApi(pending: pending);
      await tester.pumpWidget(_host(url: _validPath, fetcher: api.download));
      await tester.pump();

      // 스켈레톤 시머는 끝나지 않는 애니메이션이다. 여기서 pumpAndSettle을
      // 쓰면 영원히 멈추지 않으므로 pump로만 진행한다.
      expect(find.byKey(_loadingKey), findsOneWidget);
      expect(find.byKey(_placeholderKey), findsNothing);

      pending.complete(_png);
      await tester.pump();
      expect(find.byKey(_successKey), findsOneWidget);
    });

    testWidgets('로딩과 성공에 Semantics를 제공한다', (tester) async {
      // 핸들 해제 검사는 tearDown보다 먼저 돌기 때문에 본문에서 직접 닫는다.
      final handle = tester.ensureSemantics();
      final pending = Completer<Uint8List>();
      final api = _FakeImageApi(pending: pending);
      await tester.pumpWidget(
        _host(
          url: _validPath,
          fetcher: api.download,
          semanticLabel: '도담이가 그린 그림',
        ),
      );
      await tester.pump();

      expect(find.bySemanticsLabel('도담이가 그린 그림 불러오는 중'), findsOneWidget);

      pending.complete(_png);
      await tester.pump();
      expect(find.bySemanticsLabel('도담이가 그린 그림'), findsOneWidget);

      handle.dispose();
    });

    testWidgets('textScale 2.0에서도 넘치지 않는다', (tester) async {
      final pending = Completer<Uint8List>();
      final api = _FakeImageApi(pending: pending);
      await tester.pumpWidget(
        _host(url: _validPath, fetcher: api.download, textScale: 2),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);

      pending.complete(_png);
      await tester.pump();
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(
        _host(url: null, fetcher: api.download, textScale: 2),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byKey(_placeholderKey), findsOneWidget);
    });

    testWidgets('url이 바뀌면 이전 응답을 버린다', (tester) async {
      final first = Completer<Uint8List>();
      final api = _FakeImageApi(pending: first);
      await tester.pumpWidget(_host(url: _validPath, fetcher: api.download));
      await tester.pump();

      final second = Completer<Uint8List>();
      api.pending = second;
      await tester.pumpWidget(
        _host(url: '/api/v1/drawing-assets/13/file', fetcher: api.download),
      );
      await tester.pump();

      // 늦게 도착한 이전 그림이 새 그림 자리를 차지해선 안 된다.
      first.complete(_png);
      await tester.pump();
      expect(find.byKey(_successKey), findsNothing);
      expect(find.byKey(_loadingKey), findsOneWidget);

      second.complete(_png);
      await tester.pump();
      expect(find.byKey(_successKey), findsOneWidget);
      expect(api.downloaded, [_validPath, '/api/v1/drawing-assets/13/file']);
    });

    testWidgets('화면에서 내린 뒤 응답이 와도 예외가 없다', (tester) async {
      final pending = Completer<Uint8List>();
      final api = _FakeImageApi(pending: pending);
      await tester.pumpWidget(_host(url: _validPath, fetcher: api.download));
      await tester.pump();
      expect(find.byKey(_loadingKey), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      pending.complete(_png);
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });
}

Widget _host({
  required String? url,
  required ImageByteFetcher fetcher,
  String? semanticLabel,
  double textScale = 1,
}) => MaterialApp(
  home: Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: Center(
        child: SizedBox(
          width: 120,
          height: 90,
          child: AuthenticatedImage(
            url: url,
            fetcher: fetcher,
            semanticLabel: semanticLabel,
            placeholderBuilder: (_) => const ColoredBox(
              key: _placeholderKey,
              color: Color(0xFFF2F2F2),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.image_outlined),
                  Flexible(
                    child: Text(
                      '그림 없음',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  ),
);

DioException _badResponse(int statusCode) {
  final options = RequestOptions(path: _validPath);
  return DioException(
    requestOptions: options,
    type: DioExceptionType.badResponse,
    response: Response<void>(requestOptions: options, statusCode: statusCode),
  );
}

/// [RemoteActivityRepository.downloadImage]와 같은 규칙으로 그림 주소를 검사하는
/// 대역. 계약에 맞지 않는 주소는 네트워크에 나가기 전에 거절한다.
final class _FakeImageApi {
  _FakeImageApi({this.failure, this.pending});

  static final _filePattern = RegExp(
    r'^/api/v1/drawing-assets/([1-9][0-9]*)/file$',
  );

  /// `downloadImage`까지 들어온 주소.
  final List<String> requested = [];

  /// 검사를 통과해 실제 내려받기까지 간 주소.
  final List<String> downloaded = [];

  final Object? failure;
  Completer<Uint8List>? pending;

  Future<Uint8List> download(String url) async {
    requested.add(url);
    if (!_filePattern.hasMatch(url)) throw ArgumentError.value(url, 'url');
    downloaded.add(url);
    if (pending case final pending?) return pending.future;
    if (failure case final failure?) throw failure;
    return _png;
  }
}
