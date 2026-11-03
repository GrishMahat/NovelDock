/// Formats epoch-millisecond timestamps for list rows and sheets.
///
/// Kept hand-rolled (no intl): the app only ever shows "HH:mm" and
/// "yyyy-MM-dd", and `DateTime.toString()`'s exact layout must not be a
/// dependency (the history screen used to slice it apart).
library;

/// Local-time "HH:mm".
String formatTimeOfDay(int epochMillis) {
  final dt = DateTime.fromMillisecondsSinceEpoch(epochMillis);
  return '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}';
}

/// Local-time "yyyy-MM-dd".
String formatDate(int epochMillis) {
  final dt = DateTime.fromMillisecondsSinceEpoch(epochMillis);
  final mm = dt.month.toString().padLeft(2, '0');
  final dd = dt.day.toString().padLeft(2, '0');
  return '${dt.year}-$mm-$dd';
}
