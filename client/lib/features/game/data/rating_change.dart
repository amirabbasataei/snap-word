import 'package:equatable/equatable.dart';

/// One player's «جام» before and after a rated 1v1 match — a
/// `rating_update` entry (`{before, after, delta}`).
class RatingChange extends Equatable {
  final int before;
  final int after;
  final int delta;

  const RatingChange({
    required this.before,
    required this.after,
    required this.delta,
  });

  /// Null when [json] is not a well-formed entry.
  static RatingChange? tryParse(Object? json) {
    if (json is! Map) return null;
    final before = json['before'];
    final after = json['after'];
    final delta = json['delta'];
    if (before is! num || after is! num || delta is! num) return null;
    return RatingChange(
      before: before.toInt(),
      after: after.toInt(),
      delta: delta.toInt(),
    );
  }

  @override
  List<Object?> get props => [before, after, delta];
}
