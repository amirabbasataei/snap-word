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
  final PremiumPerks perks;

  const ProfileLoaded({
    required this.stats,
    required this.powerups,
    required this.isGuest,
    this.perks = PremiumPerks.none,
  });

  ProfileLoaded copyWith({PremiumPerks? perks}) => ProfileLoaded(
    stats: stats,
    powerups: powerups,
    isGuest: isGuest,
    perks: perks ?? this.perks,
  );

  @override
  List<Object?> get props => [
    stats,
    powerups,
    isGuest,
    perks.isPremium,
    perks.avatarId,
  ];
}

class ProfileError extends ProfileState {
  final String message;

  const ProfileError(this.message);

  @override
  List<Object?> get props => [message];
}
