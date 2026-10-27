import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// The installed app's version as `version+build` (e.g. `0.1.3+4`), read once
/// from the platform. Null when it cannot be read — callers show nothing or
/// a placeholder rather than failing.
abstract final class AppVersion {
  static Future<String?>? _cached;

  static Future<String?> load() => _cached ??= _read();

  static Future<String?> _read() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return info.buildNumber.isEmpty
          ? info.version
          : '${info.version}+${info.buildNumber}';
    } catch (e) {
      Logger().w('app version unavailable: $e');
      return null;
    }
  }

  @visibleForTesting
  static void reset() => _cached = null;
}
