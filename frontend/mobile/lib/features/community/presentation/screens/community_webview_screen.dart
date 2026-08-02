import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../../design_system/design_system.dart';

/// 커뮤니티 웹앱 주소. 기본값은 배포된 스테이징 웹이며, 로컬 확인 시
/// `--dart-define=COMMUNITY_WEB_URL=http://10.0.2.2:3000/community`로 바꾼다.
const String kCommunityWebUrl = String.fromEnvironment(
  'COMMUNITY_WEB_URL',
  defaultValue: 'https://i15b209.p.ssafy.io/community',
);

/// 커뮤니티 웹앱의 게시글 상세 주소를 만든다.
///
/// 웹앱 라우트는 `/community/posts/{postId}`이며 [kCommunityWebUrl]이 이미
/// `/community`까지 포함한다.
String communityPostUrl(String postId) =>
    '$kCommunityWebUrl/posts/${Uri.encodeComponent(postId)}';

/// 커뮤니티 웹앱을 웹뷰로 보여주는 화면.
///
/// 커뮤니티는 웹 전용이라(CLAUDE.md 6절) 앱은 웹앱을 그대로 띄운다. 로그인 토큰을
/// 웹앱이 읽는 키(`dodam.accessToken`)로 `localStorage`에 주입해, 웹앱이 같은
/// 토큰으로 백엔드를 호출하게 한다.
class CommunityWebView extends StatefulWidget {
  const CommunityWebView({
    this.url = kCommunityWebUrl,
    this.accessTokenProvider,
    super.key,
  });

  final String url;

  /// 주입할 액세스 토큰을 돌려주는 함수. 주지 않거나 `null`이면 토큰 없이 로드한다.
  final Future<String?> Function()? accessTokenProvider;

  @override
  State<CommunityWebView> createState() => _CommunityWebViewState();
}

class _CommunityWebViewState extends State<CommunityWebView> {
  late final WebViewController _controller;
  bool _loading = true;
  String? _error;
  String? _token;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => _injectToken(),
          onPageFinished: (_) {
            _injectToken();
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (error) {
            // 파비콘 등 서브리소스 실패는 무시하고 메인 프레임 실패만 노출한다.
            if (error.isForMainFrame ?? true) {
              if (mounted) {
                setState(() {
                  _error = error.description;
                  _loading = false;
                });
              }
            }
          },
        ),
      );
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      _token = await widget.accessTokenProvider?.call();
    } on Object {
      _token = null;
    }
    await _controller.loadRequest(Uri.parse(widget.url));
  }

  /// 웹앱 api-client가 읽는 `localStorage` 키에 앱 로그인 토큰을 심는다.
  ///
  /// 페이지 초기 타이밍에 따라 실패할 수 있어 `onPageStarted`와 `onPageFinished`
  /// 양쪽에서 시도한다.
  Future<void> _injectToken() async {
    final token = _token;
    if (token == null || token.isEmpty) return;
    final value = jsonEncode(token);
    try {
      await _controller.runJavaScript(
        "try { window.localStorage.setItem('dodam.accessToken', $value); } "
        'catch (e) {}',
      );
    } on Object {
      // 다음 콜백에서 재시도한다.
    }
  }

  Future<void> _reload() async {
    setState(() {
      _error = null;
      _loading = true;
    });
    await _controller.reload();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return _CommunityWebError(onRetry: _reload);
    }
    return Stack(
      children: [
        WebViewWidget(controller: _controller),
        if (_loading)
          const ColoredBox(
            color: AppColors.canvas,
            child: Center(child: CircularProgressIndicator()),
          ),
      ],
    );
  }
}

class _CommunityWebError extends StatelessWidget {
  const _CommunityWebError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: AppColors.canvas,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.wifi_off_rounded,
              size: 48,
              color: AppColors.inkMuted,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              '커뮤니티를 불러오지 못했어요',
              style: AppTypography.bodyStrong,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs),
            const Text(
              '네트워크 상태를 확인한 뒤 다시 시도해 주세요.',
              style: AppTypography.bodySm,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            AppButton(label: '다시 시도', onPressed: onRetry),
          ],
        ),
      ),
    ),
  );
}

/// 상단바를 갖춘 독립 화면 형태(라우트 진입용).
class CommunityWebViewScreen extends StatelessWidget {
  const CommunityWebViewScreen({
    this.url = kCommunityWebUrl,
    this.accessTokenProvider,
    super.key,
  });

  /// 처음 열 주소. 알림에서 들어오면 게시글 상세 주소가 들어온다.
  final String url;

  final Future<String?> Function()? accessTokenProvider;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.canvas,
    appBar: AppTopBar(
      title: '커뮤니티',
      onBack: () => Navigator.of(context).maybePop(),
    ),
    body: SafeArea(
      child: CommunityWebView(
        url: url,
        accessTokenProvider: accessTokenProvider,
      ),
    ),
  );
}
