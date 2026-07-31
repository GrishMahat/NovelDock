import 'package:flutter_test/flutter_test.dart';

import 'package:noveldock/app.dart';

void main() {
  test('App smoke test', () {
    // App class should be constructable without errors
    expect(const NovelDockApp(), isA<NovelDockApp>());
  });
}
