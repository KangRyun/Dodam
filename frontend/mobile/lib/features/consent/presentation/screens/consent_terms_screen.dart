import 'package:flutter/material.dart';

import '../../../../app/widgets/app_failure_view.dart';
import '../../../../design_system/design_system.dart';
import '../../../child/data/dto/child_consent_dtos.dart';
import '../../domain/repositories/consent_repository.dart';
import '../controllers/consent_terms_controller.dart';
import '../widgets/consent_section_card.dart';
import '../widgets/consent_term_detail_sheet.dart';

/// 서비스가 외부에 공표한 법적 고지 문서의 기본 주소.
///
/// 게이트웨이가 정적 파일로 서빙하며(`infra/nginx/conf.d/default.conf`의
/// `location /legal/`) 스토어 심사에 등록된 주소다. 로컬 확인 시
/// `--dart-define=LEGAL_WEB_URL=http://10.0.2.2:8080/legal`로 바꾼다.
const String kLegalDocumentBaseUrl = String.fromEnvironment(
  'LEGAL_WEB_URL',
  defaultValue: 'https://i15b209.p.ssafy.io/legal',
);

/// 정책 문서 [path]의 전체 주소.
///
/// [base] 끝의 `/`를 떼고 이어 붙인다. `--dart-define=LEGAL_WEB_URL=.../legal/`
/// 처럼 끝에 `/`가 붙은 값을 주면 `legal//privacy/`가 되어 404 웹뷰가 뜬다.
String legalDocumentUrl(String path, {String base = kLegalDocumentBaseUrl}) =>
    '${base.replaceAll(RegExp(r'/+$'), '')}/$path';

/// 앱에서 열어 주는 공표 정책 문서.
///
/// 동의 약관(`GET /consents/terms`)에 대응 항목이 **없는** 문서만 둔다. 서비스
/// 이용약관은 `SERVICE_TOS` 약관으로 목록에 이미 나오므로 여기 넣지 않는다.
/// 개인정보 처리방침은 동의 약관이 아니라 별도 고지 문서라 서버 목록에 없다.
const List<({String title, String description, String path})>
kLegalPolicyDocuments = [
  (
    title: '개인정보 처리방침',
    description: '수집 항목 · 이용 목적 · 보관과 파기 · 보호자의 권리',
    path: 'privacy/',
  ),
];

/// 설정 > 약관 및 정책.
///
/// 서비스에 적용 중인 약관과 공표된 정책 문서를 **읽기 전용**으로 보여준다.
/// 동의 여부를 조회하거나 바꾸지 않으므로 아동을 고르지 않아도 되고, 아이를
/// 등록하지 않은 계정도 아동 대상 약관 전문을 읽을 수 있다.
class ConsentTermsScreen extends StatefulWidget {
  const ConsentTermsScreen({
    required this.repository,
    this.openTermUrl,
    super.key,
  });

  final ConsentRepository repository;

  /// 원문 URL을 열 때 실행할 동작. 주지 않으면 앱 안 웹뷰로 이동한다.
  /// 웹뷰는 플랫폼 구현이 필요해 위젯 테스트에서 대체 동작을 넣는다.
  final TermUrlOpener? openTermUrl;

  @override
  State<ConsentTermsScreen> createState() => _ConsentTermsScreenState();
}

class _ConsentTermsScreenState extends State<ConsentTermsScreen> {
  late final ConsentTermsController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ConsentTermsController(widget.repository);
    _controller.load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _showTermDetail(ConsentTermDto term) {
    showConsentTermDetailSheet(
      context: context,
      termId: term.termId,
      title: term.title,
      required: term.required,
      version: term.version,
      contentHtml: term.contentHtml,
      contentUrl: term.contentUrl,
      openTermUrl: widget.openTermUrl,
    );
  }

  void _openPolicyDocument(String title, String path) {
    final url = consentTermContentUri(legalDocumentUrl(path));
    if (url == null) {
      showAppMessage(
        context,
        message: '$title 주소를 열 수 없어요.',
        type: AppMessageType.error,
      );
      return;
    }
    openConsentTermUrl(context, title, url, openTermUrl: widget.openTermUrl);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.canvas,
    appBar: AppTopBar(
      title: '약관 및 정책',
      onBack: () => Navigator.of(context).maybePop(),
    ),
    body: SafeArea(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppSizes.wideContentMaxWidth,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ConsentSectionCard(
                    key: const ValueKey('consent-terms-section'),
                    title: '약관',
                    child: _termsBody(),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  ConsentSectionCard(
                    key: const ValueKey('legal-documents-section'),
                    title: '정책 문서',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final document in kLegalPolicyDocuments)
                          _PolicyDocumentRow(
                            title: document.title,
                            description: document.description,
                            onTap: () => _openPolicyDocument(
                              document.title,
                              document.path,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _termsBody() => switch (_controller.status) {
    ConsentTermsStatus.loading => const Padding(
      key: ValueKey('consent-terms-loading'),
      padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
      child: Center(child: CircularProgressIndicator()),
    ),
    ConsentTermsStatus.error => AppFailureView(
      title: '약관 목록을 불러오지 못했어요',
      failure: _controller.error,
      onRetry: _controller.load,
    ),
    ConsentTermsStatus.ready =>
      _controller.terms.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Text(
                '표시할 약관이 없어요.',
                style: TextStyle(color: AppColors.inkMuted),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final group in _controller.groups) ...[
                  _GroupLabel(scope: group.scope),
                  for (final term in group.terms)
                    _TermRow(
                      term: term,
                      onTap: () => _showTermDetail(term),
                    ),
                ],
              ],
            ),
  };
}

/// 적용 범위 구분 라벨.
///
/// 아동 대상 약관은 보호자가 법정대리인으로서 동의하는 문서라 목록에 함께
/// 나온다. 무엇에 대한 약관인지 헷갈리지 않게 범위를 먼저 알린다.
class _GroupLabel extends StatelessWidget {
  const _GroupLabel({required this.scope});

  final ConsentTargetScope? scope;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(
      top: AppSpacing.xs,
      bottom: AppSpacing.xxs,
    ),
    child: Text(
      switch (scope) {
        ConsentTargetScope.user => '보호자 대상',
        ConsentTargetScope.child => '아동 대상',
        null => '기타',
      },
      style: AppTypography.bodySm.copyWith(fontWeight: FontWeight.w800),
    ),
  );
}

/// 약관 한 줄. 열람 전용이라 동의 토글을 두지 않는다.
class _TermRow extends StatelessWidget {
  const _TermRow({required this.term, required this.onTap});

  final ConsentTermDto term;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    key: ValueKey('consent-term-${term.termId}'),
    contentPadding: EdgeInsets.zero,
    title: Row(
      children: [
        Flexible(child: Text(term.title, style: AppTypography.bodyStrong)),
        const SizedBox(width: AppSpacing.xs),
        ConsentRequirementBadge(required: term.required),
      ],
    ),
    subtitle: term.version.isEmpty
        ? null
        : Text('버전 ${term.version}', style: AppTypography.bodySm),
    trailing: const Icon(
      Icons.chevron_right_rounded,
      color: AppColors.inkMuted,
    ),
    onTap: onTap,
  );
}

/// 공표 정책 문서 한 줄. 누르면 앱 안 웹뷰로 원문을 연다.
class _PolicyDocumentRow extends StatelessWidget {
  const _PolicyDocumentRow({
    required this.title,
    required this.description,
    required this.onTap,
  });

  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    key: ValueKey('legal-document-$title'),
    contentPadding: EdgeInsets.zero,
    title: Text(title, style: AppTypography.bodyStrong),
    subtitle: Text(description, style: AppTypography.bodySm),
    trailing: const Icon(
      Icons.open_in_new_rounded,
      color: AppColors.inkMuted,
    ),
    onTap: onTap,
  );
}
