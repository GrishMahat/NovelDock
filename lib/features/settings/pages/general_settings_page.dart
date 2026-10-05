import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:webview_all/webview_all.dart';

import '../../../core/config/app_prefs.dart';
import '../../../core/network/client.dart' show cookieJarProvider;
import '../../../core/providers/browse_cache.dart';
import '../../../core/utils/logger.dart';

part 'general_settings_page.g.dart';

const _tag = 'GeneralSettings';

class GeneralSettings {
  final int startupTab;
  final String defaultDisplayMode;

  /// Layout for a source's Popular/Latest results.
  ///
  /// Deliberately its own key rather than [defaultDisplayMode]: that one is a
  /// three-way mode for the library (grid/list/compact) written by the library's
  /// own toggle. Sharing it would let the browse toggle silently overwrite a
  /// library preference, since "compact" has no browse equivalent.
  final bool browseGridView;
  final bool confirmExit;
  final bool showNsfw;

  /// Raw provider scores are 0–1000: 'stars' (÷200, ★ 4.3), 'ten' (÷100),
  /// or 'hundred' (÷10).
  final String ratingFormat;

  const GeneralSettings({
    this.startupTab = 0,
    this.defaultDisplayMode = 'grid',

    /// Grid on every form factor. The old default was "list on phones", chosen
    /// when a browse card was 120dp wide and ate its own title; the mobile
    /// density pass fixed the geometry (2 columns at 260dp on a phone), so that
    /// default no longer earns its keep.
    this.browseGridView = true,
    this.confirmExit = false,
    this.showNsfw = false,
    this.ratingFormat = 'stars',
  });

  GeneralSettings copyWith({
    int? startupTab,
    String? defaultDisplayMode,
    bool? browseGridView,
    bool? confirmExit,
    bool? showNsfw,
    String? ratingFormat,
  }) {
    return GeneralSettings(
      startupTab: startupTab ?? this.startupTab,
      defaultDisplayMode: defaultDisplayMode ?? this.defaultDisplayMode,
      browseGridView: browseGridView ?? this.browseGridView,
      confirmExit: confirmExit ?? this.confirmExit,
      showNsfw: showNsfw ?? this.showNsfw,
      ratingFormat: ratingFormat ?? this.ratingFormat,
    );
  }
}

@Riverpod(keepAlive: true)
class GeneralSettingsNotifier extends _$GeneralSettingsNotifier {
  @override
  GeneralSettings build() {
    final p = ref.watch(appPrefsProvider);
    return GeneralSettings(
      startupTab: p.getInt('startup_tab') ?? 0,
      defaultDisplayMode: p.getString('default_display_mode') ?? 'grid',
      browseGridView: p.getBool('browse_grid_view') ?? true,
      confirmExit: p.getBool('confirm_exit') ?? false,
      showNsfw: p.getBool('show_nsfw') ?? false,
      ratingFormat: p.getString('rating_format') ?? 'stars',
    );
  }

  Future<void> setStartupTab(int tab) async {
    state = state.copyWith(startupTab: tab);
    await ref.read(appPrefsProvider).setInt('startup_tab', tab);
  }

  Future<void> setDefaultDisplayMode(String mode) async {
    state = state.copyWith(defaultDisplayMode: mode);
    await ref.read(appPrefsProvider).setString('default_display_mode', mode);
  }

  Future<void> setBrowseGridView(bool value) async {
    state = state.copyWith(browseGridView: value);
    await ref.read(appPrefsProvider).setBool('browse_grid_view', value);
  }

  Future<void> setConfirmExit(bool value) async {
    state = state.copyWith(confirmExit: value);
    await ref.read(appPrefsProvider).setBool('confirm_exit', value);
  }

  Future<void> setShowNsfw(bool value) async {
    state = state.copyWith(showNsfw: value);
    await ref.read(appPrefsProvider).setBool('show_nsfw', value);
  }

  Future<void> setRatingFormat(String format) async {
    state = state.copyWith(ratingFormat: format);
    await ref.read(appPrefsProvider).setString('rating_format', format);
  }
}

class GeneralSettingsPage extends ConsumerStatefulWidget {
  const GeneralSettingsPage({super.key});

  @override
  ConsumerState<GeneralSettingsPage> createState() =>
      _GeneralSettingsPageState();
}

class _GeneralSettingsPageState extends ConsumerState<GeneralSettingsPage> {
  /// Live cache size for the storage row. Null until the first read lands.
  String? _browseCacheSummary;

  @override
  void initState() {
    super.initState();
    _loadBrowseCacheSummary();
  }

  Future<void> _loadBrowseCacheSummary() async {
    try {
      final cache = ref.read(BrowseResultCache.provider);
      final entries = await cache.entryCount();
      final bytes = await cache.sizeBytes();
      if (!mounted) return;
      setState(() {
        _browseCacheSummary = entries == 0
            ? 'Empty'
            : '${_formatBytes(bytes)} across $entries cached page(s)';
      });
    } catch (_) {
      if (mounted) setState(() => _browseCacheSummary = null);
    }
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _confirmClearBrowseCache(WidgetRef ref) async {
    final cache = ref.read(BrowseResultCache.provider);
    final entries = await cache.entryCount();
    if (!mounted) return;

    if (entries == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Browse cache is already empty')),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear browse cache?'),
        content: Text(
          'Removes $entries cached listing(s). Sources will load from the '
          'network next time you open them. Downloads and library untouched.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await cache.clear();
    await _loadBrowseCacheSummary();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Browse cache cleared')));
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(generalSettingsProvider);
    final notifier = ref.read(generalSettingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('General Settings')),
      body: ListView(
        children: [
          _buildSection(context, 'Startup Tab'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(
              'Takes effect after restarting the app.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          RadioGroup<int>(
            groupValue: settings.startupTab,
            onChanged: (v) {
              if (v != null) notifier.setStartupTab(v);
            },
            child: Column(
              children: [
                RadioListTile<int>(title: const Text('Library'), value: 0),
                RadioListTile<int>(title: const Text('Browse'), value: 1),
                RadioListTile<int>(title: const Text('History'), value: 2),
              ],
            ),
          ),
          const Divider(),
          _buildSection(context, 'Library Default View'),
          RadioGroup<String>(
            groupValue: settings.defaultDisplayMode,
            onChanged: (v) {
              if (v != null) notifier.setDefaultDisplayMode(v);
            },
            child: Column(
              children: [
                RadioListTile<String>(
                  title: const Text('Grid View'),
                  value: 'grid',
                ),
                RadioListTile<String>(
                  title: const Text('List View'),
                  value: 'list',
                ),
                RadioListTile<String>(
                  title: const Text('Compact View'),
                  value: 'compact',
                ),
              ],
            ),
          ),
          const Divider(),
          _buildSection(context, 'Rating Format'),
          RadioGroup<String>(
            groupValue: settings.ratingFormat,
            onChanged: (v) {
              if (v != null) notifier.setRatingFormat(v);
            },
            child: const Column(
              children: [
                RadioListTile<String>(
                  title: Text('Stars'),
                  subtitle: Text('★ 4.3 out of 5'),
                  value: 'stars',
                ),
                RadioListTile<String>(
                  title: Text('10-point'),
                  subtitle: Text('8.5 out of 10'),
                  value: 'ten',
                ),
                RadioListTile<String>(
                  title: Text('100-point'),
                  subtitle: Text('85 out of 100'),
                  value: 'hundred',
                ),
              ],
            ),
          ),
          const Divider(),
          _buildSection(context, 'Application Behavior'),
          SwitchListTile(
            title: const Text('Confirm before exit'),
            subtitle: const Text('Prompt for confirmation before closing app'),
            value: settings.confirmExit,
            onChanged: (v) => notifier.setConfirmExit(v),
          ),
          SwitchListTile(
            title: const Text('Show NSFW Sources'),
            subtitle: const Text('Display 18+ provider extensions in Browse'),
            value: settings.showNsfw,
            onChanged: (v) async {
              if (v) {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Age Verification'),
                    content: const Text(
                      'NSFW content may contain adult material. Are you 18 or older?',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('I am 18+'),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  notifier.setShowNsfw(true);
                }
              } else {
                notifier.setShowNsfw(false);
              }
            },
          ),
          const Divider(),
          _buildSection(context, 'Storage'),
          ListTile(
            leading: const Icon(Icons.grid_view_outlined),
            title: const Text('Browse cache'),
            subtitle: Text(
              _browseCacheSummary ??
                  'Saved source listings for faster browsing',
            ),
            trailing: const Icon(Icons.chevron_right, size: 18),
            onTap: () => _confirmClearBrowseCache(ref),
          ),
          const Divider(),
          _buildSection(context, 'Privacy'),
          ListTile(
            leading: const Icon(Icons.cleaning_services_outlined),
            title: const Text('Clear site data'),
            subtitle: const Text(
              'Delete scraper cookies and in-app browser sessions. '
              'You may need to solve Cloudflare checks again.',
            ),
            onTap: () => _confirmClearSiteData(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmClearSiteData(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear site data?'),
        content: const Text(
          'This signs you out of novel sites inside the app and clears '
          'saved verification cookies. Downloads and library are untouched.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;

    var cleared = 0;
    try {
      final jar = await ref.read(cookieJarProvider.future);
      await jar.deleteAll();
      cleared++;
    } catch (e) {
      Log.w(_tag, 'Failed to clear scraper cookies: $e');
    }
    try {
      await WebViewCookieManager().clearCookies();
      cleared++;
    } catch (e) {
      Log.w(_tag, 'Failed to clear browser cookies: $e');
    }

    Log.i(_tag, 'Site data cleared ($cleared/2 stores)');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            cleared == 2
                ? 'Site data cleared'
                : 'Partially cleared — see logs for details',
          ),
        ),
      );
    }
  }

  Widget _buildSection(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
