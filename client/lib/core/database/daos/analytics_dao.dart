part of '../app_database.dart';

@DriftAccessor(tables: [LocalAnalyticsEvents])
class AnalyticsDao extends DatabaseAccessor<AppDatabase>
    with _$AnalyticsDaoMixin
    implements AnalyticsEventStore {
  AnalyticsDao(super.db);

  @override
  Future<void> add(StoredAnalyticsEvent e) => into(localAnalyticsEvents).insert(
    LocalAnalyticsEventsCompanion.insert(
      clientEventId: e.clientEventId,
      name: e.name,
      tsMs: e.tsMs,
      sessionId: Value(e.sessionId),
      screen: Value(e.screen),
      props: Value(e.props),
    ),
  );

  @override
  Future<List<StoredAnalyticsEvent>> oldest(int limit) async {
    final rows =
        await (select(localAnalyticsEvents)
              ..orderBy([(t) => OrderingTerm.asc(t.id)])
              ..limit(limit))
            .get();
    return [
      for (final r in rows)
        StoredAnalyticsEvent(
          id: r.id,
          clientEventId: r.clientEventId,
          name: r.name,
          tsMs: r.tsMs,
          sessionId: r.sessionId,
          screen: r.screen,
          props: r.props,
        ),
    ];
  }

  @override
  Future<void> remove(List<int> ids) =>
      (delete(localAnalyticsEvents)..where((t) => t.id.isIn(ids))).go();

  /// Keeps the newest [maxRows] events, dropping the oldest first.
  @override
  Future<void> trim(int maxRows) async {
    final count = await localAnalyticsEvents.count().getSingle();
    if (count <= maxRows) return;
    await customUpdate(
      'DELETE FROM local_analytics_events WHERE id IN ('
      'SELECT id FROM local_analytics_events ORDER BY id ASC LIMIT ?)',
      variables: [Variable.withInt(count - maxRows)],
      updates: {localAnalyticsEvents},
    );
  }
}
