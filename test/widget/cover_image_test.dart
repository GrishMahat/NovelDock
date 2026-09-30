import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noveldock/widgets/cover_image.dart';

void main() {
  group('CoverImage.isLocalPath', () {
    test('absolute paths and file URIs are local', () {
      expect(CoverImage.isLocalPath('/data/covers/1.jpg'), isTrue);
      expect(CoverImage.isLocalPath('file:///data/covers/1.jpg'), isTrue);
    });

    test('http(s) URLs are remote', () {
      expect(CoverImage.isLocalPath('https://x.com/c.jpg'), isFalse);
      expect(CoverImage.isLocalPath('http://x.com/c.jpg'), isFalse);
    });
  });

  group('CoverImage widget', () {
    testWidgets('null url shows the book-icon placeholder', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: CoverImage(width: 40, height: 56)),
        ),
      );
      expect(find.byIcon(Icons.book), findsOneWidget);
      expect(find.byType(RawImage), findsNothing);
    });

    testWidgets('empty url shows the book-icon placeholder', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: CoverImage(imageUrl: '', width: 40, height: 56)),
        ),
      );
      expect(find.byIcon(Icons.book), findsOneWidget);
      expect(find.byType(RawImage), findsNothing);
    });
  });
}
