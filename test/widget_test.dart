import 'package:flutter_test/flutter_test.dart';

import 'package:noveldock/app.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const NovelDockApp());
    // App should render without errors
    expect(find.text('NovelDock'), findsOneWidget);
  });
}
