import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:benterm/ui/update_banner.dart';
import 'package:benterm/update/release_check.dart';
import 'package:benterm/update/update_service.dart';

/// An update service whose release check answers from a canned response.
UpdateService serviceReturning(
  http.Response response, {
  String current = '0.2.0',
}) {
  return UpdateService(
    releaseCheck: ReleaseCheck(client: MockClient((_) async => response)),
    currentVersionOverride: current,
  );
}

http.Response release(String tag) {
  return http.Response(
    jsonEncode({
      'tag_name': tag,
      'body': 'What changed in $tag',
      'assets': const <Object>[],
    }),
    200,
  );
}

Future<void> pumpBanner(WidgetTester tester, UpdateService service) async {
  await tester.pumpWidget(
    MaterialApp(home: Scaffold(body: UpdateBanner(service: service))),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('announces a newer release', (tester) async {
    await pumpBanner(tester, serviceReturning(release('v0.3.0')));

    expect(find.text('Version 0.3.0 is available'), findsOneWidget);
  });

  testWidgets('stays hidden when already current', (tester) async {
    await pumpBanner(tester, serviceReturning(release('v0.2.0')));

    expect(find.byType(UpdateBanner), findsOneWidget);
    expect(find.textContaining('is available'), findsNothing);
  });

  testWidgets('stays hidden when running a newer build than published', (
    tester,
  ) async {
    await pumpBanner(
      tester,
      serviceReturning(release('v0.2.0'), current: '0.3.0'),
    );

    expect(find.textContaining('is available'), findsNothing);
  });

  testWidgets('a failed check says nothing at all', (tester) async {
    // Being offline is not an error worth interrupting anyone over: the app
    // is perfectly usable without updating.
    await pumpBanner(
      tester,
      serviceReturning(http.Response('{"message":"rate limited"}', 403)),
    );

    expect(find.textContaining('is available'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('can be dismissed', (tester) async {
    await pumpBanner(tester, serviceReturning(release('v0.3.0')));

    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pump();

    expect(find.textContaining('is available'), findsNothing);
  });

  testWidgets('opens a dialog with the release notes', (tester) async {
    await pumpBanner(tester, serviceReturning(release('v0.3.0')));

    await tester.tap(find.widgetWithText(TextButton, 'View'));
    await tester.pumpAndSettle();

    expect(find.text('benterm 0.3.0'), findsOneWidget);
    expect(find.text('What changed in v0.3.0'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Update now'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Later'), findsOneWidget);
  });

  testWidgets('Later closes the dialog and leaves the banner', (tester) async {
    await pumpBanner(tester, serviceReturning(release('v0.3.0')));

    await tester.tap(find.widgetWithText(TextButton, 'View'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Later'));
    await tester.pumpAndSettle();

    expect(find.text('benterm 0.3.0'), findsNothing);
    expect(find.text('Version 0.3.0 is available'), findsOneWidget);
  });
}
