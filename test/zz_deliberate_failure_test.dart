// Deliberately failing test: proves the deploy workflow stops before
// deploying when a test fails (CR-25 change 5). Never merge this branch.
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('deliberate failure', () => expect(1, 2));
}
