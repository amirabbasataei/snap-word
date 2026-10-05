import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:logger/logger.dart';
import 'package:tapsell_mediation/tapsell.dart';

/// Tapsell zone ids (create them in the Tapsell panel for this app's key, which
/// lives in `android/app/build.gradle.kts`). Pass at build time:
/// `--dart-define=TAPSELL_REWARDED_ZONE=...`. An empty id disables ads.
abstract final class AdZones {
  static const String rewarded = String.fromEnvironment(
    'TAPSELL_REWARDED_ZONE',
  );
}

/// Player-initiated rewarded ads only. There are deliberately no banners or
/// interstitials: an ad is shown only after the player taps "watch ad".
class AdService {
  static const _requestTimeout = Duration(seconds: 12);
  static const _showTimeout = Duration(minutes: 3);

  final Logger _log = Logger();
  bool _rewardedBusy = false;

  bool get _supported => !kIsWeb && Platform.isAndroid;
  bool get rewardedEnabled => _supported && AdZones.rewarded.isNotEmpty;

  Future<void> init() async {
    if (!_supported) return;
    try {
      // Iran market, no GDPR-style consent screen; the SDK still wants a value.
      await Tapsell.setUserConsent(true);
    } catch (e) {
      _log.w('Tapsell consent call failed: $e');
    }
    if (AdZones.rewarded.isEmpty) {
      _log.w('TAPSELL_REWARDED_ZONE not set — rewarded ads are disabled');
    }
  }

  /// Requests and shows a rewarded ad. Returns true only if the player earned
  /// the reward (watched to completion). False on no-fill, error, or skip.
  Future<bool> showRewardedAd() async {
    if (!rewardedEnabled || _rewardedBusy) return false;
    _rewardedBusy = true;
    try {
      final adId = await Tapsell.requestRewardedAd(
        AdZones.rewarded,
      ).timeout(_requestTimeout);
      _log.d('Rewarded ad id: $adId');
      if (adId == null || adId.isEmpty) return false;

      final done = Completer<bool>();
      var rewarded = false;
      // The native call doesn't return when the ad ends (the callbacks below
      // report that), so it must not be awaited.
      Tapsell.showRewardedAd(
        adId,
        onAdImpression: () => _log.d('Rewarded ad impression'),
        onAdClicked: () => _log.d('Rewarded ad clicked'),
        onAdRewarded: () {
          _log.d('Rewarded ad rewarded');
          rewarded = true;
        },
        onAdClosed: (state) {
          _log.d('Rewarded ad closed: $state (rewarded=$rewarded)');
          if (!done.isCompleted) {
            done.complete(rewarded || state == ShowCompletionState.completed);
          }
        },
        onAdFailed: (message) {
          _log.w('Rewarded ad failed: $message');
          if (!done.isCompleted) done.complete(false);
        },
      ).catchError((Object e) {
        _log.w('Rewarded ad show failed: $e');
        if (!done.isCompleted) done.complete(false);
        return null;
      });
      return await done.future.timeout(_showTimeout, onTimeout: () => rewarded);
    } on PlatformException catch (e) {
      _log.w('Rewarded ad request failed: ${e.message}');
      return false;
    } on TimeoutException {
      _log.w('Rewarded ad request timed out');
      return false;
    } catch (e) {
      _log.w('Rewarded ad error: $e');
      return false;
    } finally {
      _rewardedBusy = false;
    }
  }
}
