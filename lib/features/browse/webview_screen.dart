import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_all/webview_all.dart';

import '../../core/network/client.dart' show cookieJarProvider;
import '../../core/network/cloudflare.dart';
import '../../core/utils/logger.dart';
import '../../theme/tokens.dart';

const _tag = 'WebView';

/// How often the clearance cookie is checked while a challenge is showing,
/// and how long we keep trying before giving up (2s × 150 ≈ 5 minutes).
const _cookiePollInterval = Duration(seconds: 2);
const _cookiePollMaxChecks = 150;

/// JavaScript that answers '1' when the current page is a Cloudflare
/// challenge and '0' otherwise. Returned as '1'/'0' strings rather than a
/// bare boolean because result wrapping differs between platforms.
const _challengeProbeJs = '''
(function() {
  var html = (document.documentElement && document.documentElement.outerHTML) || '';
  var markers = ['cf-browser-verification', '__cf_chl_f_tk',
    'cdn-cgi/challenge-platform', 'Checking your browser', 'Just a moment'];
  for (var i = 0; i < markers.length; i++) {
    if (html.indexOf(markers[i]) !== -1) return '1';
  }
  return '0';
})()
''';

/// In-app browser backed by webview_all (Android, iOS, desktop, web).
///
/// Every loaded page is checked for a Cloudflare challenge; the verification
/// banner only appears while a challenge is actually present. Once clearance
/// cookies show up in the browser's cookie store they are copied into the
/// app cookie jar so provider fetches go through.
class WebViewScreen extends ConsumerStatefulWidget {
  final String url;
  final String title;
  const WebViewScreen({super.key, required this.url, this.title = ''});
  @override
  ConsumerState<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends ConsumerState<WebViewScreen> {
  WebViewController? _controller;
  bool _isLoading = true;
  bool _useFallback = false;
  int _progress = 0;
  String? _loadError;
  bool _challenge = false;
  Timer? _clearanceTimer;
  int _checkCount = 0;
  bool _reloadingAfterClearance = false;

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  @override
  void dispose() {
    _clearanceTimer?.cancel();
    super.dispose();
  }

  Future<void> _initWebView() async {
    try {
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageStarted: (_) {
              if (mounted) {
                setState(() {
                  _isLoading = true;
                  _loadError = null;
                });
              }
            },
            onPageFinished: (_) {
              if (!mounted) return;
              setState(() => _isLoading = false);
              _evaluateChallenge();
            },
            onProgress: (progress) {
              if (mounted) setState(() => _progress = progress);
            },
            onWebResourceError: (error) {
              if (mounted) {
                setState(() {
                  _isLoading = false;
                  _loadError = error.description;
                });
              }
            },
          ),
        )
        ..loadRequest(Uri.parse(widget.url));
    } catch (_) {
      // WebView not supported on this platform, use system browser
      if (mounted) {
        setState(() => _useFallback = true);
        await _openInExternalBrowser();
      }
    }
  }

  /// Check the freshly loaded page for a Cloudflare challenge and show or
  /// hide the verification banner accordingly.
  Future<void> _evaluateChallenge() async {
    final controller = _controller;
    if (controller == null || !mounted) return;
    try {
      final result = await controller.runJavaScriptReturningResult(
        _challengeProbeJs,
      );
      final challenged = result.toString().replaceAll('"', '') == '1';
      if (!mounted) return;
      setState(() => _challenge = challenged);
      if (challenged) {
        _startClearancePolling();
      } else {
        _clearanceTimer?.cancel();
      }
    } catch (e) {
      Log.w(_tag, 'Challenge probe failed: $e');
    }
  }

  void _startClearancePolling() {
    _clearanceTimer?.cancel();
    _checkCount = 0;
    _clearanceTimer = Timer.periodic(_cookiePollInterval, (_) {
      if (!mounted) {
        _clearanceTimer?.cancel();
        return;
      }
      _checkCount++;
      _pollForClearance();
      if (_checkCount >= _cookiePollMaxChecks) {
        _clearanceTimer?.cancel();
        Log.w(_tag, 'Cloudflare clearance polling timed out');
      }
    });
  }

  /// Look for cf_clearance in the browser's native cookie store; when found,
  /// copy all cookies for this domain into the app cookie jar and reload so
  /// the challenge page resolves to the real content.
  Future<void> _pollForClearance() async {
    final controller = _controller;
    if (controller == null || _reloadingAfterClearance) return;
    try {
      final uri = Uri.parse(widget.url);
      final currentUrl = await controller.currentUrl();
      final cookieUri = currentUrl == null ? uri : Uri.parse(currentUrl);
      final cookies = await WebViewCookieManager().getCookies(
        domain: cookieUri,
      );
      if (!mounted || _reloadingAfterClearance) return;

      final hasClearance = cookies.any((c) => c.name == 'cf_clearance');
      if (!hasClearance) return;

      _clearanceTimer?.cancel();
      final jar = await ref.read(cookieJarProvider.future);
      await CloudflareHandler.persistCookies(jar, cookieUri, {
        for (final c in cookies) c.name: c.value,
      });
      Log.ok(
        _tag,
        'Captured ${cookies.length} cookies incl. cf_clearance for ${uri.host}',
      );
      _reloadingAfterClearance = true;
      await controller.reload();
      _reloadingAfterClearance = false;
    } catch (e) {
      // Cookie store or jar may not be ready yet; poll again.
      Log.d(_tag, 'Clearance poll: $e');
    }
  }

  Future<void> _openInExternalBrowser() async {
    final uri = Uri.parse(widget.url);
    final launched =
        await canLaunchUrl(uri) &&
        await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!mounted) return;
    if (!launched) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Couldn\'t open link: ${widget.url}')),
      );
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    if (_useFallback || _controller == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.title.isNotEmpty ? widget.title : widget.url),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title.isNotEmpty ? widget.title : widget.url),
        bottom: _isLoading && _progress > 0
            ? PreferredSize(
                preferredSize: const Size.fromHeight(3),
                child: LinearProgressIndicator(
                  value: _progress / 100,
                  backgroundColor: Colors.transparent,
                ),
              )
            : null,
      ),
      body: _loadError != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 48),
                    const SizedBox(height: 12),
                    Text(
                      'Failed to load page:\n$_loadError',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => _controller!.reload(),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          : Column(
              children: [
                // Cloud verification banner — only shown while a Cloudflare
                // challenge is actually present on the loaded page.
                if (_challenge)
                  Container(
                    width: double.infinity,
                    color: scheme.secondaryContainer,
                    padding: const EdgeInsets.symmetric(
                      horizontal: Insets.md,
                      vertical: Insets.sm,
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: scheme.onSecondaryContainer,
                          ),
                        ),
                        const SizedBox(width: Insets.sm),
                        Expanded(
                          child: Text(
                            'Cloudflare verification required — completing it '
                            'here, then chapters can load.',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: scheme.onSecondaryContainer),
                          ),
                        ),
                      ],
                    ),
                  ),
                Expanded(child: WebViewWidget(controller: _controller!)),
              ],
            ),
    );
  }
}
