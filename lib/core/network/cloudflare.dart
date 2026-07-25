import 'dart:async';

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
    final body = response.data?.toString() ?? '';
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
    if (server.toLowerCase().contains('cloudflare') && body.contains('challenge')) {
      return true;
    }

    return false;
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
  Future<Map<String, String>?> _resolveWithWebView(BuildContext context, String url) async {
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
  late final WebViewController _controller;
  bool _isLoading = true;
  String _status = 'Loading...';
  Timer? _timeoutTimer;
  Timer? _checkTimer;
  int _checkCount = 0;

  @override
  void initState() {
    super.initState();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            setState(() {
              _isLoading = true;
              _status = 'Loading page...';
            });
          },
          onPageFinished: (url) {
            setState(() {
              _isLoading = false;
              _status = 'Checking for Cloudflare...';
            });
            _onPageFinished();
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));

    // Timeout after 5 minutes
    _timeoutTimer = Timer(const Duration(minutes: 5), () {
      widget.onTimeout();
    });
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    _checkTimer?.cancel();
    super.dispose();
  }

  void _onPageFinished() {
    // Try to auto-click Cloudflare Turnstile checkbox
    _controller.runJavaScript('''
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

    // Check for cf_clearance cookie periodically
    _checkTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _checkCount++;
      _checkCookies();

      // Give up after 150 checks (5 minutes)
      if (_checkCount > 150) {
        _checkTimer?.cancel();
        widget.onComplete({});
      }
    });
  }

  Future<void> _checkCookies() async {
    try {
      final cookieResult = await _controller.runJavaScriptReturningResult('document.cookie');
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

        _checkTimer?.cancel();
        _timeoutTimer?.cancel();
        widget.onComplete(cookies);
      }
    } catch (e) {
      // JS might not be ready yet
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cloudflare Verification'),
        actions: [
          TextButton(
            onPressed: () {
              _checkTimer?.cancel();
              _timeoutTimer?.cancel();
              widget.onComplete({});
            },
            child: const Text('Skip'),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_isLoading)
            const LinearProgressIndicator(minHeight: 3),
          Expanded(
            child: WebViewWidget(controller: _controller),
          ),
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
