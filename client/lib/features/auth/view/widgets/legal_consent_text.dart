import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:wordchain/core/services/legal_links.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/widgets/legal_doc_opener.dart';

/// «با ورود، قوانین و حریم خصوصی زنجیر را می‌پذیرم.» — the two nouns are
/// links to the public Terms and Privacy pages (opened in the browser).
///
/// They are inline links inside a sentence, so their hit area follows the line
/// height (WCAG 2.5.8 exempts inline targets); the line height is raised a
/// little to make them easier to hit.
class LegalConsentText extends StatefulWidget {
  const LegalConsentText({super.key});

  @override
  State<LegalConsentText> createState() => _LegalConsentTextState();
}

class _LegalConsentTextState extends State<LegalConsentText> {
  late final TapGestureRecognizer _terms;
  late final TapGestureRecognizer _privacy;

  @override
  void initState() {
    super.initState();
    _terms =
        TapGestureRecognizer()
          ..onTap = () => openLegalDoc(context, LegalDoc.terms);
    _privacy =
        TapGestureRecognizer()
          ..onTap = () => openLegalDoc(context, LegalDoc.privacy);
  }

  @override
  void dispose() {
    _terms.dispose();
    _privacy.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final link = TextStyle(
      color: context.zs.indigoInk,
      fontWeight: FontWeight.w800,
      decoration: TextDecoration.underline,
      decorationColor: context.zs.indigoInk,
    );
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.6,
      child: Text.rich(
        TextSpan(
          style: ZTypography.metaLabel.copyWith(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            height: 1.9,
            color: z.ink60,
          ),
          children: [
            const TextSpan(text: 'با ورود، '),
            TextSpan(text: 'قوانین', style: link, recognizer: _terms),
            const TextSpan(text: ' و '),
            TextSpan(text: 'حریم خصوصی', style: link, recognizer: _privacy),
            const TextSpan(text: ' زنجیر را می‌پذیرم.'),
          ],
        ),
      ),
    );
  }
}
