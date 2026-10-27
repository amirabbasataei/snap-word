import 'package:dio/dio.dart';
import 'package:wordchain/core/network/api_endpoints.dart';
import 'package:wordchain/core/utils/error_messages.dart';

class WordSuggestionException implements Exception {
  final String message;
  final String code;
  const WordSuggestionException(this.message, {required this.code});
}

/// Why a player flags a word that is already in the dictionary.
enum WordFlagReason {
  notAWord('not_a_word', 'کلمه نیست'),
  inappropriate('inappropriate', 'نامناسب است');

  final String wire;
  final String label;
  const WordFlagReason(this.wire, this.label);
}

/// One of the player's own reports (`GET /words/suggestions/mine`).
class MyWordReport {
  final String word;
  final String kind; // add | remove
  final String status; // pending | approved | rejected
  final String outcome; // add | remove | ai_block | ''
  final bool rewarded;
  final DateTime? createdAt;

  const MyWordReport({
    required this.word,
    required this.kind,
    required this.status,
    this.outcome = '',
    this.rewarded = false,
    this.createdAt,
  });

  bool get isAdd => kind == 'add';

  factory MyWordReport.fromJson(Map<String, dynamic> json) => MyWordReport(
    word: json['word'] as String? ?? '',
    kind: json['kind'] as String? ?? 'add',
    status: json['status'] as String? ?? 'pending',
    outcome: json['outcome'] as String? ?? '',
    rewarded: json['rewarded'] as bool? ?? false,
    createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
  );
}

/// Reports to the server about the dictionary: a valid word it rejected, or a
/// word in it that should not be there. Guests may report (identified by the
/// analytics install id); a signed-in player's Bearer token attributes the
/// report — and the reward — to the account.
class WordSuggestionsRepository {
  final Dio _dio;
  final String Function() _installId;

  WordSuggestionsRepository({
    required Dio dio,
    required String Function() installId,
  }) : _dio = dio,
       _installId = installId;

  /// Suggests [word] for the dictionary. Returns true when this player had
  /// already reported it.
  Future<bool> suggestWord(String word) async {
    final data = await _post({'word': word, 'kind': 'add'});
    return data['already_reported'] as bool? ?? false;
  }

  /// Flags [word] (in the dictionary) for removal. Returns true when this
  /// player had already reported it.
  Future<bool> flagWord(String word, WordFlagReason reason) async {
    final data = await _post({
      'word': word,
      'kind': 'remove',
      'reason': reason.wire,
    });
    return data['already_reported'] as bool? ?? false;
  }

  Future<Map<String, dynamic>> _post(Map<String, dynamic> body) async {
    try {
      final response = await _dio.post(
        ApiEndpoints.wordSuggestions,
        data: {...body, 'install_id': _installId()},
      );
      return (response.data['data'] as Map<String, dynamic>?) ?? const {};
    } on DioException catch (e) {
      final code = apiErrorCode(e);
      throw WordSuggestionException(
        errorMessageFor(code, fallback: genericErrorMessage),
        code: code,
      );
    }
  }

  Future<List<MyWordReport>> mine() async {
    try {
      final response = await _dio.get(ApiEndpoints.myWordSuggestions);
      final data = response.data['data'] as Map<String, dynamic>?;
      return ((data?['items'] as List<dynamic>?) ?? const [])
          .map((e) => MyWordReport.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      final code = apiErrorCode(e);
      throw WordSuggestionException(
        errorMessageFor(code, fallback: genericErrorMessage),
        code: code,
      );
    }
  }
}
