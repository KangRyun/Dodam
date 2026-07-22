enum AuthProvider {
  kakao('KAKAO'),
  google('GOOGLE'),
  naver('NAVER');

  const AuthProvider(this.wireName);

  final String wireName;

  static AuthProvider fromWireName(String value) => values.firstWhere(
    (provider) => provider.wireName == value.toUpperCase(),
    orElse: () =>
        throw ArgumentError.value(value, 'value', '지원하지 않는 OAuth 제공자입니다.'),
  );
}
