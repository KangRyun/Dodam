import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../feedback/app_skeleton.dart';

/// 인증이 필요한 이미지 바이트를 가져오는 콜백. 실패 시 예외를 던진다.
typedef ImageByteFetcher = Future<Uint8List> Function(String url);

enum AuthenticatedImageStatus { empty, loading, success, failure }

/// 인증(Authorization 헤더)이 필요한 이미지를 [fetcher]로 내려받아
/// [Image.memory]로 표시하는 위젯.
///
/// `url`이 없거나(empty) 내려받기에 실패하면(failure) 항상 같은
/// [placeholderBuilder]를 보여준다 — 호출부가 "왜 못 보여줬는지"를
/// 구분해 알릴 필요가 없다는 기존 화면들의 규칙을 그대로 따른다.
///
/// 서버가 주는 그림 주소는 스킴·호스트 없는 앱 내부 경로다. 그 형태가 아닌
/// 주소는 [fetcher]를 부르지 않고 실패로 둔다([_isSafeApiPath]).
class AuthenticatedImage extends StatefulWidget {
  const AuthenticatedImage({
    required this.url,
    required this.fetcher,
    required this.placeholderBuilder,
    this.fit = BoxFit.cover,
    this.semanticLabel,
    super.key,
  });

  final String? url;
  final ImageByteFetcher fetcher;
  final BoxFit fit;
  final WidgetBuilder placeholderBuilder;

  /// 스크린리더가 읽을 그림 설명. 주지 않으면 그림을 장식으로 둔다.
  final String? semanticLabel;

  @override
  State<AuthenticatedImage> createState() => _AuthenticatedImageState();
}

class _AuthenticatedImageState extends State<AuthenticatedImage> {
  AuthenticatedImageStatus _status = AuthenticatedImageStatus.empty;
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(AuthenticatedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) _load();
  }

  Future<void> _load() async {
    final url = widget.url;
    if (url == null || url.isEmpty) {
      setState(() {
        _status = AuthenticatedImageStatus.empty;
        _bytes = null;
      });
      return;
    }
    // 보낼 수 없는 주소면 요청 자체를 만들지 않는다. 인증 헤더가 실려 나가는
    // 요청이라, 엉뚱한 곳을 가리키는 주소는 그림 한 장을 접는 편이 낫다.
    if (!_isSafeApiPath(url)) {
      setState(() {
        _status = AuthenticatedImageStatus.failure;
        _bytes = null;
      });
      return;
    }
    setState(() {
      _status = AuthenticatedImageStatus.loading;
      _bytes = null;
    });
    try {
      final bytes = await widget.fetcher(url);
      if (!mounted || widget.url != url) return;
      setState(() {
        _bytes = bytes;
        _status = AuthenticatedImageStatus.success;
      });
    } on Object {
      if (!mounted || widget.url != url) return;
      setState(() => _status = AuthenticatedImageStatus.failure);
    }
  }

  @override
  Widget build(BuildContext context) => switch (_status) {
    AuthenticatedImageStatus.empty ||
    AuthenticatedImageStatus.failure => widget.placeholderBuilder(context),
    // 스켈레톤 블록 자체는 장식이다. 스크린리더에는 무엇을 기다리는지만 알린다.
    AuthenticatedImageStatus.loading => Semantics(
      container: true,
      label: widget.semanticLabel == null
          ? '그림 불러오는 중'
          : '${widget.semanticLabel} 불러오는 중',
      child: ExcludeSemantics(
        child: LayoutBuilder(
          key: const ValueKey('authenticated-image-loading'),
          builder: (context, constraints) => AppSkeleton(
            width: constraints.hasBoundedWidth ? constraints.maxWidth : 48,
            height: constraints.hasBoundedHeight ? constraints.maxHeight : 48,
            borderRadius: BorderRadius.zero,
          ),
        ),
      ),
    ),
    AuthenticatedImageStatus.success => Image.memory(
      _bytes!,
      key: const ValueKey('authenticated-image-success'),
      fit: widget.fit,
      gaplessPlayback: true,
      semanticLabel: widget.semanticLabel,
      errorBuilder: (_, _, _) => widget.placeholderBuilder(context),
    ),
  };
}

/// [AuthenticatedImage]가 [ImageByteFetcher]에 넘겨도 되는 주소인지 본다.
///
/// 서버가 주는 그림 주소는 `/api/v1/...` 형태의 앱 내부 경로다. 스킴·호스트가
/// 붙은 절대 URL, 질의·조각이 달린 주소, 상위 경로(`..`) 참조는 우리 API가
/// 아닌 곳을 가리킬 수 있으므로 요청 전에 걸러낸다.
bool _isSafeApiPath(String url) {
  // `Uri`는 파싱할 때 `..`를 먼저 정리해 버린다. 상위 경로를 타려는 주소를
  // 알아보려면 원문 그대로를 봐야 한다.
  final rawSegments = url.split('/');
  if (rawSegments.contains('..') || rawSegments.contains('.')) return false;
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  if (uri.hasScheme || uri.hasAuthority || uri.hasQuery || uri.hasFragment) {
    return false;
  }
  return uri.path.isNotEmpty;
}
