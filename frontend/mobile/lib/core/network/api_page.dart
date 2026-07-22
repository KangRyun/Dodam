/// Pagination response defined by API common contract v1.0.
final class ApiPage<T> {
  const ApiPage({
    required this.content,
    required this.page,
    required this.size,
    required this.totalElements,
    required this.totalPages,
    required this.hasNext,
  });

  factory ApiPage.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic> json) itemFromJson,
  ) {
    return ApiPage<T>(
      content: (json['content'] as List<dynamic>)
          .map((item) => itemFromJson(item as Map<String, dynamic>))
          .toList(growable: false),
      page: json['page'] as int,
      size: json['size'] as int,
      totalElements: json['totalElements'] as int,
      totalPages: json['totalPages'] as int,
      hasNext: json['hasNext'] as bool,
    );
  }

  final List<T> content;
  final int page;
  final int size;
  final int totalElements;
  final int totalPages;
  final bool hasNext;
}
