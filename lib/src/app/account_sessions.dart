import '../protocol/models.dart';
import 'error_display.dart';

class AccountSessionsLoadPatch {
  const AccountSessionsLoadPatch({
    required this.sessions,
    required this.loading,
    required this.securityError,
  });

  final List<UserSession> sessions;
  final bool loading;
  final String? securityError;
}

AccountSessionsLoadPatch accountSessionsLoadStarted({
  required List<UserSession> sessions,
}) {
  return AccountSessionsLoadPatch(
    sessions: sessions,
    loading: true,
    securityError: null,
  );
}

AccountSessionsLoadPatch accountSessionsLoadSucceeded({
  required List<UserSession> sessions,
}) {
  return AccountSessionsLoadPatch(
    sessions: sessions,
    loading: false,
    securityError: null,
  );
}

AccountSessionsLoadPatch accountSessionsLoadCancelled({
  required List<UserSession> sessions,
  required String? securityError,
}) {
  return AccountSessionsLoadPatch(
    sessions: sessions,
    loading: false,
    securityError: securityError,
  );
}

AccountSessionsLoadPatch accountSessionsLoadFailed({
  required List<UserSession> sessions,
  required Object failure,
}) {
  return AccountSessionsLoadPatch(
    sessions: sessions,
    loading: false,
    securityError: userFacingErrorMessage(failure),
  );
}
