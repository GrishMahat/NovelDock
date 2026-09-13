import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../main.dart' show sharedFilePath;
import '../../router/app_router.dart';
import '../../router/root_navigator.dart';
import '../providers/engine.dart';
import '../providers/models.dart';
import '../providers/novel_opener.dart';
import '../providers/registries.dart';
import 'logger.dart';

const _tag = 'IncomingIntent';

/// Tabs reachable via `noveldock://<tab>` (launcher shortcuts).
const _intentTabs = {'library', 'browse', 'history', 'downloads', 'settings'};

/// Android share/deep-link/custom-scheme intents, forwarded by MainActivity
/// over `dev.grish.noveldock/intents` as `{kind, ...}` maps:
/// - `{kind: file, path}` — shared/clicked EPUB or PDF (already copied to
///   our cache dir; Dart cannot read another app's content:// URIs)
/// - `{kind: url, url}` — http(s) novel link (browser share or deep link)
/// - `{kind: tab, tab}` — `noveldock://<tab>` (launcher shortcuts)
///
/// Wired once from NovelDockApp startup: cold intent via getInitialIntent,
/// warm intents via the onIntent push. The app widget is app-lifetime, so
/// holding its ref in the static channel handler is safe.
class IncomingIntent {
  static const _channel = MethodChannel('dev.grish.noveldock/intents');

  static Future<void> handleStartup(WidgetRef ref) async {
    try {
      final initial = await _channel.invokeMethod<Map>('getInitialIntent');
      if (initial != null) {
        await route(ref, Map<String, String>.from(initial));
      }
    } catch (_) {
      // Non-Android shells have no native handler: nothing to route.
    }
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onIntent' && call.arguments is Map) {
        await route(ref, Map<String, String>.from(call.arguments as Map));
      }
    });
  }

  @visibleForTesting
  static Future<void> route(WidgetRef ref, Map<String, String> intent) async {
    final router = ref.read(routerProvider);
    switch (intent['kind']) {
      case 'file':
        final path = intent['path'];
        if (path == null || path.isEmpty) return;
        Log.i(_tag, 'Shared file: $path');
        sharedFilePath = path;
        router.go('/import?file=${Uri.encodeComponent(path)}');
      case 'url':
        await _openNovelUrl(ref, intent['url'] ?? '');
      case 'tab':
        final tab = intent['tab'] ?? '';
        if (_intentTabs.contains(tab)) {
          router.go('/$tab');
        } else {
          Log.w(_tag, 'Unknown intent tab: $tab');
        }
      default:
        Log.w(_tag, 'Unknown intent: $intent');
    }
  }

  /// Opens a browser-shared / deep-linked novel URL: match the host against
  /// installed providers, insert, and navigate to the detail screen (metadata
  /// fills in in the background via the normal open flow).
  static Future<void> _openNovelUrl(WidgetRef ref, String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) return;
    try {
      await ref.read(enabledProvidersProvider.notifier).ready;
      final enabled = ref.read(enabledProvidersProvider);
      final metas = await ref.read(availableProvidersProvider.future);
      final providerId = matchProviderForUrl(
        url,
        metas.where((m) => enabled.contains(m.id)).toList(),
      );
      final router = ref.read(routerProvider);
      if (providerId == null) {
        _snack('No installed source handles this link');
        router.go('/browse');
        return;
      }
      final id = await ref
          .read(novelOpenerProvider)
          .open(
            SearchResultItem(
              title: _titleFallback(uri),
              url: url,
              providerId: providerId,
            ),
          );
      if (id > 0) {
        router.go('/novel/$id');
      } else {
        _snack('Could not open this link');
      }
    } catch (e) {
      Log.w(_tag, 'Failed to open $url: $e');
      _snack('Could not open this link');
    }
  }

  /// Provider id whose baseUrl host matches [url] (www-tolerant), or null.
  /// Pure for testing.
  static String? matchProviderForUrl(String url, List<ProviderMeta> providers) {
    final host = _bareHost(Uri.tryParse(url)?.host ?? '');
    if (host.isEmpty) return null;
    for (final meta in providers) {
      final base = _bareHost(Uri.tryParse(meta.baseUrl)?.host ?? '');
      if (base.isNotEmpty && (host == base || host.endsWith('.$base'))) {
        return meta.id;
      }
    }
    return null;
  }

  static String _bareHost(String host) {
    final h = host.toLowerCase();
    return h.startsWith('www.') ? h.substring(4) : h;
  }

  static String _titleFallback(Uri uri) {
    final last = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
    final title = last.replaceAll(RegExp('[-_]+'), ' ').trim();
    return title.isEmpty ? uri.host : title;
  }

  static void _snack(String message) {
    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null) return;
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(message)));
  }
}
