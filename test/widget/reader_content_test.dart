// Widget-level test for chapter image headers: proves the Cookie map
// resolved at load time actually reaches Image.network in the renderer.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:noveldock/core/content/content_model.dart';
import 'package:noveldock/core/tts/tts_manager.dart';
import 'package:noveldock/features/reader/widgets/reader_content_view.dart';
import 'package:noveldock/features/settings/pages/reader/reader_settings_state.dart';

// 1x1 transparent PNG (same bytes as package:transparent_image).
const _kTransparentPng = <int>[
  137,
  80,
  78,
  71,
  13,
  10,
  26,
  10,
  0,
  0,
  0,
  13,
  73,
  72,
  68,
  82,
  0,
  0,
  0,
  1,
  0,
  0,
  0,
  1,
  8,
  6,
  0,
  0,
  0,
  31,
  21,
  196,
  137,
  0,
  0,
  0,
  13,
  73,
  68,
  65,
  84,
  120,
  156,
  99,
  250,
  207,
  192,
  0,
  8,
  247,
  72,
  178,
  56,
  49,
  0,
  0,
  35,
  4,
  3,
  37,
  161,
  214,
  164,
  0,
  0,
  0,
  0,
  73,
  69,
  78,
  68,
  174,
  66,
  96,
  130,
];

class _FakeHttpHeaders extends Fake implements HttpHeaders {}

class _FakeHttpResponse extends Fake implements HttpClientResponse {
  final _stream = Stream<List<int>>.value(_kTransparentPng);

  @override
  int get statusCode => HttpStatus.ok;

  @override
  int get contentLength => _kTransparentPng.length;

  @override
  HttpHeaders get headers => _FakeHttpHeaders();

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
}

class _FakeHttpRequest extends Fake implements HttpClientRequest {
  @override
  HttpHeaders get headers => _FakeHttpHeaders();

  @override
  Future<HttpClientResponse> close() async => _FakeHttpResponse();
}

class _FakeHttpClient extends Fake implements HttpClient {
  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _FakeHttpRequest();
}

void main() {
  testWidgets('body images receive the chapter Cookie headers', (tester) async {
    const content = ChapterContent(
      format: ContentFormat.markdown,
      data: '# Title\n\nSome text.\n\n![alt](https://novels.example/i.png)\n',
      chapterId: 7,
      imageHeaders: {'Cookie': 'cf_clearance=abc'},
    );

    await HttpOverrides.runZoned(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: buildChapterContent(
                content: content,
                currentChapterId: 7,
                settings: const ReaderSettings(),
                ttsState: const TtsManagerState(),
                chunkKeys: {},
                settingsVersion: 1,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }, createHttpClient: (_) => _FakeHttpClient());

    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as NetworkImage).headers, {
      'Cookie': 'cf_clearance=abc',
    });
  });

  testWidgets('no headers means a plain image request', (tester) async {
    const content = ChapterContent(
      format: ContentFormat.markdown,
      data: '![alt](https://novels.example/i.png)\n',
      chapterId: 7,
    );

    await HttpOverrides.runZoned(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: buildChapterContent(
                content: content,
                currentChapterId: 7,
                settings: const ReaderSettings(),
                ttsState: const TtsManagerState(),
                chunkKeys: {},
                settingsVersion: 1,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }, createHttpClient: (_) => _FakeHttpClient());

    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as NetworkImage).headers, isNull);
  });
}
