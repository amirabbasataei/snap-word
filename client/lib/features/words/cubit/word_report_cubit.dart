import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wordchain/core/services/analytics_service.dart';
import 'package:wordchain/features/words/data/word_suggestions_repository.dart';

enum WordReportStatus { idle, sending, sent, failed }

class WordReportState extends Equatable {
  final WordReportStatus status;

  /// Persian error text while [status] is failed.
  final String? message;

  /// The server said this player had already reported the word.
  final bool alreadyReported;

  const WordReportState({
    this.status = WordReportStatus.idle,
    this.message,
    this.alreadyReported = false,
  });

  bool get sending => status == WordReportStatus.sending;
  bool get sent => status == WordReportStatus.sent;

  @override
  List<Object?> get props => [status, message, alreadyReported];
}

/// One report to the server (add a missing word, or flag a bad one). Scoped to
/// the widget that sends it; [source] is where in the app it came from, for
/// analytics (`game_over`, `chain`, `profile`).
class WordReportCubit extends Cubit<WordReportState> {
  final WordSuggestionsRepository _repository;
  final String source;

  WordReportCubit(this._repository, {required this.source})
    : super(const WordReportState());

  /// «کلمه‌ام درسته»: suggests [word] for the dictionary.
  Future<void> suggest(String word) =>
      _send(() => _repository.suggestWord(word), kind: 'add');

  /// Flags [word], which the dictionary accepts, as wrong or inappropriate.
  Future<void> flag(String word, WordFlagReason reason) =>
      _send(() => _repository.flagWord(word, reason), kind: 'remove');

  Future<void> _send(
    Future<bool> Function() request, {
    required String kind,
  }) async {
    if (state.sending) return;
    emit(const WordReportState(status: WordReportStatus.sending));
    try {
      final already = await request();
      if (isClosed) return;
      trackEvent(AnalyticsEvent.wordSuggest, {'kind': kind, 'source': source});
      emit(
        WordReportState(
          status: WordReportStatus.sent,
          alreadyReported: already,
        ),
      );
    } on WordSuggestionException catch (e) {
      if (!isClosed) {
        emit(
          WordReportState(status: WordReportStatus.failed, message: e.message),
        );
      }
    }
  }

  /// Back to idle (e.g. to report another word from the same dialog).
  void reset() => emit(const WordReportState());
}
