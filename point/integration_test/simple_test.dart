import 'package:flutter_test/flutter_test.dart';
import 'package:point/main.dart';
import 'package:point/src/rust/frb_generated.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => await RustLib.init());
  testWidgets('Can call rust function', (WidgetTester tester) async {
    await tester.pumpWidget(const PointApp());
    expect(find.text('Point'), findsWidgets);
  });
}
