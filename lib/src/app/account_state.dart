import '../protocol/models.dart';

class AccountLoadPatch {
  const AccountLoadPatch({
    required this.user,
    required this.loading,
    required this.accountError,
  });

  final CurrentUser? user;
  final bool loading;
  final String? accountError;
}

AccountLoadPatch accountLoadStarted({required CurrentUser? user}) {
  return AccountLoadPatch(user: user, loading: true, accountError: null);
}

AccountLoadPatch accountLoadSucceeded({required CurrentUser user}) {
  return AccountLoadPatch(user: user, loading: false, accountError: null);
}

AccountLoadPatch accountLoadCancelled({
  required CurrentUser? user,
  required String? accountError,
}) {
  return AccountLoadPatch(
    user: user,
    loading: false,
    accountError: accountError,
  );
}

AccountLoadPatch accountLoadFailed({
  required CurrentUser? user,
  required Object failure,
}) {
  return AccountLoadPatch(
    user: user,
    loading: false,
    accountError: failure.toString(),
  );
}
