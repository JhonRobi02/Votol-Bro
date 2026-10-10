import 'package:flutter_test/flutter_test.dart';
import 'package:votol_config/main.dart';

void main() {
  testWidgets('shows the Votol Bros home screen', (tester) async {
    await tester.pumpWidget(const VotolApp());
    await tester.pump();

    expect(find.text('Votol Bros'), findsOneWidget);
  });
}
