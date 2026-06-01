part of '../app_database.dart';

class RemotePowerup {
  final String powerupType;
  final int quantity;

  const RemotePowerup({required this.powerupType, required this.quantity});

  factory RemotePowerup.fromJson(Map<String, dynamic> json) => RemotePowerup(
        powerupType: json['powerup_type'] as String,
        quantity: json['quantity'] as int? ?? 0,
      );
}

@DriftAccessor(tables: [LocalPowerupCache])
class PowerupCacheDao extends DatabaseAccessor<AppDatabase>
    with _$PowerupCacheDaoMixin {
  PowerupCacheDao(super.db);

  Future<List<LocalPowerupCacheEntry>> getAll() =>
      select(localPowerupCache).get();

  Future<void> setQuantity(String powerupType, int quantity) =>
      into(localPowerupCache).insertOnConflictUpdate(
        LocalPowerupCacheCompanion(
          powerupType: Value(powerupType),
          quantity: Value(quantity),
          lastSyncedAt: Value(DateTime.now()),
        ),
      );

  Future<void> refreshFromRemote(List<RemotePowerup> powerups) async {
    await transaction(() async {
      for (final p in powerups) {
        await setQuantity(p.powerupType, p.quantity);
      }
    });
  }
}
