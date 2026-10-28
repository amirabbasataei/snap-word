import 'package:flutter_test/flutter_test.dart';
import 'package:wordchain/core/network/dio_client.dart';
import 'package:wordchain/core/services/legal_links.dart';

void main() {
  test('URLs are the API host plus /terms and /privacy', () {
    final links = LegalLinks(baseUrl: 'https://example.test');
    expect(
      links.urlFor(LegalDoc.terms).toString(),
      'https://example.test/terms',
    );
    expect(
      links.urlFor(LegalDoc.privacy).toString(),
      'https://example.test/privacy',
    );
  });

  test('a trailing slash or a port in the base URL is handled', () {
    expect(
      LegalLinks(
        baseUrl: 'https://example.test/',
      ).urlFor(LegalDoc.terms).toString(),
      'https://example.test/terms',
    );
    expect(
      LegalLinks(
        baseUrl: 'http://10.0.2.2:8080',
      ).urlFor(LegalDoc.privacy).toString(),
      'http://10.0.2.2:8080/privacy',
    );
  });

  test('defaults to DioClient.baseUrl, so API_BASE_URL builds follow it', () {
    expect(
      LegalLinks().urlFor(LegalDoc.terms).toString(),
      '${DioClient.baseUrl}/terms',
    );
  });

  test('open() hands the URL to the opener and returns its result', () async {
    final opened = <Uri>[];
    final links = LegalLinks(
      baseUrl: 'https://example.test',
      opener: (u) async {
        opened.add(u);
        return true;
      },
    );
    expect(await links.open(LegalDoc.privacy), isTrue);
    expect(opened.single.toString(), 'https://example.test/privacy');
  });

  test(
    'open() is false when the browser did not launch, and never throws',
    () async {
      expect(
        await LegalLinks(opener: (_) async => false).open(LegalDoc.terms),
        isFalse,
      );
      expect(
        await LegalLinks(
          opener: (_) async => throw Exception('no handler'),
        ).open(LegalDoc.terms),
        isFalse,
      );
    },
  );
}
