import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wordchain/features/words/data/word_suggestions_repository.dart';

enum MyWordReportsStatus { loading, loaded, failed }

class MyWordReportsState extends Equatable {
  final MyWordReportsStatus status;
  final List<MyWordReport> items;
  final String? message;

  const MyWordReportsState({
    this.status = MyWordReportsStatus.loading,
    this.items = const [],
    this.message,
  });

  @override
  List<Object?> get props => [status, items, message];
}

/// «پیشنهادهای من»: the signed-in player's own reports and their outcome.
class MyWordReportsCubit extends Cubit<MyWordReportsState> {
  final WordSuggestionsRepository _repository;

  MyWordReportsCubit(this._repository) : super(const MyWordReportsState());

  Future<void> load() async {
    emit(const MyWordReportsState());
    try {
      final items = await _repository.mine();
      if (isClosed) return;
      emit(
        MyWordReportsState(status: MyWordReportsStatus.loaded, items: items),
      );
    } on WordSuggestionException catch (e) {
      if (!isClosed) {
        emit(
          MyWordReportsState(
            status: MyWordReportsStatus.failed,
            message: e.message,
          ),
        );
      }
    }
  }
}
