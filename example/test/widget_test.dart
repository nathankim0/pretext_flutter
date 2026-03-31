import 'package:flutter_test/flutter_test.dart';

import 'package:pretext_flutter_example/main.dart';

void main() {
  testWidgets('launcher renders demo cards', (WidgetTester tester) async {
    await tester.pumpWidget(const PretextDemoApp());

    expect(find.text('Editorial Engine'), findsOneWidget);
    expect(find.text('Bubbles'), findsOneWidget);
  });
}
