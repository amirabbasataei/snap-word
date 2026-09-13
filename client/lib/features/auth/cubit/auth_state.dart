part of 'auth_cubit.dart';

abstract class AuthState extends Equatable {
  const AuthState();

  @override
  List<Object?> get props => [];
}

class AuthInitial extends AuthState {
  const AuthInitial();
}

class AuthLoading extends AuthState {
  const AuthLoading();
}

class AuthGuest extends AuthState {
  const AuthGuest();
}

class AuthAuthenticated extends AuthState {
  final String userId;
  final String username;
  final int coins;

  const AuthAuthenticated({
    required this.userId,
    required this.username,
    this.coins = 0,
  });

  AuthAuthenticated copyWith({int? coins}) => AuthAuthenticated(
        userId: userId,
        username: username,
        coins: coins ?? this.coins,
      );

  @override
  List<Object?> get props => [userId, username, coins];
}

class AuthError extends AuthState {
  final String message;

  const AuthError(this.message);

  @override
  List<Object?> get props => [message];
}
