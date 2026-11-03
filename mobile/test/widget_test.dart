import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/shared/ui/ui.dart';

Widget _host(Widget child, Brightness b) => MaterialApp(
      theme: b == Brightness.dark ? AppTheme.dark() : AppTheme.light(),
      home: CupertinoPageScaffold(child: SafeArea(child: child)),
    );

void main() {
  for (final b in Brightness.values) {
    testWidgets('kit renders in ${b.name} mode', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_host(
        ListView(children: [
          RxButton(label: 'Start', onPressed: () => taps++),
          const RxButton(label: 'Disabled', onPressed: null),
          const RxSection(header: 'Section', children: [
            RxTile(title: 'Row', detail: '3', icon: CupertinoIcons.car),
          ]),
          const RxEmptyState(icon: CupertinoIcons.flag, title: 'Empty'),
          const RxRideStatusPill(status: 'live'),
          const RxAvatar(name: 'Alex Driver'),
          const RxMetric(value: '42', unit: 'km/h', label: 'Speed'),
        ]),
        b,
      ));
      expect(find.text('Start'), findsOneWidget);
      expect(find.text('SECTION'), findsOneWidget);
      expect(find.text('LIVE'), findsOneWidget);
      expect(find.text('AD'), findsOneWidget);

      await tester.tap(find.text('Start'));
      await tester.tap(find.text('Disabled'));
      expect(taps, 1);
      expect(tester.takeException(), isNull);
    });
  }

  test('palette meets basic contrast expectations', () {
    final light = RxPalette.of(Brightness.light);
    final dark = RxPalette.of(Brightness.dark);
    expect(light.label, const Color(0xFF000000));
    expect(dark.background, const Color(0xFF000000));
    expect(light.accent, isNot(dark.accent));
  });
}
