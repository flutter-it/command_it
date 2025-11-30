// ignore_for_file: avoid_print

import 'package:command_it/command_it.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Helper to collect values emitted by a ValueListenable
class Collector<T> {
  List<T>? values;

  void call(T value) {
    values ??= <T>[];
    values!.add(value);
  }

  void clear() {
    values?.clear();
  }

  void reset() {
    clear();
    values = null;
  }
}

void main() {
  group('Pipe Extension', () {
    group('Basic functionality', () {
      test('Basic pipe: Command A result triggers Command B', () {
        fakeAsync((async) {
          var targetExecutionCount = 0;
          String? receivedParam;

          // Source command returns a String
          final sourceCommand = Command.createAsync<String, String>(
            (param) async {
              await Future<void>.delayed(const Duration(milliseconds: 10));
              return 'result_$param';
            },
            initialValue: '',
          );

          // Target command receives a String
          final targetCommand = Command.createAsyncNoResult<String>(
            (param) async {
              targetExecutionCount++;
              receivedParam = param;
            },
          );

          // Pipe source to target
          sourceCommand.pipeToCommand(targetCommand);

          // Execute source command
          sourceCommand.run('input');

          // Wait for source to complete
          async.elapse(const Duration(milliseconds: 20));

          // Target should have been triggered with source's result
          expect(targetExecutionCount, 1);
          expect(receivedParam, 'result_input');
        });
      });

      test('Pipe with transform function', () {
        fakeAsync((async) {
          var targetExecutionCount = 0;
          int? receivedParam;

          // Source command returns a String
          final sourceCommand = Command.createAsync<String, String>(
            (param) async {
              await Future<void>.delayed(const Duration(milliseconds: 10));
              return param;
            },
            initialValue: '',
          );

          // Target command receives an int
          final targetCommand = Command.createAsyncNoResult<int>(
            (param) async {
              targetExecutionCount++;
              receivedParam = param;
            },
          );

          // Pipe with transform: String -> int (length)
          sourceCommand.pipeToCommand(targetCommand,
              transform: (s) => s.length);

          // Execute source command
          sourceCommand.run('hello');

          // Wait for source to complete
          async.elapse(const Duration(milliseconds: 20));

          // Target should have been triggered with transformed value
          expect(targetExecutionCount, 1);
          expect(receivedParam, 5); // 'hello'.length
        });
      });

      test('Pipe without transform - types match, value passed directly', () {
        fakeAsync((async) {
          int? receivedParam;

          final sourceCommand = Command.createAsync<int, int>(
            (param) async {
              await Future<void>.delayed(const Duration(milliseconds: 10));
              return param * 2;
            },
            initialValue: 0,
          );

          final targetCommand = Command.createAsyncNoResult<int>(
            (param) async {
              receivedParam = param;
            },
          );

          // No transform - types match (int -> int)
          sourceCommand.pipeToCommand(targetCommand);

          sourceCommand.run(21);
          async.elapse(const Duration(milliseconds: 20));

          expect(receivedParam, 42); // 21 * 2
        });
      });

      test(
          'Pipe without transform - types dont match, calls run() without param',
          () {
        fakeAsync((async) {
          var targetExecutionCount = 0;

          // Source returns String
          final sourceCommand = Command.createAsync<String, String>(
            (param) async {
              await Future<void>.delayed(const Duration(milliseconds: 10));
              return param;
            },
            initialValue: '',
          );

          // Target takes no param (void)
          final targetCommand = Command.createAsyncNoParamNoResult(
            () async {
              targetExecutionCount++;
            },
          );

          // No transform, types don't match - should call run() without param
          sourceCommand.pipeToCommand(targetCommand);

          sourceCommand.run('trigger');
          async.elapse(const Duration(milliseconds: 20));

          expect(targetExecutionCount, 1);
        });
      });
    });

    group('Different source ValueListenables', () {
      test('Pipe from command.isRunning triggers on execution state change',
          () {
        fakeAsync((async) {
          final isRunningValues = <bool>[];

          final sourceCommand = Command.createAsync<void, String>(
            (_) async {
              await Future<void>.delayed(const Duration(milliseconds: 10));
              return 'done';
            },
            initialValue: '',
          );

          // Target command collects the isRunning values
          final targetCommand = Command.createSyncNoResult<bool>(
            (running) {
              isRunningValues.add(running);
            },
          );

          // Pipe isRunning to target
          sourceCommand.isRunning.pipeToCommand(targetCommand);

          sourceCommand.run();
          async.elapse(const Duration(milliseconds: 5));

          // Should have fired with true when execution started
          expect(isRunningValues, contains(true));

          async.elapse(const Duration(milliseconds: 10));

          // Should have fired with false when execution completed
          expect(isRunningValues, contains(false));
        });
      });

      test('Pipe from command.results triggers on every state change', () {
        fakeAsync((async) {
          final resultStates = <String>[];

          final sourceCommand = Command.createAsync<String, String>(
            (param) async {
              await Future<void>.delayed(const Duration(milliseconds: 10));
              return 'result_$param';
            },
            initialValue: 'initial',
          );

          // Target collects result states
          final targetCommand =
              Command.createSyncNoResult<CommandResult<String?, String>>(
            (result) {
              if (result.isRunning) {
                resultStates.add('loading');
              } else if (result.hasData) {
                resultStates.add('data:${result.data}');
              }
            },
          );

          // Pipe results to target
          sourceCommand.results.pipeToCommand(targetCommand);

          sourceCommand.run('test');
          async.elapse(const Duration(milliseconds: 20));

          // Should have captured loading and data states
          expect(resultStates, contains('loading'));
          expect(resultStates, contains('data:result_test'));
        });
      });
    });

    group('Subscription management', () {
      test('Cancel subscription stops piping', () {
        fakeAsync((async) {
          var targetExecutionCount = 0;

          final sourceCommand = Command.createAsync<String, String>(
            (param) async {
              await Future<void>.delayed(const Duration(milliseconds: 10));
              return param;
            },
            initialValue: '',
          );

          final targetCommand = Command.createAsyncNoParamNoResult(
            () async {
              targetExecutionCount++;
            },
          );

          // Pipe and get subscription
          final subscription = sourceCommand.pipeToCommand(targetCommand);

          // First execution - should trigger target
          sourceCommand.run('first');
          async.elapse(const Duration(milliseconds: 20));
          expect(targetExecutionCount, 1);

          // Cancel the subscription
          subscription.cancel();

          // Second execution - should NOT trigger target
          sourceCommand.run('second');
          async.elapse(const Duration(milliseconds: 20));
          expect(targetExecutionCount, 1); // Still 1, not 2
        });
      });

      test('Multiple pipes from same source all fire', () {
        fakeAsync((async) {
          var target1Count = 0;
          var target2Count = 0;

          final sourceCommand = Command.createAsync<String, String>(
            (param) async {
              await Future<void>.delayed(const Duration(milliseconds: 10));
              return param;
            },
            initialValue: '',
          );

          final target1 = Command.createAsyncNoParamNoResult(() async {
            target1Count++;
          });

          final target2 = Command.createAsyncNoParamNoResult(() async {
            target2Count++;
          });

          // Pipe to both targets
          sourceCommand.pipeToCommand(target1);
          sourceCommand.pipeToCommand(target2);

          sourceCommand.run('trigger');
          async.elapse(const Duration(milliseconds: 20));

          expect(target1Count, 1);
          expect(target2Count, 1);
        });
      });

      test('Disposing source command stops pipe from firing', () {
        fakeAsync((async) {
          var targetExecutionCount = 0;

          final sourceCommand = Command.createAsync<String, String>(
            (param) async {
              await Future<void>.delayed(const Duration(milliseconds: 10));
              return param;
            },
            initialValue: '',
          );

          final targetCommand = Command.createAsyncNoParamNoResult(
            () async {
              targetExecutionCount++;
            },
          );

          sourceCommand.pipeToCommand(targetCommand);

          // First execution
          sourceCommand.run('first');
          async.elapse(const Duration(milliseconds: 20));
          expect(targetExecutionCount, 1);

          // Dispose source command
          sourceCommand.dispose();

          // Wait for disposal to complete (command_it has 50ms delay)
          async.elapse(const Duration(milliseconds: 100));

          // Trying to run after dispose should not trigger target
          // (actually source.run won't work after dispose, but pipe should be cleaned up)
          expect(targetExecutionCount, 1);
        });
      });
    });

    group('Chaining', () {
      test('Chain of pipes: A -> B -> C', () {
        fakeAsync((async) {
          final collector = Collector<int>();

          // Command A: doubles the input
          final commandA = Command.createAsync<int, int>(
            (x) async {
              await Future<void>.delayed(const Duration(milliseconds: 10));
              return x * 2;
            },
            initialValue: 0,
          );

          // Command B: adds 10
          final commandB = Command.createAsync<int, int>(
            (x) async {
              await Future<void>.delayed(const Duration(milliseconds: 10));
              return x + 10;
            },
            initialValue: 0,
          );

          // Command C: collects the result
          final commandC = Command.createSyncNoResult<int>(
            (x) {
              collector(x);
            },
          );

          // Chain: A -> B -> C
          commandA.pipeToCommand(commandB);
          commandB.pipeToCommand(commandC);

          // Start with 5: A(5) = 10, B(10) = 20, C collects 20
          commandA.run(5);

          // Wait for full chain to complete
          async.elapse(const Duration(milliseconds: 50));

          expect(collector.values, [20]);
        });
      });
    });

    group('Error handling', () {
      test('Pipe does not fire when source command errors', () {
        fakeAsync((async) {
          // Set up global error handler to avoid assertion
          Command.globalExceptionHandler = (e, s) {};

          var targetExecutionCount = 0;

          final sourceCommand = Command.createAsync<String, String>(
            (param) async {
              await Future<void>.delayed(const Duration(milliseconds: 10));
              throw Exception('Source error');
            },
            initialValue: '',
          );

          final targetCommand = Command.createAsyncNoParamNoResult(
            () async {
              targetExecutionCount++;
            },
          );

          sourceCommand.pipeToCommand(targetCommand);

          sourceCommand.run('trigger');
          async.elapse(const Duration(milliseconds: 20));

          // Target should NOT have been triggered because source errored
          // (Command doesn't emit value on error)
          expect(targetExecutionCount, 0);

          // Clean up
          Command.globalExceptionHandler = null;
        });
      });

      test('Target command error does not affect source', () {
        fakeAsync((async) {
          // Set up global error handler to avoid assertion
          Command.globalExceptionHandler = (e, s) {};

          var sourceCompleted = false;
          String? sourceResult;

          final sourceCommand = Command.createAsync<String, String>(
            (param) async {
              await Future<void>.delayed(const Duration(milliseconds: 10));
              sourceCompleted = true;
              return 'success';
            },
            initialValue: '',
          );

          sourceCommand.listen((value, _) {
            sourceResult = value;
          });

          final targetCommand = Command.createAsyncNoResult<String>(
            (param) async {
              throw Exception('Target error');
            },
          );

          sourceCommand.pipeToCommand(targetCommand);

          sourceCommand.run('trigger');
          async.elapse(const Duration(milliseconds: 20));

          // Source should have completed successfully
          expect(sourceCompleted, true);
          expect(sourceResult, 'success');

          // Clean up
          Command.globalExceptionHandler = null;
        });
      });
    });

    group('Edge cases', () {
      test('Pipe from sync command works', () {
        var targetExecutionCount = 0;
        String? receivedParam;

        final sourceCommand = Command.createSync<String, String>(
          (param) => 'sync_$param',
          initialValue: '',
        );

        final targetCommand = Command.createSyncNoResult<String>(
          (param) {
            targetExecutionCount++;
            receivedParam = param;
          },
        );

        sourceCommand.pipeToCommand(targetCommand);

        sourceCommand.run('test');

        expect(targetExecutionCount, 1);
        expect(receivedParam, 'sync_test');
      });

      test('Pipe from ValueNotifier works', () {
        var targetExecutionCount = 0;
        int? receivedParam;

        final valueNotifier = ValueNotifier<int>(0);

        final targetCommand = Command.createSyncNoResult<int>(
          (param) {
            targetExecutionCount++;
            receivedParam = param;
          },
        );

        valueNotifier.pipeToCommand(targetCommand);

        valueNotifier.value = 42;

        expect(targetExecutionCount, 1);
        expect(receivedParam, 42);
      });
    });
  });
}
