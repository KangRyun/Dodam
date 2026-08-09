Map<String, dynamic> jsonObject(Object? value) {
  return Map<String, dynamic>.from(value! as Map);
}

List<Map<String, dynamic>> jsonObjectList(Object? value) {
  return (value! as List<dynamic>)
      .map((item) => Map<String, dynamic>.from(item as Map))
      .toList(growable: false);
}

/// Backend success responses arrive wrapped in the common envelope
/// `{success, code, message, data}` (S15P11B209-133). The helpers below
/// extract the `data` payload, falling back to the raw body when the
/// envelope is absent so mock fixtures and unwrapped responses keep working.
Map<String, dynamic> envelopeObject(Object? body) {
  final map = jsonObject(body);
  return map['data'] is Map ? jsonObject(map['data']) : map;
}

List<dynamic> envelopeList(Object? body) {
  if (body is Map && body['data'] is List) {
    return body['data']! as List<dynamic>;
  }
  return body! as List<dynamic>;
}
