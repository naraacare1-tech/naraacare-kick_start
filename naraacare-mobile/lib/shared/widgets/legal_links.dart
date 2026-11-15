import 'package:flutter/material.dart';
import 'package:naraacare/core/l10n/generated/app_localizations.dart';
import 'package:naraacare/shared/widgets/nc_toast.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens a legal document (Terms, Privacy, Licenses) in the external browser:
/// no WebView in the app (doc 07 SEC-2). Only https links from config or
/// GET /reference/policies are opened.
Future<void> openLegalLink(BuildContext context, Uri url) async {
  final message = AppLocalizations.of(context).linkOpenFailed;
  var opened = false;
  if (url.scheme == 'https') {
    try {
      opened = await launchUrl(url, mode: LaunchMode.externalApplication);
    } on Exception {
      opened = false;
    }
  }
  if (!opened && context.mounted) {
    showNcToast(context, message, kind: NcToastKind.error);
  }
}
