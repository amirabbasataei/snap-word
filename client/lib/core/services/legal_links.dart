import 'package:logger/logger.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wordchain/core/network/dio_client.dart';

/// The two public documents the backend serves (`internal/legal`).
enum LegalDoc {
  terms('/terms'),
  privacy('/privacy');

  const LegalDoc(this.path);
  final String path;
}

typedef UrlOpener = Future<bool> Function(Uri url);

/// Opens the Terms / Privacy pages in the external browser. The pages live on
/// the API host, so the URL follows `API_BASE_URL` (a local-backend build
/// opens the local pages). `url_launcher` fires an Android intent / iOS
/// `openURL`; it needs no Google services.
class LegalLinks {
  final String _baseUrl;
  final UrlOpener _open;
  final Logger _log = Logger();

  LegalLinks({String? baseUrl, UrlOpener? opener})
    : _baseUrl = _trimSlash(baseUrl ?? DioClient.baseUrl),
      _open = opener ?? _launchExternally;

  static String _trimSlash(String s) =>
      s.endsWith('/') ? s.substring(0, s.length - 1) : s;

  static Future<bool> _launchExternally(Uri url) =>
      launchUrl(url, mode: LaunchMode.externalApplication);

  Uri urlFor(LegalDoc doc) => Uri.parse('$_baseUrl${doc.path}');

  /// True when the browser was launched. Never throws.
  Future<bool> open(LegalDoc doc) async {
    try {
      return await _open(urlFor(doc));
    } catch (e) {
      _log.w('Could not open ${doc.name}: $e');
      return false;
    }
  }
}
