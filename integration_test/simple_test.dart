import 'package:flutter_test/flutter_test.dart';
import 'package:chronos_app/main.dart';
import 'package:chronos_app/src/rust/frb_generated.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => await RustLib.init());
  testWidgets('Can initialize Chronos app', (WidgetTester tester) async {
    await tester.pumpWidget(const ChronosApp(isDbReady: true));
    expect(find.byType(ChronosApp), findsOneWidget);
  });
}
