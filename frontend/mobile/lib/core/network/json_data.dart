Map<String, dynamic> jsonObject(Object? value) {
  return Map<String, dynamic>.from(value! as Map);
}

List<Map<String, dynamic>> jsonObjectList(Object? value) {
  return (value! as List<dynamic>)
      .map((item) => Map<String, dynamic>.from(item as Map))
      .toList(growable: false);
}
