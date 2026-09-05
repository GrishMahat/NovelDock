import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'novel_fetch_state.g.dart';

/// Lifecycle of a background novel detail/chapter-list fetch for one novel.
enum NovelFetchPhase {
  /// No fetch has run (or ever will) for this novel in this session.
  idle,

  /// Novel info page is being downloaded/parsed.
  fetchingInfo,

  /// Chapter list is being built and inserted.
  fetchingChapters,

  /// Fetch finished; whatever reached the database is final.
  completed,

  /// Fetch failed before completing.
  failed;

  /// Whether chapters may still arrive for this novel.
  bool get isFetching => this == fetchingInfo || this == fetchingChapters;
}

class NovelFetchState {
  final NovelFetchPhase phase;

  const NovelFetchState({this.phase = NovelFetchPhase.idle});

  NovelFetchState copyWith(NovelFetchPhase phase) =>
      NovelFetchState(phase: phase);
}

@Riverpod(keepAlive: true)
class NovelFetchStateNotifier extends _$NovelFetchStateNotifier {
  @override
  NovelFetchState build(int novelId) {
    return const NovelFetchState();
  }

  void set(NovelFetchPhase phase) {
    if (ref.mounted) state = state.copyWith(phase);
  }
}
