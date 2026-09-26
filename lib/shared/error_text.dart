import '../data/api/api_exception.dart';
import '../l10n/app_localizations.dart';

/// What to tell the user about a failed request. Never blank.
///
/// The server's message when it sent one: it is already localised (§4). The
/// app's own network message when nothing came back — never the fallback a
/// provider had to pass without a `BuildContext`, which reached the screen as
/// the literal word "network". And the generic message when the server replied
/// without one (an HTML error page during a restart, an empty-bodied error),
/// since a notice with no words says nothing about what failed.
String describeError(Object error, AppLocalizations l10n) {
  if (error is! ApiException || error.isNetworkFailure) {
    return l10n.networkError;
  }
  return error.message.trim().isEmpty ? l10n.genericError : error.message;
}
