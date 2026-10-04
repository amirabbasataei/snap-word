import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:wordchain/core/di/injection.dart';

/// Indices of the main shell's tabs, in bottom-nav order.
abstract final class MainTab {
  static const home = 0;
  static const board = 1;
  static const friends = 2;
  static const profile = 3;
}

/// Fires the tapped tab's index on every bottom-nav tap (including a re-tap of
/// the current tab). The shell keeps every tab alive, so tabs listen to this
/// to reload instead of showing data from when they were first built.
class TabRefreshBus {
  final _controller = StreamController<int>.broadcast();

  Stream<int> get stream => _controller.stream;

  void notify(int index) => _controller.add(index);
}

/// Calls [onRefresh] whenever tab [index] is tapped.
class TabRefreshListener extends StatefulWidget {
  final int index;
  final void Function(BuildContext context) onRefresh;
  final Widget child;

  const TabRefreshListener({
    super.key,
    required this.index,
    required this.onRefresh,
    required this.child,
  });

  @override
  State<TabRefreshListener> createState() => _TabRefreshListenerState();
}

class _TabRefreshListenerState extends State<TabRefreshListener> {
  StreamSubscription<int>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = getIt<TabRefreshBus>().stream.listen((i) {
      if (i == widget.index && mounted) widget.onRefresh(context);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
