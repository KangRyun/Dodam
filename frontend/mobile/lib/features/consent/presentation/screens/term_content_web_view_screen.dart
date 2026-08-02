import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../../design_system/design_system.dart';

/// 약관 웹뷰 안에서 이동을 허용할 주소인지 판단한다.
///
/// 처음 연 약관 주소와 같은 사이트(http·https + 같은 호스트)만 앱 안에서 연다.
/// 앱에는 외부 브라우저로 넘길 수단이 없어(외부 링크용 의존성 미사용) 바깥
/// 주소는 열지 않고 막는다. 막지 않으면 약관 제목을 단 상단바 아래에서 임의의
/// 외부 페이지가 열려 피싱 화면과 구분되지 않는다.
///
/// `www.`만 다른 호스트는 같은 사이트로 본다. 약관 페이지가 apex와 www 사이를
/// 리다이렉트하는 경우가 흔해서다. 포트는 비교하지 않는다. http(80)에서
/// https(443)로 올려 보내는 리다이렉트가 기본 포트 차이로 막히기 때문이다.
bool allowsTermContentNavigation({
  required Uri initial,
  required String requestUrl,
}) {
  final target = Uri.tryParse(requestUrl);
  if (target == null) return false;
  if (target.scheme != 'http' && target.scheme != 'https') return false;
  final host = _siteHost(target);
  if (host.isEmpty) return false;
  return host == _siteHost(initial);
}

String _siteHost(Uri uri) {
  final host = uri.host.toLowerCase();
  return host.startsWith('www.') ? host.substring(4) : host;
}

/// 약관 전문(원문 URL)을 앱 안에서 보여주는 화면.
///
/// 서버가 약관 본문(`contentHtml`) 없이 원문 주소(`contentUrl`)만 내려주는 약관에
/// 쓴다. 약관 원문은 로그인 없이 열람하는 공개 문서라 커뮤니티 웹뷰와 달리 액세스
/// 토큰을 주입하지 않는다.
class TermContentWebViewScreen extends StatefulWidget {
  const TermContentWebViewScreen({
    required this.title,
    required this.url,
    super.key,
  });

  /// 상단바에 표시할 약관 제목.
  final String title;

  /// 열어 볼 약관 원문 주소. 호출부에서 http(s) 여부를 이미 검증한 값을 받는다.
  final Uri url;

  @override
  State<TermContentWebViewScreen> createState() =>
      _TermContentWebViewScreenState();
}

class _TermContentWebViewScreenState extends State<TermContentWebViewScreen> {
  late final WebViewController _controller;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      // 약관 페이지가 스크립트로 본문을 그리는 경우가 있어 JS는 켠 채로 둔다.
      // JS 채널·토큰·쿠키를 주입하지 않아 앱으로 이어지는 통로가 없고, 바깥
      // 주소로 나가는 길은 아래 onNavigationRequest가 막는다.
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            if (allowsTermContentNavigation(
              initial: widget.url,
              requestUrl: request.url,
            )) {
              return NavigationDecision.navigate;
            }
            _notifyBlocked();
            return NavigationDecision.prevent;
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (error) {
            // 파비콘 등 서브리소스 실패는 무시하고 메인 프레임 실패만 노출한다.
            if (error.isForMainFrame ?? true) {
              if (mounted) {
                setState(() {
                  _failed = true;
                  _loading = false;
                });
              }
            }
          },
        ),
      );
    _load();
  }

  /// 바깥 주소로 나가려는 시도를 막았을 때 알린다.
  ///
  /// 첫 로딩 중에 막혔다면(예: 약관 주소가 다른 사이트로 리다이렉트) 빈 화면에
  /// 로딩만 계속 도는 상태가 되므로 오류 화면으로 전환해 다시 시도할 길을 준다.
  void _notifyBlocked() {
    if (!mounted) return;
    showAppMessage(
      context,
      message: '약관 페이지 밖 주소는 앱에서 열 수 없어요.',
      type: AppMessageType.warning,
    );
    if (_loading) {
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  Future<void> _load() async {
    try {
      await _controller.loadRequest(widget.url);
    } on Object {
      if (mounted) {
        setState(() {
          _failed = true;
          _loading = false;
        });
      }
    }
  }

  Future<void> _reload() async {
    setState(() {
      _failed = false;
      _loading = true;
    });
    await _load();
  }

  @override
  Widget build(BuildContext context) => TermContentView(
    title: widget.title,
    webView: WebViewWidget(controller: _controller),
    loading: _loading,
    failed: _failed,
    onRetry: _reload,
  );
}

/// 약관 웹뷰 화면의 표시 부분.
///
/// 웹뷰 위젯을 주입받아 상단바·로딩·오류 상태만 그린다. 웹뷰 자체는 플랫폼
/// 구현이 있어야 만들 수 있어, 이 위젯을 분리해 두면 위젯 테스트에서 대체
/// 위젯을 넣고 화면 전이를 확인할 수 있다.
class TermContentView extends StatelessWidget {
  const TermContentView({
    required this.title,
    required this.webView,
    required this.loading,
    required this.failed,
    required this.onRetry,
    super.key,
  });

  final String title;
  final Widget webView;
  final bool loading;
  final bool failed;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.canvas,
    appBar: AppTopBar(
      title: title,
      onBack: () => Navigator.of(context).maybePop(),
    ),
    body: SafeArea(
      child: failed
          ? _TermContentError(onRetry: onRetry)
          : Stack(
              children: [
                webView,
                if (loading)
                  const ColoredBox(
                    key: ValueKey('term-content-loading'),
                    color: AppColors.canvas,
                    child: Center(child: CircularProgressIndicator()),
                  ),
              ],
            ),
    ),
  );
}

class _TermContentError extends StatelessWidget {
  const _TermContentError({required this.onRetry});

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
              '약관 전문을 불러오지 못했어요',
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
            AppButton(
              key: const ValueKey('term-content-retry'),
              label: '다시 시도',
              onPressed: onRetry,
            ),
          ],
        ),
      ),
    ),
  );
}
