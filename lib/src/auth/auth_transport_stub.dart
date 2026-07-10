import 'package:http/http.dart' as http;

http.Client createEnvironmentProxyAuthHttpClient() => http.Client();

bool isTlsHandshakeFailure(Object error) {
  final message = error.toString().toLowerCase();
  return message.contains('handshakeexception') ||
      message.contains('handshake error') ||
      message.contains('tls handshake');
}
