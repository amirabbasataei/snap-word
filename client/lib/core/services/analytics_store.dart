/// One buffered analytics event, as stored on the device until uploaded.
class StoredAnalyticsEvent {
  final int id; // 0 until stored
  final String clientEventId;
  final String name;
  final int tsMs;
  final String? sessionId;
  final String? screen;
  final String? props; // JSON object

  const StoredAnalyticsEvent({
    this.id = 0,
    required this.clientEventId,
    required this.name,
    required this.tsMs,
    this.sessionId,
    this.screen,
    this.props,
  });
}

/// Where `AnalyticsService` buffers events (the Drift `AnalyticsDao`; an
/// in-memory fake in tests).
abstract interface class AnalyticsEventStore {
  Future<void> add(StoredAnalyticsEvent e);

  /// Oldest first.
  Future<List<StoredAnalyticsEvent>> oldest(int limit);

  Future<void> remove(List<int> ids);

  /// Drops the oldest events so at most [maxRows] remain.
  Future<void> trim(int maxRows);
}
