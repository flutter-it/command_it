import 'package:command_it/command_it.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// This test demonstrates the Dart language limitation with callable classes
/// and function-typed parameters.
///
/// Command implements a call() method making it a callable class. When you
/// assign a Command instance to a function-typed parameter like VoidCallback,
/// Dart performs an **implicit tear-off of the call method**.
///
/// This triggers the `implicit_call_tearoffs` linter warning in stricter
/// configurations (like DartPad). This project doesn't enable that rule by
/// default, but it's considered a code smell because it's unclear that a
/// tear-off is happening.
///
/// **Recommended pattern**: Explicitly use `.run` (method tear-off) or
/// `() => command()` (lambda) to make the intent clear.
///
/// See: https://gist.github.com/escamoteur/e92fc4b2a0aaf4d180f46110543c6706
void main() {
  group('Command callable class assignment patterns', () {
    test('Demonstrate working patterns for VoidCallback assignment', () {
      // Create a command compatible with VoidCallback (no param, no result)
      var callCount = 0;
      final command = Command.createSyncNoParamNoResult(() {
        callCount++;
      });

      // ⚠️  IMPLICIT CALL TEAR-OFF - Direct assignment of callable class
      // This works at runtime but triggers linter warning in strict mode:
      // VoidCallback callback = command;  // Warning: implicit_call_tearoffs
      //
      // Dart implicitly tears off the .call() method, which is unclear.
      // Use explicit patterns below instead:

      // ✅ WORKS - Method tear-off
      VoidCallback methodTearOff = command.run;
      methodTearOff();
      expect(callCount, 1);

      // ✅ WORKS - Lambda wrapping
      VoidCallback lambda = () => command();
      lambda();
      expect(callCount, 2);

      // ✅ WORKS - Lambda calling run
      VoidCallback lambdaRun = () => command.run();
      lambdaRun();
      expect(callCount, 3);
    });

    testWidgets('Demonstrate patterns with Flutter widgets',
        (WidgetTester tester) async {
      var pressCount = 0;
      final command = Command.createSyncNoParamNoResult(() {
        pressCount++;
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                // ⚠️  IMPLICIT CALL TEAR-OFF - Triggers linter warning:
                // FloatingActionButton(
                //   onPressed: command,  // Warning: implicit_call_tearoffs
                //   child: Icon(Icons.add),
                // ),

                // ✅ WORKS - Method tear-off (RECOMMENDED)
                FloatingActionButton(
                  onPressed: command.run,
                  child: const Icon(Icons.add),
                ),

                // ✅ WORKS - Lambda wrapping
                TextButton(
                  onPressed: () => command(),
                  child: const Text('Press'),
                ),

                // ✅ WORKS - Lambda calling run
                ElevatedButton(
                  onPressed: () => command.run(),
                  child: const Text('Run'),
                ),
              ],
            ),
          ),
        ),
      );

      // Test method tear-off pattern
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump();
      expect(pressCount, 1);

      // Test lambda pattern
      await tester.tap(find.byType(TextButton));
      await tester.pump();
      expect(pressCount, 2);

      // Test lambda run pattern
      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();
      expect(pressCount, 3);

      // Dispose command and wait for async disposal to complete
      command.dispose();
      await tester.pumpAndSettle();
    });

    test('Demonstrate with nullable callback parameters', () {
      var callCount = 0;
      final command = Command.createSyncNoParamNoResult(() {
        callCount++;
      });

      // Custom widget-like class with nullable callback
      void processCallback(VoidCallback? callback) {
        callback?.call();
      }

      // ⚠️  IMPLICIT CALL TEAR-OFF - Triggers linter warning:
      // processCallback(command);  // Warning: implicit_call_tearoffs
      //
      // Works at runtime but unclear that call() is being torn off

      // ✅ WORKS - Method tear-off
      processCallback(command.run);
      expect(callCount, 1);

      // ✅ WORKS - Lambda
      processCallback(() => command());
      expect(callCount, 2);
    });

    test('Demonstrate with non-nullable callback parameters', () {
      var callCount = 0;
      final command = Command.createSyncNoParamNoResult(() {
        callCount++;
      });

      // Custom widget-like class with non-nullable callback
      void processCallback(VoidCallback callback) {
        callback();
      }

      // ⚠️  IMPLICIT CALL TEAR-OFF - Triggers linter warning:
      // processCallback(command);  // Warning: implicit_call_tearoffs
      //
      // Works at runtime but unclear that call() is being torn off

      // ✅ WORKS - Method tear-off
      processCallback(command.run);
      expect(callCount, 1);

      // ✅ WORKS - Lambda
      processCallback(() => command());
      expect(callCount, 2);
    });
  });

  group('Workaround patterns documentation', () {
    test('Recommended pattern: Use method tear-off', () {
      final command = Command.createSyncNoParamNoResult(() {});

      // This is the cleanest and recommended approach
      VoidCallback callback = command.run;

      expect(callback, isA<VoidCallback>());
    });

    test('Alternative pattern: Lambda wrapping', () {
      final command = Command.createSyncNoParamNoResult(() {});

      // This works but is more verbose
      VoidCallback callback = () => command();

      expect(callback, isA<VoidCallback>());
    });
  });
}
