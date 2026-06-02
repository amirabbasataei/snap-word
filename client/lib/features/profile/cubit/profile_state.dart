part of 'profile_cubit.dart';

abstract class ProfileState extends Equatable {
  const ProfileState();

  @override
  List<Object?> get props => [];
}

class ProfileInitial extends ProfileState {
  const ProfileInitial();
}

class ProfileLoading extends ProfileState {
  const ProfileLoading();
}

class ProfileLoaded extends ProfileState {
  final ProfileStats stats;
  final List<PowerupItem> powerups;
  final bool isGuest;

  const ProfileLoaded({
    required this.stats,
    required this.powerups,
    required this.isGuest,
  });

  @override
  List<Object?> get props => [stats, powerups, isGuest];
}

class ProfileError extends ProfileState {
  final String message;

  const ProfileError(this.message);

  @override
  List<Object?> get props => [message];
}
