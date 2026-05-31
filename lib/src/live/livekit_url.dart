String resolveLiveKitServerUrl({
  required String serverUrl,
  required String apiBaseUrl,
}) {
  final liveKitUri = Uri.tryParse(serverUrl);
  final apiUri = Uri.tryParse(apiBaseUrl);
  if (liveKitUri == null || apiUri == null) return serverUrl;
  if (liveKitUri.host.isEmpty || apiUri.host.isEmpty) return serverUrl;

  final host =
      _isLocalAdvertisedHost(liveKitUri.host) &&
          !_isLocalAdvertisedHost(apiUri.host)
      ? apiUri.host
      : liveKitUri.host;

  return liveKitUri
      .replace(scheme: _webSocketScheme(liveKitUri), host: host)
      .toString();
}

String _webSocketScheme(Uri uri) {
  if (uri.scheme == 'https' || uri.scheme == 'wss') return 'wss';
  return 'ws';
}

bool _isLocalAdvertisedHost(String host) {
  final normalized = host.toLowerCase();
  return normalized == 'localhost' ||
      normalized == '127.0.0.1' ||
      normalized == '::1' ||
      normalized == '0.0.0.0';
}
