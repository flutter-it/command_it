// ignore_for_file: deprecated_member_use, deprecated_member_use_from_same_package
// This file tests the deprecated API to ensure backward compatibility
// and maintain test coverage for deprecated methods until v10.0.0

import 'package:command_it/command_it.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Deprecated API Backward Compatibility Tests', () {
    test('execute() method works and forwards to run()', () async {
      var executionCount = 0;
      final command = Command.createAsyncNoParamNoResult(() async {
        executionCount++;
      });

      // Use deprecated execute() method
      command.execute();
      await Future<void>.delayed(Duration(milliseconds: 10));

      expect(executionCount, 1);
      command.dispose();
    });

    test('executeWithFuture() method returns Future', () async {
      final command = Command.createAsync<int, String>(
        (x) async {
          await Future<void>.delayed(Duration(milliseconds: 10));
          return 'result-$x';
        },
        initialValue: 'initial',
      );

      // Use deprecated executeWithFuture() method
      final future = command.executeWithFuture(42);
      final result = await future;

      expect(result, 'result-42');
      command.dispose();
    });

    test('isExecuting getter works', () async {
      final command = Command.createAsync<int, int>(
        (x) async {
          await Future<void>.delayed(Duration(milliseconds: 50));
          return x * 2;
        },
        initialValue: 0,
      );

      var wasExecuting = false;

      // Use deprecated isExecuting property
      command.isExecuting.listen((isExec, _) {
        if (isExec) wasExecuting = true;
      });

      command.run(21);
      await Future<void>.delayed(Duration(milliseconds: 10));

      expect(wasExecuting, true);
      await Future<void>.delayed(Duration(milliseconds: 100));
      command.dispose();
    });

    test('isExecutingSync getter works', () async {
      final command = Command.createAsync<int, int>(
        (x) async {
          await Future<void>.delayed(Duration(milliseconds: 50));
          return x * 2;
        },
        initialValue: 0,
      );

      var syncWasExecuting = false;

      // Use deprecated isExecutingSync property
      command.isExecutingSync.listen((isExec, _) {
        if (isExec) syncWasExecuting = true;
      });

      command.run(21);
      // isExecutingSync notifies synchronously
      expect(syncWasExecuting, true);

      await Future<void>.delayed(Duration(milliseconds: 100));
      command.dispose();
    });

    test('canExecute getter works', () {
      final restriction = ValueNotifier<bool>(false);
      final command = Command.createSync<int, int>(
        (x) => x * 2,
        initialValue: 0,
        restriction: restriction,
      );

      var canExecuteValues = <bool>[];

      // Use deprecated canExecute property
      command.canExecute.listen((canExec, _) {
        canExecuteValues.add(canExec);
      });

      // Trigger a change to get initial value
      restriction.value = true;
      expect(canExecuteValues.last, false);

      restriction.value = false;
      expect(canExecuteValues.last, true);

      restriction.value = true;
      expect(canExecuteValues.last, false);

      command.dispose();
      restriction.dispose();
    });

    test('thrownExceptions getter works', () async {
      final command = Command.createAsync<int, int>(
        (x) async {
          throw Exception('test error $x');
        },
        initialValue: 0,
      );

      CommandError<int>? caughtError;

      // Use deprecated thrownExceptions property
      command.thrownExceptions.listen((error, _) {
        if (error != null) caughtError = error;
      });

      command.run(42);
      await Future<void>.delayed(Duration(milliseconds: 50));

      expect(caughtError, isNotNull);
      expect(caughtError!.error.toString(), contains('test error 42'));
      command.dispose();
    });

    test('CommandResult.isExecuting getter works', () {
      const result = CommandResult<void, String>(null, 'data', null, true);

      // Use deprecated isExecuting getter on CommandResult
      expect(result.isExecuting, true);

      const notExecuting =
          CommandResult<void, String>(null, 'data', null, false);
      expect(notExecuting.isExecuting, false);
    });

    testWidgets('whileExecuting parameter in CommandBuilder works',
        (WidgetTester tester) async {
      final command = Command.createAsync<int, String>(
        (x) async {
          await Future<void>.delayed(Duration(milliseconds: 100));
          return 'done-$x';
        },
        initialValue: 'initial',
      );
      addTearDown(command.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CommandBuilder<int, String>(
              command: command,
              onData: (context, data, _) => Text(data),
              // Use deprecated whileExecuting parameter
              whileExecuting: (context, _, __) => const Text('loading'),
            ),
          ),
        ),
      );

      // Initial state
      expect(find.text('initial'), findsOneWidget);

      // Start execution
      command.run(42);
      await tester.pump();

      // Should show loading (via deprecated whileExecuting)
      expect(find.text('loading'), findsOneWidget);

      // Wait for completion
      await tester.pumpAndSettle();
      expect(find.text('done-42'), findsOneWidget);
    });

    testWidgets('whileExecuting in toWidget extension works',
        (WidgetTester tester) async {
      final command = Command.createAsync<int, String>(
        (x) async {
          await Future<void>.delayed(Duration(milliseconds: 100));
          return 'done-$x';
        },
        initialValue: 'initial',
      );
      addTearDown(command.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<CommandResult<int?, String>>(
              valueListenable: command.results,
              builder: (context, result, _) {
                return result.toWidget(
                  onData: (data, _) => Text(data),
                  // Use deprecated whileExecuting parameter
                  whileExecuting: (_, __) => const Text('loading'),
                );
              },
            ),
          ),
        ),
      );

      // Initial state
      expect(find.text('initial'), findsOneWidget);

      // Start execution
      command.run(42);
      await tester.pump(Duration(milliseconds: 10));

      // Should show loading (via deprecated whileExecuting)
      expect(find.text('loading'), findsOneWidget);

      // Wait for completion
      await tester.pumpAndSettle();
      expect(find.text('done-42'), findsOneWidget);
    });

    test('Command.toWidget whileExecuting parameter works', () {
      final command = Command.createAsync<int, String>(
        (x) async {
          await Future<void>.delayed(Duration(milliseconds: 50));
          return 'result-$x';
        },
        initialValue: 'initial',
      );

      // Use deprecated whileExecuting parameter in Command.toWidget
      final widget = command.toWidget(
        onResult: (result, _) => Text(result),
        whileExecuting: (_, __) => const Text('executing'),
      );

      expect(widget, isNotNull);

      command.dispose();
    });

    test('All deprecated properties work together', () async {
      final restriction = ValueNotifier<bool>(false);

      final command = Command.createAsync<int, int>(
        (x) async {
          await Future<void>.delayed(Duration(milliseconds: 10));
          return x * 2;
        },
        initialValue: 0,
        restriction: restriction,
      );

      var executingChanges = 0;

      // Use multiple deprecated properties together
      command.isExecuting.listen((isExec, _) => executingChanges++);
      command.canExecute.listen((_, __) {});
      command.thrownExceptions.listen((error, _) {});

      // Use deprecated execute method
      command.execute(21);
      await Future<void>.delayed(Duration(milliseconds: 50));

      expect(executingChanges, greaterThan(0));

      command.dispose();
      restriction.dispose();
    });

    test('MockCommand.execute() deprecated method works', () {
      final mockCommand = MockCommand<int, String>(
        initialValue: 'initial',
      );

      // Use deprecated execute() method on MockCommand
      mockCommand.execute(42);

      // Verify it was called
      expect(mockCommand.executionCount, 1);
      expect(mockCommand.lastPassedValueToExecute, 42);

      mockCommand.dispose();
    });

    test('CommandResult.isLoading() constructor works', () {
      // Test the isLoading named constructor
      const result = CommandResult<int, String>.isLoading(42);

      expect(result.paramData, 42);
      expect(result.data, null);
      expect(result.error, null);
      expect(result.isRunning, true);
    });

    test('CommandResult.blank() constructor works', () {
      // Test the blank named constructor
      const result = CommandResult<int, String>.blank();

      expect(result.paramData, null);
      expect(result.data, null);
      expect(result.error, null);
      expect(result.isRunning, false);
    });
  });
}
