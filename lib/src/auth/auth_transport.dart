import 'package:http/http.dart' as http;

import 'auth_transport_stub.dart'
    if (dart.library.io) 'auth_transport_io.dart'
    as platform;

typedef AuthHttpClientFactory = http.Client Function();

http.Client createEnvironmentProxyAuthHttpClient() {
  return platform.createEnvironmentProxyAuthHttpClient();
}

bool isTlsHandshakeFailure(Object error) {
  return platform.isTlsHandshakeFailure(error);
}
