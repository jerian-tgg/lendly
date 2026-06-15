import 'package:flutter_test/flutter_test.dart';
import 'package:lendly/main.dart';

void main() {
  testWidgets('Ensure app compiles', (WidgetTester tester) async {
    // This just verifies the app structure compiles properly
    const app = MyApp();
    expect(app, isNotNull);
  });
}
