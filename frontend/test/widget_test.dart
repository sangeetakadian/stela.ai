import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stela_app/main.dart';
import 'package:stela_app/splash.dart';

void main() {
  testWidgets('App builds and presents the splash screen',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(Splash), findsOneWidget);
  });
}
