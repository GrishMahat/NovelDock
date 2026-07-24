import 'package:flutter_test/flutter_test.dart';

import 'package:quicknovel/app.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const QuickNovelApp());
    // App should render without errors
    expect(find.text('QuickNovel'), findsOneWidget);
  });
}
