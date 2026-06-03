import 'dart:convert';

import 'package:http/http.dart' as http;

const jsonUtf8ContentType = 'application/json; charset=utf-8';
const jsonAcceptHeader = 'application/json';

String encodeJsonBody(Object? value) => jsonEncode(value);

String decodeUtf8Body(http.Response response) {
  return utf8.decode(response.bodyBytes, allowMalformed: false);
}

Object? decodeJsonBody(http.Response response) {
  final body = decodeUtf8Body(response);
  if (body.trim().isEmpty) return null;
  return jsonDecode(body);
}
