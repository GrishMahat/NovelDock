import 'package:flutter_riverpod/legacy.dart';

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

class NovelFetchStateNotifier extends StateNotifier<NovelFetchState> {
  NovelFetchStateNotifier() : super(const NovelFetchState());

  void set(NovelFetchPhase phase) {
    if (mounted) state = state.copyWith(phase);
  }
}

/// Per-novel background fetch phase, updated by [NovelOpener] and consumed
/// by surfaces that must distinguish "no chapters exist" from "chapters are
/// still being fetched".
final novelFetchStateProvider =
    StateNotifierProvider.family<NovelFetchStateNotifier, NovelFetchState, int>(
      (ref, novelId) => NovelFetchStateNotifier(),
    );
