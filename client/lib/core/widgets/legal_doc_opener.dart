import 'package:flutter/material.dart';
import 'package:wordchain/core/di/injection.dart';
import 'package:wordchain/core/services/legal_links.dart';
import 'package:wordchain/core/utils/error_messages.dart';
import 'package:wordchain/core/widgets/z_toast.dart';

/// Opens the Terms / Privacy page in the browser; a launch failure is a toast
/// (never an exception in the widget tree).
Future<void> openLegalDoc(BuildContext context, LegalDoc doc) async {
  final overlay = Overlay.of(context, rootOverlay: true);
  final opened = await getIt<LegalLinks>().open(doc);
  if (!opened && overlay.mounted) {
    ZToast.showOn(overlay, legalPageOpenFailedMessage, kind: ZToastKind.error);
  }
}
