import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

enum InviteCodeStatus { loading, ready, failed }

class InviteCodeState extends Equatable {
  final InviteCodeStatus status;
  final String? code;

  const InviteCodeState._(this.status, this.code);
  const InviteCodeState.loading() : this._(InviteCodeStatus.loading, null);
  const InviteCodeState.ready(String code)
    : this._(InviteCodeStatus.ready, code);
  const InviteCodeState.failed() : this._(InviteCodeStatus.failed, null);

  @override
  List<Object?> get props => [status, code];
}

/// The player's own referral code (`GET /referral/me`) for the Friends tab's
/// share card. Best effort: a failure only turns the card into a retry, it
/// never blocks the screen.
class InviteCodeCubit extends Cubit<InviteCodeState> {
  final Future<String> Function() _fetch;

  InviteCodeCubit({required Future<String> Function() fetch})
    : _fetch = fetch,
      super(const InviteCodeState.loading());

  Future<void> load() async {
    emit(const InviteCodeState.loading());
    try {
      final code = await _fetch();
      if (isClosed) return;
      emit(
        code.isEmpty
            ? const InviteCodeState.failed()
            : InviteCodeState.ready(code),
      );
    } catch (_) {
      if (!isClosed) emit(const InviteCodeState.failed());
    }
  }
}
