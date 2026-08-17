import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../utils/logger.dart';

const _tag = 'Cloudflare';

/// Detects Cloudflare challenge pages and resolves them via WebView.
class CloudflareHandler {
  /// Check if a response looks like a Cloudflare challenge.
  static bool isCloudflareChallenge(Response response) {
    final statusCode = response.statusCode ?? 0;
    final body = _bodyAsString(response.data);
    final headers = response.headers;

    // Status codes that indicate Cloudflare
    if (statusCode == 403 || statusCode == 429 || statusCode == 503) {
      if (body.contains('cf-browser-verification') ||
          body.contains('__cf_chl_f_tk') ||
          body.contains('cdn-cgi/challenge-platform') ||
          body.contains('Checking your browser') ||
          body.contains('Just a moment')) {
        return true;
      }
    }

    // Check for cf-ray header
    if (headers.value('cf-ray') != null) {
      if (statusCode == 403 || statusCode == 503) {
        return true;
      }
    }

    // Check server header
    final server = headers.value('server') ?? '';
    if (server.toLowerCase().contains('cloudflare') &&
        body.contains('challenge')) {
      return true;
    }

    return false;
  }

  /// Converts Dio response data to a string regardless of responseType.
  /// `.toString()` on raw bytes (e.g. List<int>/Uint8List) does NOT give
  /// page content — it gives something like "Instance of '_Uint8List'" —
  /// so bytes need to be explicitly utf8-decoded first.
  static String _bodyAsString(dynamic data) {
    if (data == null) return '';
    if (data is String) return data;
    if (data is List<int>) {
      try {
        return utf8.decode(data, allowMalformed: true);
      } catch (_) {
        return '';
      }
    }
    return data.toString();
  }

  /// Attempt to bypass Cloudflare challenge for a URL.
  /// Returns true if bypass was successful (cookies captured).
  Future<bool> bypass(BuildContext context, String url) async {
    Log.i(_tag, 'Starting Cloudflare bypass for: $url');

    try {
      final cookies = await _resolveWithWebView(context, url);
      if (cookies != null && cookies.isNotEmpty) {
        Log.ok(_tag, 'Captured ${cookies.length} cookies');
        return true;
      }
      Log.w(_tag, 'No cookies captured');
      return false;
    } catch (e) {
      Log.e(_tag, 'Cloudflare bypass failed', e);
      return false;
    }
  }

  /// Open WebView and capture Cloudflare clearance cookies.
  Future<Map<String, String>?> _resolveWithWebView(
    BuildContext context,
    String url,
  ) async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('WebView is not available on this platform.'),
          ),
        );
      }
      return null;
    }

    final completer = Completer<Map<String, String>?>();
    bool resolved = false;

    // ignore: use_build_context_synchronously
    await Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (ctx) => _CloudflareWebView(
          url: url,
          onComplete: (cookies) {
            if (!resolved) {
              resolved = true;
              completer.complete(cookies);
              Navigator.of(ctx).pop();
            }
          },
          onTimeout: () {
            if (!resolved) {
              resolved = true;
              completer.complete(null);
              Navigator.of(ctx).pop();
            }
          },
        ),
      ),
    );

    return completer.future;
  }
}

/// WebView page that loads a Cloudflare-protected URL and captures cookies.
class _CloudflareWebView extends StatefulWidget {
  final String url;
  final void Function(Map<String, String> cookies) onComplete;
  final VoidCallback onTimeout;

  const _CloudflareWebView({
    required this.url,
    required this.onComplete,
    required this.onTimeout,
  });

  @override
  State<_CloudflareWebView> createState() => _CloudflareWebViewState();
}

class _CloudflareWebViewState extends State<_CloudflareWebView> {
  WebViewController? _controller;
  bool _isLoading = true;
  bool _unsupported = false;
  bool _completed = false;
  String _status = 'Loading...';
  Timer? _timeoutTimer;
  Timer? _checkTimer;
  int _checkCount = 0;

  @override
  void initState() {
    super.initState();

    try {
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageStarted: (url) {
              if (!mounted) return;
              setState(() {
                _isLoading = true;
                _status = 'Loading page...';
              });
            },
            onPageFinished: (url) {
              if (!mounted) return;
              setState(() {
                _isLoading = false;
                _status = 'Checking for Cloudflare...';
              });
              _onPageFinished();
            },
          ),
        )
        ..loadRequest(Uri.parse(widget.url));
      _controller = controller;

      // Timeout after 5 minutes
      _timeoutTimer = Timer(const Duration(minutes: 5), () {
        if (!mounted) return;
        _complete(() => widget.onTimeout());
      });
    } catch (e) {
      _unsupported = true;
      // Defer completion until after the first frame — calling
      // Navigator.pop synchronously inside initState (via onComplete)
      // can run before the route is fully mounted.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _complete(() => widget.onComplete({}));
      });
    }
  }

  /// Runs [action] exactly once, guarding against duplicate completion
  /// (e.g. timeout firing right as cookies are found).
  void _complete(VoidCallback action) {
    if (_completed) return;
    _completed = true;
    _checkTimer?.cancel();
    _timeoutTimer?.cancel();
    action();
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    _checkTimer?.cancel();
    super.dispose();
  }

  void _onPageFinished() {
    final controller = _controller;
    if (controller == null || _completed) return;

    // Try to auto-click Cloudflare Turnstile checkbox
    controller.runJavaScript('''
      // Try to find and click the Cloudflare challenge
      var challengeForm = document.querySelector('#challenge-form');
      var challengeRunning = document.querySelector('#challenge-running');
      var turnstile = document.querySelector('#cf-turnstile-response');

      if (challengeForm || challengeRunning || turnstile) {
        // Cloudflare challenge detected, try to submit
        var submitBtn = document.querySelector('#challenge-form input[type="submit"]');
        if (submitBtn) submitBtn.click();
      }
    ''');

    // Cancel any previous polling timer before starting a new one —
    // onPageFinished can fire multiple times (redirects, Cloudflare's
    // own internal reloads during the challenge), and without this,
    // overlapping timers would stack up and could all call onComplete.
    _checkTimer?.cancel();
    _checkCount = 0;

    // Check for cf_clearance cookie periodically
    _checkTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted || _completed) {
        _checkTimer?.cancel();
        return;
      }
      _checkCount++;
      _checkCookies();

      // Give up after 150 checks (5 minutes)
      if (_checkCount > 150) {
        _complete(() => widget.onComplete({}));
      }
    });
  }

  Future<void> _checkCookies() async {
    final controller = _controller;
    if (controller == null || _completed) return;

    try {
      final cookieResult = await controller.runJavaScriptReturningResult(
        'document.cookie',
      );
      // The widget may have been disposed, or completion may have
      // already happened via timeout/skip, while this await was pending.
      if (!mounted || _completed) return;

      final cookieString = cookieResult.toString();

      if (cookieString.contains('cf_clearance')) {
        // Parse cookies
        final cookies = <String, String>{};
        for (final part in cookieString.split(';')) {
          final trimmed = part.trim();
          final eqIndex = trimmed.indexOf('=');
          if (eqIndex > 0) {
            final name = trimmed.substring(0, eqIndex).trim();
            final value = trimmed.substring(eqIndex + 1).trim();
            cookies[name] = value;
          }
        }

        _complete(() => widget.onComplete(cookies));
      }
    } catch (e) {
      // JS might not be ready yet
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_unsupported || _controller == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cloudflare Verification'),
        actions: [
          TextButton(
            onPressed: () => _complete(() => widget.onComplete({})),
            child: const Text('Skip'),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_isLoading) const LinearProgressIndicator(minHeight: 3),
          Expanded(child: WebViewWidget(controller: _controller!)),
          Container(
            padding: const EdgeInsets.all(12),
            color: Theme.of(context).colorScheme.surface,
            child: Row(
              children: [
                Icon(
                  _isLoading ? Icons.hourglass_top : Icons.info_outline,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$_status (${_checkCount * 2}s elapsed)',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
