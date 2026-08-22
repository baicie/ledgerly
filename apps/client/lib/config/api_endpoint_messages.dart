import '../l10n/l10n.dart';

String apiEndpointErrorText(Object error, [AppLocalizations? l10n]) {
  l10n ??= L10n.current;
  if (error is FormatException) {
    final message = error.message;
    if (message.contains('Release builds require')) {
      return l10n.requireHttpsLanOk;
    }
    if (message.contains('default HTTPS port')) {
      return l10n.webReleaseHttps443;
    }
    if (message.contains('origin without')) {
      return l10n.apiOriginOnly;
    }
    if (message.contains('must not be empty') || message.contains('required')) {
      return l10n.enterApiAddress;
    }
  }
  return l10n.invalidHttpApiAddress;
}
