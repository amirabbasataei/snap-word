import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wordchain/core/di/injection.dart';
import 'package:wordchain/core/services/notification_service.dart';
import 'package:wordchain/core/utils/error_messages.dart';
import 'package:wordchain/core/utils/tab_refresh.dart';
import 'package:wordchain/core/widgets/notification_permission_dialog.dart';
import 'package:wordchain/core/widgets/z_toast.dart';
import 'package:wordchain/features/profile/view/widgets/profile_settings.dart';

/// «اعلان‌ها» — whether this device gets pushes, shown like «حالت شب».
///
/// On means the player allows it in the app **and** the OS permission is
/// granted. Turning it off is the player's own opt-out ([NotificationService.
/// setEnabled]): the device is unregistered, so nothing is sent to it. Turning
/// it on stores the choice and, when the OS has not granted the permission,
/// shows the explainer before the OS prompt. An app cannot revoke or re-ask a
/// refused OS permission (iOS asks once, Android twice), so when the prompt
/// does not appear the toast points to the system settings.
///
/// Re-read on every profile-tab tap and on app resume, so a permission changed
/// in system settings is picked up.
class ProfileNotificationsSwitch extends StatefulWidget {
  const ProfileNotificationsSwitch({super.key});

  @override
  State<ProfileNotificationsSwitch> createState() =>
      _ProfileNotificationsSwitchState();
}

class _ProfileNotificationsSwitchState extends State<ProfileNotificationsSwitch>
    with WidgetsBindingObserver {
  StreamSubscription<int>? _tabSub;

  /// Null until the first read: nothing is drawn before we know the state.
  bool? _on;

  /// A change is in flight: the switch shows a spinner and ignores taps.
  bool _busy = false;

  NotificationService get _service => getIt<NotificationService>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabSub = getIt<TabRefreshBus>().stream.listen((i) {
      if (i == MainTab.profile) _refresh();
    });
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final on =
        await _service.isEnabled() &&
        await _service.permissionState() == 'granted';
    if (mounted && on != _on) setState(() => _on = on);
  }

  Future<void> _toggle() async {
    if (_busy || _on == null) return;
    final turningOff = _on!;
    final overlay = Overlay.of(context, rootOverlay: true);
    setState(() {
      _busy = true;
      // Off is applied at once: the stored flag is what stops pushes, and the
      // server/FCM clean-up runs in the background.
      if (turningOff) _on = false;
    });
    try {
      if (turningOff) {
        await _service.setEnabled(false);
        ZToast.showOn(overlay, notificationsOffTitle);
      } else {
        await _service.setEnabled(true);
        var granted = await _service.isAuthorized();
        if (granted) {
          // Reports the permission to the server (reach in the admin panel).
          await _service.registerToken();
        } else if (mounted) {
          granted = await askNotificationPermissionWithExplainer(context);
          if (!granted && await _service.permissionState() == 'denied') {
            ZToast.showOn(
              overlay,
              notificationsBlockedTitle,
              message: notificationsBlockedMessage,
            );
          }
        }
        if (granted) {
          ZToast.showOn(
            overlay,
            notificationsEnabledTitle,
            message: notificationsEnabledMessage,
            kind: ZToastKind.success,
          );
        }
      }
      await _refresh();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final on = _on;
    if (on == null) return const SizedBox.shrink();
    return ProfileSwitchButton(
      label: 'اعلان‌ها',
      value: on,
      busy: _busy,
      onTap: _toggle,
    );
  }
}
