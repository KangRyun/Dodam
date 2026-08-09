import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';
import '../screens/term_content_web_view_screen.dart';

/// 약관 전문 URL을 여는 동작. 기본 동작은 앱 안 웹뷰 화면으로 이동하는 것이다.
typedef TermUrlOpener =
    void Function(BuildContext context, String title, Uri url);

final RegExp _lineBreakTagPattern = RegExp('<br[^>]*>', caseSensitive: false);

/// 평문에서 줄을 바꿔야 하는 블록 레벨 태그. 여는 태그와 닫는 태그를 모두 줄바꿈
/// 하나로 바꾼다. `</p><p>` 처럼 두 경계가 맞닿으면 줄바꿈이 겹쳐 빈 줄이 생기고,
/// 그 빈 줄이 문단 구분이 된다. 경계가 한쪽만 있으면 줄만 바뀐다.
///
/// 태그 이름 뒤에 `[\s/>]`를 요구한다. 이것이 없으면 `<pre>`가 `p`로, `<progress>`가
/// `p`로 잡혀 인라인이 아닌 곳에서 줄이 끊긴다.
final RegExp _blockLevelTagPattern = RegExp(
  r'</?(?:'
  r'p|div|section|article|header|footer|blockquote|hr|h[1-6]|'
  r'ul|ol|dl|dt|dd|'
  r'table|thead|tbody|tfoot|tr|td|th'
  r')(?=[\s/>])[^>]*>',
  caseSensitive: false,
);

/// 목록 항목의 시작. 평문에는 목록 구조가 남지 않아 항목 경계가 사라지므로 불릿을
/// 붙인다. 줄바꿈은 [_listItemEndPattern]이 담당한다.
final RegExp _listItemStartPattern = RegExp(
  r'<li(?=[\s/>])[^>]*>',
  caseSensitive: false,
);

/// 목록 항목의 끝. 뒤따르는 공백까지 함께 먹는다. 원문이 `</li>` 다음 줄에 `<li>`를
/// 쓰더라도 항목 사이에 빈 줄이 생기지 않게 하려는 것이다.
final RegExp _listItemEndPattern = RegExp(r'</li\s*>\s*', caseSensitive: false);

final RegExp _remainingTagPattern = RegExp('<[^>]+>');

final RegExp _blankLineRunPattern = RegExp(r'\n{3,}');

/// 약관 본문(HTML)을 읽기 쉬운 평문으로 정리한다. 별도 HTML 렌더러 의존성 없이
/// 문단·항목·줄바꿈만 보존한다.
///
/// 블록 레벨 태그는 지우기 전에 줄바꿈으로 바꾸고, 인라인 태그(`b`·`strong`·`em`·
/// `span`·`a` 등)만 구분자 없이 지운다. 인라인까지 줄바꿈으로 바꾸면 강조가 들어간
/// 문장이 중간에서 쪼개진다.
///
/// 태그를 다 걷어낸 뒤에 HTML 엔티티를 되돌린다. 순서를 뒤집으면 `&lt;p&gt;`처럼
/// 이스케이프된 텍스트가 실제 태그로 되살아나 본문에서 사라진다.
String consentTermPlainText(String? html) {
  if (html == null) return '';
  return html
      .replaceAll(_lineBreakTagPattern, '\n')
      .replaceAll(_listItemEndPattern, '\n')
      .replaceAll(_listItemStartPattern, '• ')
      .replaceAll(_blockLevelTagPattern, '\n')
      .replaceAll(_remainingTagPattern, '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll(_blankLineRunPattern, '\n\n')
      .trim();
}

/// 약관 원문 주소를 열 수 있는 형태인지 확인해 [Uri]로 돌려준다.
///
/// 앱 안 웹뷰로 여는 값이므로 http·https 절대 주소만 허용한다. 비어 있거나
/// 형식이 잘못됐거나 다른 스킴이면 `null`을 돌려주고, 화면은 링크를 감춘다.
///
/// 스킴 유무는 [Uri.hasScheme]로 본다. [Uri.isAbsolute]는 fragment가 있으면
/// 무조건 `false`라서, 조항 앵커를 단 약관 주소(`.../terms#제3조`)까지 거른다.
Uri? consentTermContentUri(String? raw) {
  final value = raw?.trim();
  if (value == null || value.isEmpty) return null;
  final uri = Uri.tryParse(value);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  return uri;
}

/// 약관 원문을 앱 안 웹뷰로 연다. [openTermUrl]을 주면 그 동작으로 대체한다.
///
/// 웹뷰는 플랫폼 구현이 필요해 위젯 테스트에서 대체 동작을 넣는다.
void openConsentTermUrl(
  BuildContext context,
  String title,
  Uri url, {
  TermUrlOpener? openTermUrl,
}) {
  if (openTermUrl != null) {
    openTermUrl(context, title, url);
    return;
  }
  Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => TermContentWebViewScreen(title: title, url: url),
    ),
  );
}

/// 약관 한 건의 상세를 바텀시트로 보여준다.
///
/// 동의 관리(S15P11B209-706)와 약관 및 정책(S15P11B209-458)이 같은 상세 경로를
/// 쓰도록 한 곳에 모아 둔 표시 지점이다. 본문(HTML)이 있으면 시트 안에서 바로
/// 읽히므로 우선하고, 본문이 없을 때만 원문 주소로 넘어가며, 둘 다 없으면 안내
/// 문구를 보여준다. 어느 화면에서 열든 판정이 갈리지 않게 여기서만 분기한다.
Future<void> showConsentTermDetailSheet({
  required BuildContext context,
  required int termId,
  required String title,
  required bool required,
  required String version,
  String? contentHtml,
  String? contentUrl,
  TermUrlOpener? openTermUrl,
}) {
  final body = consentTermPlainText(contentHtml);
  final contentUri = body.isEmpty ? consentTermContentUri(contentUrl) : null;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppColors.surface,
    builder: (sheetContext) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      minChildSize: 0.3,
      builder: (context, scrollController) => ListView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          0,
          AppSpacing.xl,
          AppSpacing.xl,
        ),
        children: [
          Text(title, style: AppTypography.titleLg),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${required ? '필수' : '선택'}'
            '${version.isEmpty ? '' : ' · 버전 $version'}',
            style: AppTypography.bodySm,
          ),
          const SizedBox(height: AppSpacing.lg),
          if (contentUri != null) ...[
            const Text(
              '약관 전문은 웹 페이지에서 확인할 수 있어요.',
              style: TextStyle(color: AppColors.ink, height: 1.6),
            ),
            const SizedBox(height: AppSpacing.lg),
            AppButton(
              key: ValueKey('consent-detail-open-url-$termId'),
              label: '약관 전문 보기',
              onPressed: () => openConsentTermUrl(
                sheetContext,
                title,
                contentUri,
                openTermUrl: openTermUrl,
              ),
            ),
          ] else
            SelectableText(
              body.isEmpty ? '약관 상세 내용을 제공하지 않아요.' : body,
              style: const TextStyle(color: AppColors.ink, height: 1.6),
            ),
        ],
      ),
    ),
  );
}
