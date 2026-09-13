import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../router/root_navigator.dart';
import 'logger.dart';

const _tag = 'AppUpdater';
const _releasesUrl =
    'https://api.github.com/repos/GrishMahat/NovelDock/releases/latest';
const _releasesPage = 'https://github.com/GrishMahat/NovelDock/releases';

/// A newer release found on GitHub.
class UpdateInfo {
  final String version;
  final String url;
  final String? notes;
  const UpdateInfo({required this.version, required this.url, this.notes});
}

/// In-app update check (original's `InAppUpdater`, minus auto-download:
/// the dialog links to the releases page and the user installs by hand).
class AppUpdater {
  /// Returns the latest release when it is newer than the installed build,
  /// null when up to date or when the check fails. Never throws.
  static Future<UpdateInfo?> checkForUpdate({http.Client? client}) async {
    final owned = client == null;
    client ??= http.Client();
    try {
      final current = (await PackageInfo.fromPlatform()).version;
      final res = await client
          .get(
            Uri.parse(_releasesUrl),
            headers: {'Accept': 'application/vnd.github+json'},
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final tag = (json['tag_name'] as String?) ?? '';
      if (tag.isEmpty || !isNewerVersion(current, tag)) return null;
      return UpdateInfo(
        version: tag,
        url: (json['html_url'] as String?) ?? _releasesPage,
        notes: json['body'] as String?,
      );
    } catch (e) {
      Log.w(_tag, 'Update check failed: $e');
      return null;
    } finally {
      if (owned) client.close();
    }
  }

  /// Check and prompt. Quiet (app-start) mode only dialogs on an update;
  /// manual mode also reports "up to date" via snackbar. Falls back to the
  /// root navigator context when none is passed (startup runs above
  /// MaterialApp in the tree, where no Navigator exists yet).
  static Future<void> checkAndPrompt({
    BuildContext? context,
    bool quiet = true,
    http.Client? client,
  }) async {
    final info = await checkForUpdate(client: client);
    final ctx = context ?? rootNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    if (info != null) {
      await showUpdateDialog(ctx, info);
    } else if (!quiet) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(content: Text('You are on the latest version')),
      );
    }
  }

  static Future<void> showUpdateDialog(BuildContext context, UpdateInfo info) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Update available'),
        content: Text(
          'NovelDock ${info.version} is available. '
          'Open the releases page to download it?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(context).pop();
              final uri = Uri.parse(info.url);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
            child: const Text('Download'),
          ),
        ],
      ),
    );
  }

  /// True when [latestTag] (e.g. `v0.2.0`, `v0.1.3-beta`) is newer than the
  /// installed [current] version (`0.1.3`). A bare release outranks the same
  /// core with a pre-release suffix.
  static bool isNewerVersion(String current, String latestTag) {
    List<int> core(String v) {
      final bare = v.trim().replaceFirst(RegExp('^[vV]'), '');
      final corePart = bare.split(RegExp('[-+]')).first;
      return corePart.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    }

    bool preRelease(String v) {
      final bare = v.trim().replaceFirst(RegExp('^[vV]'), '');
      return bare.contains('-');
    }

    final a = core(current);
    final b = core(latestTag);
    for (var i = 0; i < a.length || i < b.length; i++) {
      final x = i < a.length ? a[i] : 0;
      final y = i < b.length ? b[i] : 0;
      if (y != x) return y > x;
    }
    // Same core: release beats pre-release (installed beta -> release).
    return preRelease(current) && !preRelease(latestTag);
  }
}
