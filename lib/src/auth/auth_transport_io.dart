import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

http.Client createEnvironmentProxyAuthHttpClient() {
  final client = HttpClient()
    ..findProxy = (uri) => HttpClient.findProxyFromEnvironment(uri);
  return IOClient(client);
}

bool isTlsHandshakeFailure(Object error) {
  if (error is HandshakeException) return true;
  return _looksLikeTlsHandshakeFailure(error);
}

bool _looksLikeTlsHandshakeFailure(Object error) {
  final message = error.toString().toLowerCase();
  return message.contains('handshakeexception') ||
      message.contains('handshake error') ||
      message.contains('tls handshake');
}
